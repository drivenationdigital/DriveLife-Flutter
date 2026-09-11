import 'package:drivelife/utils/country.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('countryFromAddress', () {
    test('reads the tail of what Google actually returns', () {
      // The forms Google emits, which are not the formal names.
      expect(countryFromAddress('Silverstone Circuit, Towcester, UK'), 'GB');
      expect(countryFromAddress('Circuit of the Americas, Austin, TX, USA'), 'US');
      expect(countryFromAddress('Exhibition Place, Toronto, ON, Canada'), 'CA');
    });

    test('takes the last part only', () {
      // "Canada Water" is in London. Matching a country anywhere in the
      // string would file this under CA.
      expect(countryFromAddress('Canada Water, London, UK'), 'GB');
    });

    test('is null rather than wrong when it does not recognise the tail', () {
      expect(countryFromAddress('Somewhere, Freedonia'), isNull);
      expect(countryFromAddress(''), isNull);
    });
  });

  group('countryFlag', () {
    test('builds a flag from any valid code', () {
      expect(countryFlag('GB'), '\u{1F1EC}\u{1F1E7}');
      expect(countryFlag('CA'), '\u{1F1E8}\u{1F1E6}');
    });

    test('is empty for anything that is not a code', () {
      expect(countryFlag(''), '');
      expect(countryFlag('G'), '');
      expect(countryFlag('G1'), '');
      expect(countryFlag('GBR'), '');
    });
  });

  group('countryLabel', () {
    test('names the countries the filter offers', () {
      expect(countryLabel('GB'), contains('United Kingdom'));
      expect(countryLabel('US'), contains('United States'));
      expect(countryLabel('CA'), contains('Canada'));
    });

    test('falls back to the code rather than showing nothing', () {
      // Two letters is all a flag needs, so an unassigned pair still gets a
      // sequence — which platforms render as the letters. The point is that
      // the code survives rather than the label coming back empty.
      expect(countryLabel('ZZ'), contains('ZZ'));
      expect(countryLabel(''), '');
    });
  });
}
