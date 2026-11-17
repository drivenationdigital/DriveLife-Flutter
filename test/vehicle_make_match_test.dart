import 'package:drivelife/models/vehicle_guess.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matching what the scan said to an entry of the make dropdown.
///
/// ── WHY A LITERAL COMPARISON WAS NOT ENOUGH ─────────────────────────
///
/// The list spells these names the way a British road registry does.
/// The model answers with the way people say them. Compared literally,
/// lowercased, it missed most of the common ones — which showed up as
/// "the manufacturer dropdown isn't auto selecting correctly".
void main() {
  // The real list, abridged to the entries that matter here — and
  // deliberately including the pairs that trap a careless alias table:
  // Opel beside Vauxhall, Rover beside Land Rover, Mercury beside
  // Mercedes-Benz, Corvette beside Chevrolet.
  const makes = <String>[
    'Abarth', 'AC', 'Alfa Romeo', 'Alpine', 'Aston Martin', 'Audi',
    'BMW', 'Bentley', 'Chevrolet', 'Chrysler', 'Citroen', 'Corvette',
    'CUPRA', 'DS AUTOMOBILES', 'Ferrari', 'Fiat', 'Ford', 'Honda',
    'Jaguar', 'Land Rover', 'Lexus', 'Mercedes-Benz', 'Mercury', 'MG',
    'MINI', 'Nissan', 'Opel', 'Peugeot', 'Porsche', 'Renault',
    'Rolls-Royce', 'Rover', 'SEAT', 'Skoda', 'SsangYong', 'Subaru',
    'Tesla', 'Toyota', 'Vauxhall', 'Volkswagen', 'Volvo',
    'Other / Not Listed',
  ];

  String? match(String guess) => VehicleGuess.matchMake(guess, makes);

  group('the names that were failing', () {
    test('Mercedes finds Mercedes-Benz', () {
      expect(match('Mercedes'), 'Mercedes-Benz');
    });

    test('so does Mercedes Benz, without the hyphen', () {
      expect(match('Mercedes Benz'), 'Mercedes-Benz');
    });

    test('Citroën finds Citroen', () {
      expect(match('Citroën'), 'Citroen');
    });

    test('Alfa finds Alfa Romeo', () {
      expect(match('Alfa'), 'Alfa Romeo');
    });

    test('VW finds Volkswagen', () {
      expect(match('VW'), 'Volkswagen');
    });

    test('Range Rover finds Land Rover, which is the marque', () {
      expect(match('Range Rover'), 'Land Rover');
    });

    test('DS finds DS AUTOMOBILES', () {
      expect(match('DS'), 'DS AUTOMOBILES');
    });
  });

  group('the list wins before any alias', () {
    test('Opel is Opel, not Vauxhall', () {
      // Both are in the list. Translating before checking would answer
      // with a different marque than the photographs showed.
      expect(match('Opel'), 'Opel');
    });

    test('Rover is Rover, not Land Rover', () {
      expect(match('Rover'), 'Rover');
    });

    test('Vauxhall is still Vauxhall', () {
      expect(match('Vauxhall'), 'Vauxhall');
    });
  });

  group('the ordinary cases still work', () {
    test('an exact name', () {
      expect(match('Porsche'), 'Porsche');
    });

    test('case does not matter', () {
      expect(match('porsche'), 'Porsche');
      expect(match('BMW'), 'BMW');
      expect(match('bmw'), 'BMW');
    });

    test('a list entry in caps', () {
      expect(match('Cupra'), 'CUPRA');
      expect(match('Seat'), 'SEAT');
      expect(match('Mini'), 'MINI');
    });

    test('a hyphen in the list', () {
      expect(match('Rolls Royce'), 'Rolls-Royce');
      expect(match('rolls-royce'), 'Rolls-Royce');
    });

    test('odd capitalisation in the list', () {
      expect(match('Ssangyong'), 'SsangYong');
    });

    test('stray whitespace', () {
      expect(match('  Audi  '), 'Audi');
    });
  });

  group('a make run together with a model', () {
    test('the make is taken', () {
      expect(match('Volkswagen Golf'), 'Volkswagen');
    });

    test('even hyphenated', () {
      expect(match('Mercedes-Benz C63'), 'Mercedes-Benz');
    });
  });

  group('rather null than wrong', () {
    test('an ambiguous prefix picks nothing', () {
      // "Mer" starts both Mercedes-Benz and Mercury. Neither is a safe
      // answer, and the banner still names what the scan said.
      expect(match('Mer'), isNull);
    });

    test('a single letter picks nothing', () {
      expect(match('A'), isNull);
      expect(match('C'), isNull);
    });

    test('a make the list does not carry', () {
      expect(match('Koenigsegg'), isNull);
      expect(match('Rivian'), isNull);
    });

    test('empty, or punctuation only', () {
      expect(match(''), isNull);
      expect(match('   '), isNull);
      expect(match('-'), isNull);
    });

    test('a model with no make is not forced into one', () {
      expect(match('911'), isNull);
    });
  });
}
