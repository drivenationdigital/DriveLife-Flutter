import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'discover_place.dart';

/// Draws the map pins and registers them with the style.
///
/// Mapbox needs a real raster for `icon-image`; it cannot draw a Flutter
/// widget. So each category's pin is painted once onto a canvas, handed to the
/// style under [DiscoverKind.iconId], and from then on the SymbolLayer picks
/// one per feature with a `['get', 'icon']` expression. Two images, drawn
/// once, however many thousand pins are on screen.
abstract final class DiscoverPins {
  const DiscoverPins._();

  /// Logical size of a pin, before the device pixel ratio.
  static const double _width = 34;
  static const double _height = 44;

  /// Paints every category's pin and adds it to the loaded style.
  ///
  /// Idempotent: re-registering an existing id replaces it, which is what
  /// should happen when the style reloads and takes its image table with it.
  static Future<void> register(MapboxMap map, double pixelRatio) async {
    for (final kind in DiscoverKind.values) {
      final image = await _draw(kind, pixelRatio);
      await map.addImage(
        kind.iconId,
        pixelRatio,
        await StyleImage.fromImage(image),
        // Not an SDF: these are full-colour pins and the colour is the
        // legend. An SDF would be recoloured by the layer and every pin
        // would come out the same.
        sdf: false,
      );
      image.dispose();
    }
  }

  /// A teardrop in the category's colour with its glyph knocked out in white.
  static Future<ui.Image> _draw(DiscoverKind kind, double pixelRatio) async {
    final w = _width * pixelRatio;
    final h = _height * pixelRatio;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final radius = w / 2;
    final centre = Offset(radius, radius);

    // The body: a circle, plus a triangle tapering to the point that sits on
    // the coordinate. Drawn as one path so the shadow follows the outline
    // instead of showing the seam between the two shapes.
    final body = Path()
      ..addOval(Rect.fromCircle(center: centre, radius: radius))
      ..moveTo(radius - radius * 0.42, radius + radius * 0.78)
      ..lineTo(radius, h)
      ..lineTo(radius + radius * 0.42, radius + radius * 0.78)
      ..close();

    canvas.drawShadow(body, Colors.black.withValues(alpha: 0.4), 3 * pixelRatio, false);
    canvas.drawPath(body, Paint()..color = kind.colour);

    // A white rim, so a dark pin still reads against dark map features and
    // two overlapping pins remain two pins.
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * pixelRatio
        ..color = Colors.white,
    );

    final icon = kind.icon;
    final glyph = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: radius * 1.05,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      ),
    )..layout();

    glyph.paint(canvas, centre - Offset(glyph.width / 2, glyph.height / 2));

    return recorder.endRecording().toImage(w.ceil(), h.ceil());
  }
}
