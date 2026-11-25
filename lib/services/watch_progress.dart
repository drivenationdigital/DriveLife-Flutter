import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How far through each video somebody has watched.
///
/// ── WHY THIS IS ON THE DEVICE AND NOT THE SERVER ────────────────────
///
/// For now, because there is no endpoint. When there is one, this
/// becomes the cache in front of it rather than being replaced: a
/// resume position has to be readable BEFORE the network answers, or
/// the player starts at zero and jumps a second later, which is worse
/// than not resuming at all.
///
/// ── WHAT IT DELIBERATELY DOES NOT REMEMBER ──────────────────────────
///
/// A position within a few seconds of the start, and a position within
/// the last thirty seconds of the end.
///
/// The first because resuming at 0:03 is not resuming, it is noise in
/// the UI telling somebody they have watched something they have not.
/// The second because finishing a video and being offered to resume it
/// at 58:40 is the app failing to notice you are done. Past that
/// point it is marked FINISHED instead, which is its own answer.
class WatchProgress {
  WatchProgress._();

  static const String _key = 'video_watch_progress_v1';

  /// Below this, there is nothing worth resuming.
  static const int _minimumSeconds = 10;

  /// Within this much of the end, treat it as watched.
  static const int _finishedSlack = 30;

  /// Cached in memory so a list of cards does not hit disk per card.
  static Map<String, int>? _cache;

  static Future<Map<String, int>> _all() async {
    final cached = _cache;

    if (cached != null) return cached;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);

      if (raw == null || raw.isEmpty) return _cache = {};

      final decoded = jsonDecode(raw);

      if (decoded is! Map) return _cache = {};

      return _cache = {
        for (final entry in decoded.entries)
          '${entry.key}': int.tryParse('${entry.value}') ?? 0,
      };
    } catch (e) {
      // A corrupt store is not worth a crash on a screen that works
      // perfectly well starting every video at the beginning.
      debugPrint('[watch] could not read progress: $e');

      return _cache = {};
    }
  }

  /// Where to resume [postId], or null to start at the beginning.
  static Future<int?> positionFor(String postId) async {
    final all = await _all();
    final seconds = all[postId];

    if (seconds == null || seconds < _minimumSeconds) return null;

    return seconds;
  }

  /// Everything known, for drawing progress bars on a row of cards.
  static Future<Map<String, int>> positions() => _all();

  /// Records where they got to.
  ///
  /// Called often - once every few seconds while something plays - so
  /// it writes to memory every time and to disk only when the value
  /// has actually moved. SharedPreferences serialises the whole map on
  /// every write, and doing that at 1Hz while a video plays is a
  /// measurable cost for no benefit.
  static Future<void> save({
    required String postId,
    required int seconds,
    required int durationSeconds,
  }) async {
    if (postId.isEmpty) return;

    final all = await _all();

    // Finished. Dropped rather than stored, so the next open starts
    // clean and no card shows a 99% bar forever.
    if (durationSeconds > 0 &&
        seconds >= durationSeconds - _finishedSlack) {
      if (all.remove(postId) != null) await _flush(all);

      return;
    }

    if (seconds < _minimumSeconds) return;

    // Only on a real change, and only per whole second.
    if (all[postId] == seconds) return;

    all[postId] = seconds;

    await _flush(all);
  }

  /// Forgets one video, for a "start from the beginning" control.
  static Future<void> clear(String postId) async {
    final all = await _all();

    if (all.remove(postId) != null) await _flush(all);
  }

  static Future<void> _flush(Map<String, int> all) async {
    _cache = all;

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_key, jsonEncode(all));
    } catch (e) {
      // The in-memory copy still works for this session.
      debugPrint('[watch] could not save progress: $e');
    }
  }

  @visibleForTesting
  static void resetForTest() => _cache = null;
}
