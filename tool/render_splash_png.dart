// Renders the native pre-splash bitmap from assets/intro-logo.svg.
//
// WHY A TEST FILE
//
// flutter_native_splash takes a PNG, not an SVG — the native splash is
// drawn by Android and iOS before a single line of Dart runs, so nothing
// that can read an SVG exists yet. The bitmap therefore has to be baked
// ahead of time, and this bakes it with the same renderer the app itself
// uses, so the native splash and the Dart one that replaces it are the
// same artwork rather than two drawings of it.
//
// It lives in tool/ and not test/ so `flutter test test/` does not
// rewrite committed assets on every run.
//
// Run it when assets/intro-logo.svg changes:
//
//   flutter test tool/render_splash_png.dart
//   dart run flutter_native_splash:create
//
// The second line is what actually installs the result into android/ and
// ios/. Rendering alone changes nothing a user would see.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1152x1152 is what flutter_native_splash wants for the Android 12+
/// splash, where only the inner 768x768 survives the circular mask. The
/// logo is sized to sit well inside that, which is why one bitmap can
/// serve both the modern splash and the legacy one.
const double _canvas = 1152;
const double _logoWidth = 620;

void main() {
  testWidgets('bake assets/splash-intro.png', (tester) async {
    await tester.binding.setSurfaceSize(const Size(_canvas, _canvas));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: _canvas,
            height: _canvas,
            // Transparent, not #151515. flutter_native_splash paints the
            // background itself from `color:`, and a bitmap carrying its
            // own background would show as a visible square against it
            // the moment the two drifted apart by a single digit.
            child: Center(
              child: SvgPicture.asset(
                'assets/intro-logo.svg',
                width: _logoWidth,
              ),
            ),
          ),
        ),
      ),
    );

    // flutter_svg loads and parses off the frame, so the first pump draws
    // nothing. Pumping a few frames gives it somewhere to land.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final boundary =
        boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;

    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    expect(bytes, isNotNull, reason: 'the boundary encoded to nothing');

    final out = File('assets/splash-intro.png');
    out.writeAsBytesSync(bytes!.buffer.asUint8List());

    // A blank canvas encodes perfectly happily, so check something was
    // actually drawn rather than trusting that it was.
    expect(
      out.lengthSync(),
      greaterThan(2000),
      reason: 'the PNG is too small to contain a logo — did the SVG load?',
    );

    // ignore: avoid_print
    print('wrote ${out.path} (${out.lengthSync()} bytes)');
  });
}
