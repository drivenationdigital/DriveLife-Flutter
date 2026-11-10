import 'dart:ui';

import 'package:drivelife/utils/image_crop.dart';
import 'package:flutter_test/flutter_test.dart';

/// The crop maths, which cannot be checked by looking at the app.
///
/// A wrong transform here does not crash or look broken — it silently
/// saves the wrong part of somebody's photo, which is the exact failure
/// the picker was built to stop.
void main() {
  group('visibleSourceRect', () {
    const source = Size(4000, 3000);
    const viewport = Size(400, 300); // same aspect, as the picker builds it

    test('untouched shows the whole image', () {
      final rect = visibleSourceRect(
        source: source,
        viewport: viewport,
        scale: 1,
        translation: Offset.zero,
      );

      expect(rect.left, 0);
      expect(rect.top, 0);
      expect(rect.width, 4000);
      expect(rect.height, 3000);
    });

    test('zoomed 2x from the origin takes the top-left quarter', () {
      final rect = visibleSourceRect(
        source: source,
        viewport: viewport,
        scale: 2,
        translation: Offset.zero,
      );

      expect(rect.left, 0);
      expect(rect.top, 0);
      expect(rect.width, 2000);
      expect(rect.height, 1500);
    });

    test('zoomed 2x and centred takes the middle', () {
      // InteractiveViewer maps child -> viewport as v = s*c + t, so
      // centring a 2x zoom means pulling back by half a viewport.
      final rect = visibleSourceRect(
        source: source,
        viewport: viewport,
        scale: 2,
        translation: const Offset(-200, -150),
      );

      expect(rect.left, 1000);
      expect(rect.top, 750);
      expect(rect.width, 2000);
      expect(rect.height, 1500);
      expect(rect.center.dx, 2000);
      expect(rect.center.dy, 1500);
    });

    test('output keeps the source aspect at every zoom', () {
      for (final scale in [1.0, 1.5, 2.0, 3.7, 5.0]) {
        final rect = visibleSourceRect(
          source: source,
          viewport: viewport,
          scale: scale,
          translation: Offset.zero,
        );

        expect(
          rect.width / rect.height,
          closeTo(source.width / source.height, 0.0001),
          reason: 'zooming must crop in, never reshape (scale $scale)',
        );
      }
    });

    test('overshoot is clamped inside the bitmap', () {
      // A fling can push past the edge for a frame. An src rect outside
      // the image draws NOTHING — a silently blank photo.
      final rect = visibleSourceRect(
        source: source,
        viewport: viewport,
        scale: 2,
        translation: const Offset(900, 900),
      );

      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(source.width));
      expect(rect.bottom, lessThanOrEqualTo(source.height));
    });

    test('far overshoot the other way is also clamped', () {
      final rect = visibleSourceRect(
        source: source,
        viewport: viewport,
        scale: 2,
        translation: const Offset(-5000, -5000),
      );

      expect(rect.right, lessThanOrEqualTo(source.width));
      expect(rect.bottom, lessThanOrEqualTo(source.height));
      expect(rect.width, 2000);
      expect(rect.height, 1500);
    });

    test('a degenerate scale returns the whole image rather than nothing', () {
      final rect = visibleSourceRect(
        source: source,
        viewport: viewport,
        scale: 0,
        translation: Offset.zero,
      );

      expect(rect, Offset.zero & source);
    });
  });

  group('cropViewportFor', () {
    test('landscape into a square space is limited by width', () {
      final size = cropViewportFor(const Size(4000, 2000), const Size(400, 400));

      expect(size.width, 400);
      expect(size.height, 200);
    });

    test('portrait into a wide space is limited by height', () {
      final size = cropViewportFor(const Size(2000, 4000), const Size(400, 300));

      expect(size.width, 150);
      expect(size.height, 300);
    });

    test('the viewport always matches the source aspect', () {
      // This is what guarantees output aspect == input aspect.
      for (final source in const [
        Size(4000, 3000),
        Size(3000, 4000),
        Size(1000, 1000),
        Size(5000, 1000),
      ]) {
        final size = cropViewportFor(source, const Size(400, 360));

        expect(
          size.width / size.height,
          closeTo(source.width / source.height, 0.0001),
        );
        expect(size.width, lessThanOrEqualTo(400.001));
        expect(size.height, lessThanOrEqualTo(360.001));
      }
    });

    test('a zero-sized source falls back to the space available', () {
      expect(
        cropViewportFor(const Size(0, 0), const Size(400, 300)),
        const Size(400, 300),
      );
    });
  });

  group('isUncropped', () {
    test('identity is untouched, so the original passes through', () {
      expect(isUncropped(1.0, Offset.zero), isTrue);
    });

    test('a hair of drift still counts as untouched', () {
      // Pinching and releasing can leave a rounding residue. Treating
      // that as an edit would re-encode a photo nobody changed.
      expect(isUncropped(1.0001, const Offset(0.001, -0.002)), isTrue);
    });

    test('a real zoom is an edit', () {
      expect(isUncropped(1.4, Offset.zero), isFalse);
    });

    test('a pan without zoom is an edit', () {
      expect(isUncropped(1.0, const Offset(-30, 0)), isFalse);
    });
  });

  _rescaleTests();
}

/// Added for the EXIF-rotation bug: the gallery reported a portrait
/// photo's raw (landscape) dimensions, so the crop was measured against
/// the wrong shape and the preview stretched.
void _rescaleTests() {
  group('rectForDecodedSize', () {
    test('agreeing sizes leave the rect alone', () {
      const rect = Rect.fromLTWH(100, 50, 400, 300);

      expect(
        rectForDecodedSize(
          rect: rect,
          assumedSource: const Size(4000, 3000),
          actualSource: const Size(4000, 3000),
        ),
        rect,
      );
    });

    test('a null assumption trusts the rect', () {
      const rect = Rect.fromLTWH(10, 20, 30, 40);

      expect(
        rectForDecodedSize(
          rect: rect,
          assumedSource: null,
          actualSource: const Size(100, 100),
        ),
        rect,
      );
    });

    test('a rotated decode maps onto the same part of the picture', () {
      // Measured against 4000x3000; decoder produced 3000x4000.
      final mapped = rectForDecodedSize(
        rect: const Rect.fromLTWH(2000, 1500, 2000, 1500),
        assumedSource: const Size(4000, 3000),
        actualSource: const Size(3000, 4000),
      );

      // Bottom-right quadrant, still the bottom-right quadrant.
      expect(mapped.left, closeTo(1500, 0.01));
      expect(mapped.top, closeTo(2000, 0.01));
      expect(mapped.width, closeTo(1500, 0.01));
      expect(mapped.height, closeTo(2000, 0.01));
    });

    test('a rescaled rect still lands inside the bitmap', () {
      final mapped = rectForDecodedSize(
        rect: const Rect.fromLTWH(3900, 2900, 200, 200),
        assumedSource: const Size(4000, 3000),
        actualSource: const Size(1000, 750),
      );

      expect(mapped.left, greaterThanOrEqualTo(0));
      expect(mapped.top, greaterThanOrEqualTo(0));
      expect(mapped.right, lessThanOrEqualTo(1000.001));
      expect(mapped.bottom, lessThanOrEqualTo(750.001));
    });

    test('a degenerate actual size is refused rather than dividing by zero', () {
      const rect = Rect.fromLTWH(0, 0, 10, 10);

      expect(
        rectForDecodedSize(
          rect: rect,
          assumedSource: const Size(100, 100),
          actualSource: const Size(0, 0),
        ),
        rect,
      );
    });
  });
}
