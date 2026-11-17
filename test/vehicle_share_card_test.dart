import 'package:drivelife/widgets/garage/vehicle_share_card.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a vehicle looks like once it is a picture somebody forwards.
///
/// Worth testing without a screen because a share card is the one
/// surface here that leaves the app. A mistake on the vehicle page is
/// seen by its owner; a mistake on the card is seen by whoever they
/// sent it to, and it cannot be taken back.
void main() {
  group('the name', () {
    test('make, model and variant read as one car', () {
      expect(
        VehicleCardFacts.name(const {
          'make': 'Ford',
          'model': 'Mustang',
          'variant': 'Dark Horse',
        }),
        'Ford Mustang Dark Horse',
      );
    });

    test('a missing variant leaves no double space', () {
      expect(
        VehicleCardFacts.name(const {'make': 'Ford', 'model': 'Mustang'}),
        'Ford Mustang',
      );
    });

    test('nothing at all is empty, and the card says "Vehicle"', () {
      expect(VehicleCardFacts.name(const {}), '');
    });
  });

  group('the line under it', () {
    test('year and colour', () {
      expect(
        VehicleCardFacts.subtitle(const {'year': '2026', 'colour': 'Grey'}),
        '2026 · Grey',
      );
    });

    test('one of the two carries no separator', () {
      expect(VehicleCardFacts.subtitle(const {'year': '2026'}), '2026');
      expect(VehicleCardFacts.subtitle(const {'colour': 'Grey'}), 'Grey');
    });

    test('neither is empty rather than a stray dot', () {
      expect(VehicleCardFacts.subtitle(const {}), '');
    });

    test('the registration is never on the card', () {
      // It is on the car in the photograph for anybody who looks, which
      // is a different thing from setting it in type beside the
      // owner's name on something built to be forwarded on.
      final line = VehicleCardFacts.subtitle(const {
        'year': '2026',
        'colour': 'Grey',
        'registration': 'EF26RTO',
      });

      expect(line.contains('EF26RTO'), isFalse);
    });
  });

  group('the figures', () {
    test('all three, in the order the page uses', () {
      final stats = VehicleCardFacts.stats(const {
        'vehicle_bhp': 453,
        'vehicle_062': 4.1,
        'vehicle_top_speed': 166,
      });

      expect(stats.map((s) => s.label).toList(), [
        'POWER',
        '0-62',
        'TOP SPEED',
      ]);
      expect(stats.map((s) => s.value).toList(), ['453', '4.1', '166']);
      expect(stats.map((s) => s.unit).toList(), ['bhp', 'sec', 'mph']);
    });

    test('a car with only power gets only power', () {
      final stats = VehicleCardFacts.stats(const {'vehicle_bhp': 453});

      expect(stats.length, 1);
      expect(stats.first.label, 'POWER');
    });

    test('a car with no figures gets no strip at all', () {
      // Not three dashes. An empty strip reads as the card being
      // broken; no strip reads as a car whose owner did not fill the
      // numbers in, which is what happened.
      expect(VehicleCardFacts.stats(const {}), isEmpty);
    });

    test('zero is not a figure', () {
      // The form stores an unanswered field as 0, so "0 bhp" is what
      // "I never filled that in" looks like coming back out.
      expect(
        VehicleCardFacts.stats(const {
          'vehicle_bhp': 0,
          'vehicle_062': 0,
          'vehicle_top_speed': 0,
        }),
        isEmpty,
      );
    });

    test('numbers that arrive as strings still count', () {
      final stats = VehicleCardFacts.stats(const {
        'vehicle_bhp': '453',
        'vehicle_top_speed': '166.0',
      });

      expect(stats.map((s) => s.value).toList(), ['453', '166']);
    });

    test('a whole number loses its .0, a decimal keeps its place', () {
      expect(VehicleCardFacts.number(166.0), '166');
      expect(VehicleCardFacts.number(4.1), '4.1');
    });

    test('rubbish is nothing rather than a wrong number', () {
      expect(VehicleCardFacts.number('fast'), '');
      expect(VehicleCardFacts.number(null), '');
      expect(VehicleCardFacts.number(''), '');
    });
  });

  group('the photograph', () {
    test('the cover, when there is one', () {
      expect(
        VehicleCardFacts.photo(const {'cover_photo': 'https://x/cover.jpg'}),
        'https://x/cover.jpg',
      );
    });

    test('the first gallery row when the cover column is empty', () {
      expect(
        VehicleCardFacts.photo(const {
          'cover_photo': '',
          'photos': [
            {'url': 'https://x/one.jpg'},
            {'url': 'https://x/two.jpg'},
          ],
        }),
        'https://x/one.jpg',
      );
    });

    test('a gallery of plain strings', () {
      expect(
        VehicleCardFacts.photo(const {
          'photos': ['https://x/one.jpg'],
        }),
        'https://x/one.jpg',
      );
    });

    test('a blank row is skipped rather than returned', () {
      expect(
        VehicleCardFacts.photo(const {
          'photos': [
            {'url': '  '},
            {'url': 'https://x/two.jpg'},
          ],
        }),
        'https://x/two.jpg',
      );
    });

    test('no photograph anywhere', () {
      // Not a crash and not a broken image: the card draws its
      // fallback panel instead.
      expect(VehicleCardFacts.photo(const {}), '');
      expect(VehicleCardFacts.photo(const {'photos': []}), '');
    });
  });
}
