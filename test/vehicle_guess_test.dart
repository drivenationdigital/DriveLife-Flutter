import 'package:drivelife/models/vehicle_guess.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the photographs say a vehicle is.
///
/// The add-vehicle flow fills a form in from this, so every reading
/// here lands in a field somebody may not check. A wrong variant is
/// worse than no variant: an empty field reads as a question and a
/// wrong one reads as an answer.
void main() {
  group('is there anything to show', () {
    test('a make alone is a guess', () {
      expect(const VehicleGuess(make: 'Porsche').hasGuess, isTrue);
    });

    test('a model alone is a guess', () {
      expect(const VehicleGuess(model: '911').hasGuess, isTrue);
    });

    test('a colour alone is not', () {
      // "We think this is a Silver" is not an identification, and
      // offering it as one spends the credibility the real ones need.
      expect(const VehicleGuess(colour: 'Silver').hasGuess, isFalse);
      expect(const VehicleGuess(body: 'Coupe').hasGuess, isFalse);
    });

    test('nothing is nothing', () {
      expect(VehicleGuess.none.hasGuess, isFalse);
    });
  });

  group('the banner line', () {
    test('make, model and variant read as one name', () {
      const guess = VehicleGuess(
        make: 'Porsche',
        model: '911',
        variant: 'GT3 Touring',
      );

      expect(guess.label, 'Porsche 911 GT3 Touring');
    });

    test('a missing variant leaves no double space', () {
      const guess = VehicleGuess(make: 'Porsche', model: '911');

      expect(guess.label, 'Porsche 911');
    });

    test('a model with no make still reads', () {
      expect(const VehicleGuess(model: 'Golf').label, 'Golf');
    });
  });

  group('reading the payload', () {
    test('the ordinary case', () {
      final guess = VehicleGuess.fromMap(const {
        'make': 'Porsche',
        'model': '911',
        'variant': 'GT3 Touring',
        'year': '2022',
        'colour': 'Silver',
        'body': 'Coupe',
        'confidence': 'High',
        'images_used': 3,
      });

      expect(guess.label, 'Porsche 911 GT3 Touring');
      expect(guess.yearForField, '2022');
      expect(guess.imagesUsed, 3);
      expect(guess.isConfident, isTrue);
    });

    test('nulls arrive as empty, not as the word null', () {
      final guess = VehicleGuess.fromMap(const {
        'make': 'Porsche',
        'model': '911',
        'variant': null,
        'year': null,
      });

      expect(guess.variant, '');
      expect(guess.label, 'Porsche 911');
    });

    test('whitespace is trimmed', () {
      final guess = VehicleGuess.fromMap(const {
        'make': '  Porsche ',
        'model': ' 911',
      });

      expect(guess.label, 'Porsche 911');
    });

    test('a missing payload is not a crash', () {
      final guess = VehicleGuess.fromMap(const {});

      expect(guess.hasGuess, isFalse);
      expect(guess.label, '');
      expect(guess.yearForField, '');
    });

    test('low confidence is still a guess, just a quiet one', () {
      final guess = VehicleGuess.fromMap(const {
        'make': 'Ford',
        'confidence': 'Low',
      });

      expect(guess.hasGuess, isTrue);
      expect(guess.isConfident, isFalse);
    });
  });

  group('the year, for a field expecting four digits', () {
    test('a plain year passes through', () {
      expect(const VehicleGuess(year: '2022').yearForField, '2022');
    });

    test('a range becomes its first year', () {
      // "2015-2023" is a real answer to "when was this made" and a
      // useless one to put in a box expecting one year. The first year
      // is the honest reading, and it is correctable.
      expect(const VehicleGuess(year: '2015-2023').yearForField, '2015');
    });

    test('nineteen-hundreds are years too', () {
      expect(const VehicleGuess(year: '1989').yearForField, '1989');
    });

    test('prose with a year in it still yields the year', () {
      expect(
        const VehicleGuess(year: 'around 2018 or so').yearForField,
        '2018',
      );
    });

    test('no year at all is empty rather than a wrong one', () {
      expect(const VehicleGuess(year: '').yearForField, '');
      expect(const VehicleGuess(year: 'unknown').yearForField, '');
      // Not a year, and not to be read as one.
      expect(const VehicleGuess(year: '3000').yearForField, '');
      expect(const VehicleGuess(year: '89').yearForField, '');
    });
  });
}
