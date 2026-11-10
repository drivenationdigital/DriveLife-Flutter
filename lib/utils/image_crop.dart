import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// How far a pick may be zoomed in.
///
/// Past this the crop is a handful of source pixels blown up, which
/// looks like a mistake rather than a choice.
const double kMaxCropZoom = 5.0;

/// The longest edge a cropped file is written at.
///
/// Not a quality setting — [MediaCompressor] still decides the final
/// size. This only stops a crop of a 48-megapixel photo being rendered
/// at full resolution in memory before compression ever sees it.
const int kCropMaxEdge = 2400;

/// What the viewport is showing, in SOURCE pixels.
///
/// ── THE COORDINATE SYSTEM, BECAUSE IT IS EASY TO GET WRONG ──────────
///
/// InteractiveViewer maps child → viewport as `v = s·c + t`, so the
/// child point under a viewport point is `c = (v − t) / s`. The visible
/// child rect is therefore the viewport's own corners pushed back
/// through that, and the child is laid out at viewport size — so one
/// child unit is `sourceWidth / viewportWidth` source pixels.
///
/// The viewport is built with the SAME aspect ratio as the image (see
/// [cropViewportFor]), which is what makes the output aspect always
/// match the input: zooming crops in, it never reshapes.
ui.Rect visibleSourceRect({
  required ui.Size source,
  required ui.Size viewport,
  required double scale,
  required ui.Offset translation,
}) {
  // A guard rather than an assert: a zero here would come from a
  // layout that has not settled, and returning the whole image is the
  // harmless answer.
  if (scale <= 0 || viewport.width <= 0 || viewport.height <= 0) {
    return ui.Offset.zero & source;
  }

  final perUnit = source.width / viewport.width;

  final left = (-translation.dx / scale) * perUnit;
  final top = (-translation.dy / scale) * perUnit;
  final width = (viewport.width / scale) * perUnit;
  final height = (viewport.height / scale) * perUnit;

  // Clamped into the image. Flinging an InteractiveViewer can overshoot
  // briefly, and a src rect outside the bitmap draws nothing at all —
  // a silently blank photo, which is the worst possible failure here.
  final clampedLeft = left.clamp(0.0, (source.width - width).clamp(0.0, source.width));
  final clampedTop = top.clamp(0.0, (source.height - height).clamp(0.0, source.height));

  return ui.Rect.fromLTWH(
    clampedLeft.toDouble(),
    clampedTop.toDouble(),
    width.clamp(1.0, source.width),
    height.clamp(1.0, source.height),
  );
}

/// The largest box of the image's shape that fits the space available.
///
/// Letterboxed rather than filled, so the untouched state shows the
/// WHOLE photo. Somebody who has not zoomed should see exactly what
/// they picked — this picker exists because people were ending up with
/// images they had not meant to choose, so the default must never hide
/// part of one.
ui.Size cropViewportFor(ui.Size source, ui.Size available) {
  if (source.width <= 0 || source.height <= 0) return available;

  final scale = (available.width / source.width) < (available.height / source.height)
      ? available.width / source.width
      : available.height / source.height;

  return ui.Size(source.width * scale, source.height * scale);
}

/// Maps a rect measured against one size onto another.
///
/// Proportional on each axis independently, so a rect measured against
/// a 4000x3000 that decoded as 3000x4000 — an EXIF rotation the gallery
/// did not report — still lands on the same part of the picture rather
/// than off the edge of it.
///
/// Returns the rect unchanged when the sizes agree, which is the normal
/// case.
ui.Rect rectForDecodedSize({
  required ui.Rect rect,
  required ui.Size? assumedSource,
  required ui.Size actualSource,
}) {
  if (assumedSource == null ||
      assumedSource.width <= 0 ||
      assumedSource.height <= 0 ||
      actualSource.width <= 0 ||
      actualSource.height <= 0) {
    return rect;
  }

  final sameWidth = (assumedSource.width - actualSource.width).abs() < 1;
  final sameHeight = (assumedSource.height - actualSource.height).abs() < 1;

  if (sameWidth && sameHeight) return rect;

  final fx = actualSource.width / assumedSource.width;
  final fy = actualSource.height / assumedSource.height;

  final scaled = ui.Rect.fromLTWH(
    rect.left * fx,
    rect.top * fy,
    rect.width * fx,
    rect.height * fy,
  );

  // Still has to land inside the bitmap: a src rect outside it draws
  // nothing at all, which is a silently blank photo.
  final width = scaled.width.clamp(1.0, actualSource.width);
  final height = scaled.height.clamp(1.0, actualSource.height);

  return ui.Rect.fromLTWH(
    scaled.left.clamp(0.0, actualSource.width - width),
    scaled.top.clamp(0.0, actualSource.height - height),
    width,
    height,
  );
}

/// Whether a transform leaves the image untouched.
///
/// Worth asking, because an untouched pick is PASSED THROUGH as its
/// own file — no decode, no re-encode, no generation lost, EXIF intact.
/// Only somebody who actually zoomed pays for a re-render.
bool isUncropped(double scale, ui.Offset translation) {
  const epsilon = 0.01;

  return (scale - 1.0).abs() < epsilon &&
      translation.dx.abs() < epsilon &&
      translation.dy.abs() < epsilon;
}

/// Renders [srcRect] of [file] to a new JPEG, and returns it.
///
/// Returns null if anything goes wrong, so a caller can fall back to
/// the original file rather than losing the pick.
/// [assumedSource] is the size [srcRect] was measured against.
///
/// ── WHY IT IS NEEDED ────────────────────────────────────────────────
///
/// The rect is worked out at layout time from what the gallery REPORTS
/// about a photo, and the decoder does not always agree. A JPEG with an
/// EXIF rotation reports its raw dimensions while decoding to the
/// rotated ones, so a portrait photo can be measured as landscape —
/// which is how a crop could end up taking the wrong strip of an image,
/// or a preview could look stretched.
///
/// Given the size the rect was measured against, this rescales it onto
/// whatever the decoder actually produced, so a mismatch costs nothing.
/// Pass null to trust the rect as-is.
Future<File?> cropImageFile({
  required File file,
  required ui.Rect srcRect,
  ui.Size? assumedSource,
}) async {
  try {
    final bytes = await file.readAsBytes();
    final decoded = await _decode(bytes);

    if (decoded == null) return null;

    try {
      srcRect = rectForDecodedSize(
        rect: srcRect,
        assumedSource: assumedSource,
        actualSource: ui.Size(
          decoded.width.toDouble(),
          decoded.height.toDouble(),
        ),
      );

      // Capped on the long edge. Beyond this we would be rendering a
      // huge bitmap only for MediaCompressor to shrink it moments
      // later.
      var outWidth = srcRect.width;
      var outHeight = srcRect.height;
      final longest = outWidth > outHeight ? outWidth : outHeight;

      if (longest > kCropMaxEdge) {
        final ratio = kCropMaxEdge / longest;
        outWidth *= ratio;
        outHeight *= ratio;
      }

      final width = outWidth.round().clamp(1, kCropMaxEdge);
      final height = outHeight.round().clamp(1, kCropMaxEdge);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      canvas.drawImageRect(
        decoded,
        srcRect,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );

      final picture = recorder.endRecording();

      ui.Image rendered;
      try {
        rendered = await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }

      Uint8List? png;
      try {
        final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
        png = data?.buffer.asUint8List();
      } finally {
        rendered.dispose();
      }

      if (png == null) return null;

      // PNG out of toByteData is lossless and enormous — a 2400px crop
      // runs to several megabytes. Straight to JPEG before it touches
      // disk, using the compressor the rest of the app already uses.
      final jpeg = await FlutterImageCompress.compressWithList(
        png,
        quality: 92,
        format: CompressFormat.jpeg,
      );

      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/dl_crop_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );

      await out.writeAsBytes(jpeg, flush: true);

      return out;
    } finally {
      decoded.dispose();
    }
  } catch (e) {
    debugPrint('[ImageCrop] failed, keeping original: $e');
    return null;
  }
}

Future<ui.Image?> _decode(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (e) {
    debugPrint('[ImageCrop] decode failed: $e');
    return null;
  }
}
