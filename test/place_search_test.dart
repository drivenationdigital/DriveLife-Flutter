import 'package:drivelife/services/place_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading a geocoder's answer.
///
/// Worth testing because the one thing that matters most — which of the
/// two numbers is the latitude — is written the opposite way round from
/// every other coordinate in this app, and getting it wrong produces a
/// perfectly valid place somewhere off Africa rather than an error.
void main() {
  String body(String features) => '{"type":"FeatureCollection",'
      '"features":[$features]}';

  const helmsley = '{"text":"Helmsley",'
      '"place_name":"Helmsley, North Yorkshire, England",'
      '"center":[-1.0613535,54.2461552]}';

  group('an ordinary answer', () {
    test('the place, with its name and its detail split', () {
      final hits = PlaceSearch.parse(body(helmsley));

      expect(hits.length, 1);
      expect(hits.first.name, 'Helmsley');
      expect(hits.first.label, 'Helmsley, North Yorkshire, England');
      expect(hits.first.detail, 'North Yorkshire, England');
    });

    test('LONGITUDE IS WRITTEN FIRST and is not read first', () {
      // GeoJSON writes [lng, lat]. Read in the order they are written,
      // Helmsley lands off the coast of Somalia.
      final hit = PlaceSearch.parse(body(helmsley)).first;

      expect(hit.point.lat, closeTo(54.2461552, 0.000001));
      expect(hit.point.lng, closeTo(-1.0613535, 0.000001));
    });

    test('several, in the order they came', () {
      final hits = PlaceSearch.parse(
        body('$helmsley,{"text":"Pickering","place_name":"Pickering, England",'
            '"center":[-0.7744189,54.2438582]}'),
      );

      expect(hits.map((h) => h.name).toList(), ['Helmsley', 'Pickering']);
    });

    test('a place with no detail has no second line', () {
      final hits = PlaceSearch.parse(
        body('{"text":"Helmsley","place_name":"Helmsley",'
            '"center":[-1.06,54.24]}'),
      );

      expect(hits.first.detail, isEmpty);
    });
  });

  group('what it refuses', () {
    test('a feature with no coordinates', () {
      expect(
        PlaceSearch.parse(body('{"text":"Nowhere","place_name":"Nowhere"}')),
        isEmpty,
      );
    });

    test('0,0 is not a place somebody meant', () {
      expect(
        PlaceSearch.parse(
          body('{"text":"Null","place_name":"Null","center":[0,0]}'),
        ),
        isEmpty,
      );
    });

    test('a latitude past the pole', () {
      expect(
        PlaceSearch.parse(
          body('{"text":"X","place_name":"X","center":[0,120]}'),
        ),
        isEmpty,
      );
    });

    test('a bad feature does not take the good ones with it', () {
      final hits = PlaceSearch.parse(
        body('{"text":"Broken"},$helmsley'),
      );

      expect(hits.length, 1);
      expect(hits.first.name, 'Helmsley');
    });

    test('an error body, which is what a bad token returns', () {
      expect(PlaceSearch.parse('{"message":"Not Authorized"}'), isEmpty);
    });

    test('something that is not JSON at all', () {
      expect(PlaceSearch.parse('<html>502</html>'), isEmpty);
      expect(PlaceSearch.parse(''), isEmpty);
    });
  });

  // ── WHICH COUNTRY THE SEARCH IS HELD TO ───────────────────────────
  //
  // Proximity only sorts. "Richmond" from Yorkshire still returns
  // Virginia two rows down, looking exactly as legitimate as the one
  // eight miles away — and picking it drops a point on the wrong
  // continent, which the map then flies to.
  group('the country filter', () {
    test('a real code is usable', () {
      expect(PlaceSearch.usableCountry('GB'), isTrue);
      expect(PlaceSearch.usableCountry('us'), isTrue);
      expect(PlaceSearch.usableCountry(' ie '), isTrue);
    });

    test('non-UK is not a country', () {
      // What last_location held before it stored real codes. Mapbox
      // rejects it, which would take the whole search down rather
      // than just the filter.
      expect(PlaceSearch.usableCountry('non-UK'), isFalse);
    });

    test('nothing at all is not a country', () {
      expect(PlaceSearch.usableCountry(null), isFalse);
      expect(PlaceSearch.usableCountry(''), isFalse);
      expect(PlaceSearch.usableCountry('   '), isFalse);
    });

    test('anything that is not two letters is refused', () {
      expect(PlaceSearch.usableCountry('GBR'), isFalse);
      expect(PlaceSearch.usableCountry('G'), isFalse);
      expect(PlaceSearch.usableCountry('44'), isFalse);
      expect(PlaceSearch.usableCountry('g1'), isFalse);
    });
  });

  group('coordinates typed as text', () {
    test('strings still parse, because APIs do that', () {
      final hits = PlaceSearch.parse(
        body('{"text":"Helmsley","place_name":"Helmsley",'
            '"center":["-1.06","54.24"]}'),
      );

      expect(hits.first.point.lat, closeTo(54.24, 0.001));
      expect(hits.first.point.lng, closeTo(-1.06, 0.001));
    });
  });
}
