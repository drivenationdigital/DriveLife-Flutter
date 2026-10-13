import 'package:drivelife/screens/discover/discover_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for where the selected pin's card goes.
///
/// It used to be parked at a fixed height above the results sheet, which put
/// it a long way from the pin it was describing — on a tall phone, most of the
/// screen away. It is now placed against the pin, and this is the arithmetic
/// that does it.
void main() {
  const screen = Size(390, 844);

  // Status bar, search bar and category chips.
  const chrome = 157.0;

  CalloutPlacement? place(Offset pin) =>
      DiscoverCallout.placeFor(pin: pin, screen: screen, chrome: chrome);

  group('side', () {
    test('sits above a pin with room above it', () {
      final at = place(const Offset(195, 600))!;

      expect(at.pointsDown, isTrue);
      // Its bottom edge clears the top of the pin art, which rises from the
      // coordinate rather than hanging below it.
      final bottom = at.top + DiscoverCallout.height + DiscoverCallout.tail;
      expect(bottom, lessThanOrEqualTo(600 - DiscoverCallout.pinHeight));
    });

    test('drops below a pin tucked under the chrome', () {
      // Near the top of the screen there is no room between the pin and the
      // search bar, so the card has to go the other way.
      final at = place(const Offset(195, 200))!;

      expect(at.pointsDown, isFalse);
      expect(at.top, greaterThan(200));
    });

    test('never slides under the chrome', () {
      for (var y = 160.0; y < 844; y += 10) {
        final at = place(Offset(195, y))!;
        if (at.pointsDown) {
          expect(
            at.top,
            greaterThanOrEqualTo(chrome),
            reason: 'a card at y=$y was placed behind the search bar',
          );
        }
      }
    });
  });

  group('horizontal', () {
    test('centres on the pin when there is room', () {
      final at = place(const Offset(195, 600))!;
      expect(at.left, 195 - DiscoverCallout.width / 2);
    });

    test('stays on screen at the left edge', () {
      final at = place(const Offset(4, 600))!;
      expect(at.left, DiscoverCallout.margin);
    });

    test('stays on screen at the right edge', () {
      final at = place(const Offset(386, 600))!;
      expect(
        at.left + DiscoverCallout.width,
        lessThanOrEqualTo(screen.width - DiscoverCallout.margin),
      );
    });

    test('survives a screen narrower than the card', () {
      // The clamp bounds would cross over, and clamp throws when they do.
      final at = DiscoverCallout.placeFor(
        pin: const Offset(100, 400),
        screen: const Size(240, 500),
        chrome: chrome,
      );

      expect(at, isNotNull);
      expect(at!.left, DiscoverCallout.margin);
    });
  });

  group('off screen', () {
    test('is not placed at all', () {
      // Panning the map takes the pin away. A card clamped to the edge would
      // point at nothing.
      expect(place(const Offset(-80, 600)), isNull);
      expect(place(const Offset(470, 600)), isNull);
      expect(place(const Offset(195, -80)), isNull);
      expect(place(const Offset(195, 920)), isNull);
    });

    test('is still placed just inside the edge', () {
      expect(place(const Offset(2, 600)), isNotNull);
      expect(place(const Offset(388, 600)), isNotNull);
    });
  });
}
