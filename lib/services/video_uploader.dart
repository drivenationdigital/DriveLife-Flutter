import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Pushes a video file to Cloudflare Stream, resumably.
///
/// ── WHY tus AND NOT A PLAIN POST ────────────────────────────────────
///
/// Cloudflare's simple direct upload caps at 200MB. "No limit on
/// length" means files well past that, so this speaks tus instead,
/// which has no such cap.
///
/// The cap is the reason it was chosen and resumability is the reason
/// it is worth it. A two-gigabyte upload over a phone connection will
/// be interrupted - a tunnel, a lift, a call - and without resume
/// every interruption means starting again from zero. With it, the
/// upload picks up from wherever Cloudflare says it got to.
///
/// ── WHY tus IS SPOKEN DIRECTLY RATHER THAN THROUGH A PACKAGE ────────
///
/// Because the part of tus needed here is two requests, and the
/// alternative is a dependency to own the one thing that must not
/// break. HEAD to ask the offset, PATCH to send from it. That is the
/// whole protocol as used here.
///
/// ── AND NOTHING HERE HOLDS THE FILE IN MEMORY ───────────────────────
///
/// Chunks are read from a [RandomAccessFile] at an offset. Reading a
/// two-gigabyte video into a list to upload it would be killed by the
/// OS long before it finished, and that is exactly the size of file
/// this exists to carry.
class VideoUploader {
  /// How much to send per request.
  ///
  /// tus requires every chunk but the last to be a multiple of 256KB,
  /// and Cloudflare recommends at least 5MB. 16MB is a compromise:
  /// large enough that the per-request overhead disappears, small
  /// enough that a dropped connection loses seconds rather than
  /// minutes of work.
  static const int chunkSize = 16 * 1024 * 1024;

  /// Cancels an upload in progress.
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  /// Sends [file] to [uploadUrl], reporting progress 0..1.
  ///
  /// Returns true when Cloudflare has the whole file. Never throws:
  /// a failed upload is an ordinary outcome on a phone, and the
  /// screen handles it by offering to try again - which resumes
  /// rather than restarts.
  /// [onProgress] receives the fraction done AND the bytes sent so
  /// far, because an estimate of time remaining needs the second one
  /// and cannot recover it from the first without knowing the total.
  Future<bool> upload({
    required File file,
    required String uploadUrl,
    void Function(double progress, int sentBytes, int totalBytes)? onProgress,
  }) async {
    _cancelled = false;

    final int total;

    try {
      total = await file.length();
    } catch (e) {
      debugPrint('[upload] could not read the file: $e');

      return false;
    }

    if (total <= 0) return false;

    // Where Cloudflare thinks we are. Zero on a fresh upload, and
    // wherever it got to on a resumed one - which is why this is
    // asked rather than assumed.
    // Read into a non-nullable local. Kept separate because $offset
    // is reassigned inside the loop below, and a nullable local that
    // is written to does not stay promoted.
    final start = await _offset(uploadUrl);

    if (start == null) return false;

    var offset = start;

    if (offset >= total) {
      onProgress?.call(1, total, total);

      return true;
    }

    RandomAccessFile handle;

    try {
      handle = await file.open();
    } catch (e) {
      debugPrint('[upload] could not open the file: $e');

      return false;
    }

    try {
      while (offset < total) {
        if (_cancelled) return false;

        final remaining = total - offset;
        final size = remaining < chunkSize ? remaining : chunkSize;

        await handle.setPosition(offset);

        final chunk = await handle.read(size);

        final next = await _send(uploadUrl, offset, chunk);

        if (next == null) {
          // One retry, after asking Cloudflare where it actually got
          // to. A chunk can fail having been partly accepted, and
          // resending from our own idea of the offset would then
          // corrupt the file.
          final actual = await _offset(uploadUrl);

          if (actual == null || actual <= offset) return false;

          offset = actual;

          continue;
        }

        offset = next;

        onProgress?.call(offset / total, offset, total);
      }

      return true;
    } catch (e) {
      debugPrint('[upload] failed at $offset of $total: $e');

      return false;
    } finally {
      await handle.close();
    }
  }

  /// Asks how much Cloudflare already has.
  Future<int?> _offset(String uploadUrl) async {
    try {
      final response = await http
          .head(
            Uri.parse(uploadUrl),
            headers: {'Tus-Resumable': '1.0.0'},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200 && response.statusCode != 204) {
        debugPrint('[upload] HEAD said ${response.statusCode}');

        return null;
      }

      return int.tryParse(response.headers['upload-offset'] ?? '') ?? 0;
    } catch (e) {
      debugPrint('[upload] could not read the offset: $e');

      return null;
    }
  }

  /// Sends one chunk and returns the new offset.
  Future<int?> _send(String uploadUrl, int offset, List<int> chunk) async {
    try {
      final response = await http
          .patch(
            Uri.parse(uploadUrl),
            headers: {
              'Tus-Resumable': '1.0.0',
              'Upload-Offset': '$offset',
              'Content-Type': 'application/offset+octet-stream',
            },
            body: chunk,
          )
          // Generous: this is up to 16MB on whatever connection the
          // phone has. Too short here turns a slow upload into a
          // failed one.
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 204 && response.statusCode != 200) {
        debugPrint('[upload] PATCH said ${response.statusCode}');

        return null;
      }

      final next = int.tryParse(response.headers['upload-offset'] ?? '');

      // No offset back means we cannot know where we are, and guessing
      // is how a file ends up silently corrupt.
      if (next == null) return null;

      return next;
    } catch (e) {
      debugPrint('[upload] chunk at $offset failed: $e');

      return null;
    }
  }
}
