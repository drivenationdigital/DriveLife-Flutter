import 'dart:io';
import 'dart:ui' as ui;

import 'package:drivelife/services/upload_quality_prefs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

/// Pixel dimensions of an image, read from its header.
class ImageSize {
  final int width;
  final int height;
  const ImageSize(this.width, this.height);

  int get longEdge => width > height ? width : height;
  int get megapixels => (width * height) ~/ 1000000;
}

/// The outcome of preparing one image for upload.
class CompressedImage {
  final File file;
  final ImageSize? size;

  /// False when the original was uploaded untouched — the normal case.
  final bool recompressed;

  const CompressedImage({
    required this.file,
    required this.recompressed,
    this.size,
  });
}

/// Prepares media for upload.
///
/// Policy, in order:
///
///  1. **Low and medium quality sources are never touched.** A screenshot or an
///     already-compressed photo has nothing left to give; re-encoding it only
///     costs another generation of artefacts.
///  2. **High quality sources pass through when the user asked for it.** With
///     "High quality uploads" on, the only ceiling is Cloudflare's own — under
///     it, the file is uploaded byte-for-byte, EXIF and all.
///  3. **Everything else is re-encoded only as far as it takes** to satisfy
///     either the standard tier's target or Cloudflare's hard limits.
///
/// Keeping the original bytes also preserves the date and GPS tags the AI
/// recognition pipeline scores on.
class MediaCompressor {
  MediaCompressor._();

  // ── Cloudflare Images limits ───────────────────────────────────────────────

  /// Cloudflare Images rejects uploads above this.
  static const int _cloudflareMaxBytes = 10 * 1024 * 1024;

  /// Pass-through ceiling, a little under the hard limit so multipart overhead
  /// can't push a borderline file over on the wire.
  static const int _passThroughLimit = 9 * 1024 * 1024 + 512 * 1024;

  /// Cloudflare also caps dimensions (12,000px per side) and total area
  /// (100 megapixels). A panorama can clear the size limit and still fail on
  /// these, so they are part of the same check.
  static const int _cloudflareMaxEdge = 12000;
  static const int _cloudflareMaxMegapixels = 100;

  /// Formats Cloudflare Images accepts. Anything else must be transcoded —
  /// notably HEIC, which iOS returns by default and Cloudflare rejects.
  static const Set<String> _passThroughFormats = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
  };

  // ── Tier thresholds ────────────────────────────────────────────────────────

  /// What counts as a "high quality" source on the standard tier. Below both of
  /// these the file is left alone: there is no meaningful data saving to be had,
  /// and the re-encode would be a pure quality loss.
  static const int _standardHighQualityEdge = 3200;
  static const int _standardHighQualityBytes = 4 * 1024 * 1024;

  /// Where the standard tier lands a source it decided to re-encode. Still
  /// comfortably above what any phone screen resolves.
  static const int _standardMaxEdge = 3200;

  /// The high tier only resizes when a file is too big for Cloudflare as it
  /// stands, and then only as far as it takes to fit.
  static const int _highMaxEdge = 4608;

  /// Quality ladders for the re-encode path, tried in order until the result
  /// fits under the Cloudflare limit.
  static const List<int> _highLadder = [95, 92, 88, 84, 78];
  static const List<int> _standardLadder = [92, 88, 84, 78];

  // ── Video thresholds ───────────────────────────────────────────────────────

  /// A clip at or below 1080p is uploaded untouched on BOTH tiers.
  ///
  /// Cloudflare Stream never upscales — its rendition ladder tops out at
  /// whatever we upload — so a local pass sets a permanent ceiling on playback
  /// quality. Phones shoot 1080p, and re-encoding that to 720p before upload is
  /// where the quality actually went. Stream builds its own 720p and 480p rungs
  /// from a 1080p master anyway, so nothing is saved by doing it here.
  static const int _videoPassThroughEdge = 1920;

  /// …unless it is so large that the upload itself becomes the problem.
  ///
  /// These are bitrate ceilings expressed as bytes, sized against the 2 minute
  /// duration cap in create_post_screen.dart — roughly 30 Mbps on the high tier
  /// and 8 Mbps on standard. If the duration cap moves, move these with it, or
  /// ordinary clips start tripping the threshold and getting re-encoded for no
  /// reason.
  static const int _videoPassThroughBytesHigh = 440 * 1024 * 1024;
  static const int _videoPassThroughBytesStandard = 120 * 1024 * 1024;

  static bool _canPassThrough(File file) {
    final path = file.path;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    return _passThroughFormats.contains(path.substring(dot + 1).toLowerCase());
  }

  /// Whether Cloudflare Images would accept the file as it stands.
  ///
  /// An unreadable size is treated as acceptable: the formats whose headers we
  /// cannot parse are the ones being transcoded anyway.
  static bool _withinCloudflareLimits(int bytes, ImageSize? size) {
    if (bytes > _passThroughLimit) return false;
    if (size == null) return true;
    return size.longEdge <= _cloudflareMaxEdge &&
        size.megapixels <= _cloudflareMaxMegapixels;
  }

  /// Whether a source carries enough detail for the standard tier's resize to be
  /// worth the generation it costs.
  static bool _isHighQualitySource(int bytes, ImageSize? size) {
    if (bytes > _standardHighQualityBytes) return true;
    return size != null && size.longEdge > _standardHighQualityEdge;
  }

  /// Reads width/height from the file header without decoding the pixels.
  ///
  /// A full decode of a 45MP photo allocates ~180MB, which is exactly the kind
  /// of spike that kills the picker on mid-range Android.
  static Future<ImageSize?> readSize(File file) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return ImageSize(descriptor.width, descriptor.height);
    } catch (e) {
      // HEIC and other exotic formats may not be readable here; those are
      // transcoded anyway, and the encoder handles sizing itself.
      debugPrint('MediaCompressor.readSize failed for ${file.path}: $e');
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// Prepare one image for upload.
  ///
  /// Returns the source untouched unless the tier or Cloudflare genuinely
  /// requires otherwise.
  static Future<CompressedImage> compressImage(
    File source, {
    required UploadQuality quality,
  }) async {
    int bytes;
    try {
      bytes = await source.length();
    } catch (e) {
      debugPrint('MediaCompressor: could not stat ${source.path}: $e');
      return CompressedImage(file: source, recompressed: false);
    }

    final size = await readSize(source);
    final compatible = _canPassThrough(source);
    final uploadable = compatible && _withinCloudflareLimits(bytes, size);

    if (uploadable) {
      // The user opted into full fidelity and Cloudflare will take it as-is.
      if (quality == UploadQuality.high) {
        return CompressedImage(file: source, size: size, recompressed: false);
      }

      // Standard tier, but there is nothing here worth reclaiming.
      if (!_isHighQualitySource(bytes, size)) {
        return CompressedImage(file: source, size: size, recompressed: false);
      }
    }

    final ladder = quality == UploadQuality.high ? _highLadder : _standardLadder;
    final maxEdge = _targetMaxEdge(quality, size, uploadable);

    File? best;

    for (var attempt = 0; attempt < ladder.length; attempt++) {
      final out = await _encode(source, size, maxEdge, ladder[attempt], attempt);
      if (out == null) break;

      best = out;
      if (await out.length() <= _cloudflareMaxBytes) break;
    }

    // Still too big at the bottom of the ladder — halve the dimensions rather
    // than let the upload fail outright.
    if (best != null && await best.length() > _cloudflareMaxBytes) {
      final shrunk = await _encode(source, size, maxEdge ~/ 2, 88, 99);
      if (shrunk != null) best = shrunk;
    }

    if (best == null) {
      debugPrint('MediaCompressor: encode failed, falling back to original');
      return CompressedImage(file: source, size: size, recompressed: false);
    }

    // A re-encode that saved nothing is pure loss — common with PNG screenshots
    // and with sources already at their efficient floor.
    if (uploadable && await best.length() >= bytes) {
      return CompressedImage(file: source, size: size, recompressed: false);
    }

    return CompressedImage(
      file: best,
      size: await readSize(best),
      recompressed: true,
    );
  }

  /// Long-edge target for a source that has to be re-encoded.
  ///
  /// [uploadable] means Cloudflare would have accepted the original, so the only
  /// reason we are here is the tier — a transcode-only case (a small HEIC on the
  /// high tier) keeps every pixel.
  static int _targetMaxEdge(
    UploadQuality quality,
    ImageSize? size,
    bool uploadable,
  ) {
    if (quality == UploadQuality.standard) return _standardMaxEdge;
    if (uploadable) return size?.longEdge ?? _highMaxEdge;
    return _highMaxEdge;
  }

  static Future<File?> _encode(
    File source,
    ImageSize? size,
    int maxEdge,
    int quality,
    int attempt,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final target = '${dir.path}/dl_upload_${stamp}_$attempt.jpg';

      // minWidth/minHeight are MINIMUMS, not a bounding box: the package scales
      // by min(srcW/minW, srcH/minH), so passing one value for both caps the
      // SHORT edge. To cap the long edge we compute the exact target and pass
      // it, which makes both ratios equal and gives precisely that size.
      var targetW = maxEdge;
      var targetH = maxEdge;

      if (size != null && size.longEdge > 0) {
        if (size.longEdge <= maxEdge) {
          targetW = size.width;
          targetH = size.height;
        } else {
          final scale = maxEdge / size.longEdge;
          targetW = (size.width * scale).round().clamp(1, 1 << 16);
          targetH = (size.height * scale).round().clamp(1, 1 << 16);
        }
      }

      final result = await FlutterImageCompress.compressAndGetFile(
        source.absolute.path,
        target,
        minWidth: targetW,
        minHeight: targetH,
        quality: quality,
        keepExif: true,
        format: CompressFormat.jpeg,
      );

      return result == null ? null : File(result.path);
    } catch (e) {
      debugPrint('MediaCompressor._encode failed (q$quality): $e');
      return null;
    }
  }

  // ── Video ──────────────────────────────────────────────────────────────────

  /// Whether a picked video is worth re-encoding before upload.
  ///
  /// Same idea as the image path: a clip already at or under 1080p has nothing
  /// to gain from a local pass, on either tier. Only an oversized file — 4K, or
  /// a bitrate high enough to make the upload itself the problem — is touched,
  /// and the tier decides how far down it goes.
  ///
  /// Unknown dimensions fall back to compressing — that is the old behaviour,
  /// and it is the safe side of the trade.
  static bool shouldCompressVideo({
    required UploadQuality quality,
    int? width,
    int? height,
    int? bytes,
  }) {
    final isHigh = quality == UploadQuality.high;
    final maxBytes = isHigh
        ? _videoPassThroughBytesHigh
        : _videoPassThroughBytesStandard;

    if (bytes != null && bytes > maxBytes) return true;

    if (width == null || height == null || width <= 0 || height <= 0) {
      return true;
    }

    // Rotation metadata makes width and height unreliable individually; the
    // long edge is the same either way.
    final longEdge = width > height ? width : height;
    return longEdge > _videoPassThroughEdge;
  }

  /// Video preset for the tier. 1080p for high quality, 720p otherwise.
  ///
  /// Frame rate is deliberately left alone — forcing 60 on a 30fps source gains
  /// nothing and costs bitrate that would be better spent on detail.
  static VideoQuality videoQualityFor(UploadQuality quality) =>
      quality == UploadQuality.high
      ? VideoQuality.Res1920x1080Quality
      : VideoQuality.Res1280x720Quality;
}
