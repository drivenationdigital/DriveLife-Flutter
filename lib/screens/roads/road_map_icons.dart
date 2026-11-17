import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// The arrowheads that say which way a road runs.
///
/// ── WHY AN IMAGE AND NOT A CHARACTER ────────────────────────────────
///
/// A text glyph would have been one line — `textField: '▶'` — and it
/// would have depended on that character existing in whichever font
/// the style happens to resolve. When it does not, Mapbox draws
/// nothing and says nothing, and the failure looks exactly like the
/// layer not being added.
///
/// A raster cannot be missing. Drawn once, handed to the style, and
/// the layer places one every sixty pixels along the line.
///
/// ── AND WHY IT POINTS RIGHT ─────────────────────────────────────────
///
/// With `symbolPlacement: line` Mapbox rotates each icon to the
/// direction of travel along the geometry, where zero degrees means
/// "along the line". So the artwork points at positive x and the map
/// turns it — which is why the arrows follow every bend without
/// anything here knowing where the bends are.
abstract final class RoadMapIcons {
  const RoadMapIcons._();

  /// The id the symbol layer asks for.
  static const String arrowId = 'dl-road-arrow';

  /// Logical size, before the device pixel ratio.
  static const double _size = 15;

  /// Paints the arrow and adds it to the loaded style.
  ///
  /// Idempotent: re-registering an existing id replaces it, which is
  /// what should happen when a style reload takes its image table with
  /// it. Has to be called on every style load for that reason — an
  /// image registered against the previous style is gone, and a layer
  /// asking for an image that is not there draws nothing at all.
  static Future<void> register(MapboxMap map, double pixelRatio) async {
    final image = await _draw(pixelRatio);

    await map.addImage(
      arrowId,
      pixelRatio,
      await StyleImage.fromImage(image),
      // Not an SDF. These are two flat colours chosen to read against
      // both the gold line and the dark casing under it; an SDF would
      // be recoloured by the layer and lose the outline that does
      // half that work.
      sdf: false,
    );

    image.dispose();
  }

  /// A white chevron with a dark edge, pointing right.
  static Future<ui.Image> _draw(double pixelRatio) async {
    final size = _size * pixelRatio;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // A chevron rather than a solid triangle: it reads as a direction
    // at a glance, and it leaves the line visible through it rather
    // than cutting the road into dashes.
    final arrow = Path()
      ..moveTo(size * 0.30, size * 0.16)
      ..lineTo(size * 0.78, size * 0.50)
      ..lineTo(size * 0.30, size * 0.84)
      ..lineTo(size * 0.45, size * 0.50)
      ..close();

    // The dark edge first, as a wider stroke under the fill. It is
    // what keeps the arrow visible where it crosses the pale part of
    // the line and where it falls on the casing.
    canvas.drawPath(
      arrow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * pixelRatio
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF0B0B0B),
    );

    canvas.drawPath(arrow, Paint()..color = Colors.white);

    return recorder.endRecording().toImage(size.ceil(), size.ceil());
  }
}
