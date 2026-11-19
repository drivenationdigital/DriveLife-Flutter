import 'package:drivelife/models/google_maps_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading a route out of a Google Maps link.
///
/// Worth testing hard because the input is somebody's clipboard: it
/// arrives in three different shapes, carries place names next to
/// coordinates, and includes one coordinate that looks exactly like a
/// stop and is not one.
void main() {
  List<List<double>> pairs(String url) => GoogleMapsLink.pointsFrom(
    url,
  ).map((p) => [p.lat, p.lng]).toList();

  group('the documented share link', () {
    test('origin, waypoints and destination, in that order', () {
      expect(
        pairs(
          'https://www.google.com/maps/dir/?api=1'
          '&origin=53.2585,-2.0074'
          '&waypoints=53.2500,-1.9800|53.2400,-1.9600'
          '&destination=53.2300,-1.9100',
        ),
        [
          [53.2585, -2.0074],
          [53.25, -1.98],
          [53.24, -1.96],
          [53.23, -1.91],
        ],
      );
    });

    test('just the two ends', () {
      expect(
        pairs(
          'https://www.google.com/maps/dir/?api=1'
          '&origin=53.1,-2.1&destination=53.2,-2.2',
        ),
        [
          [53.1, -2.1],
          [53.2, -2.2],
        ],
      );
    });

    test('a named place among them is skipped, not guessed at', () {
      // "Buxton" is a town. A road does not start in the middle of one,
      // and inventing a coordinate for it would put a waypoint
      // somewhere nobody chose.
      expect(
        pairs(
          'https://www.google.com/maps/dir/?api=1'
          '&origin=53.1,-2.1&waypoints=Buxton|53.15,-2.0'
          '&destination=53.2,-2.2',
        ),
        [
          [53.1, -2.1],
          [53.15, -2.0],
          [53.2, -2.2],
        ],
      );
    });
  });

  group('the link the browser shows', () {
    test('coordinates in the path', () {
      expect(
        pairs('https://www.google.com/maps/dir/53.2,-2.0/53.3,-1.9/'),
        [
          [53.2, -2.0],
          [53.3, -1.9],
        ],
      );
    });

    test('THE CAMERA IS NOT A STOP', () {
      // @53.25,-1.95,11z is where the map was looking. It is a
      // coordinate, it sits among the stops, and taken as one it drops
      // a waypoint wherever the map happened to be centred — which on
      // a long road is miles off it.
      final points = pairs(
        'https://www.google.com/maps/dir/53.2,-2.0/53.3,-1.9/'
        '@53.25,-1.95,11z/data=!3m1!4b1',
      );

      expect(points, [
        [53.2, -2.0],
        [53.3, -1.9],
      ]);
    });

    test('a place name in the path is skipped too', () {
      expect(
        pairs('https://www.google.com/maps/dir/53.2,-2.0/Buxton/53.3,-1.9/'),
        [
          [53.2, -2.0],
          [53.3, -1.9],
        ],
      );
    });

    test('an encoded place name does not become a coordinate', () {
      expect(
        pairs(
          'https://www.google.com/maps/dir/'
          '53.2,-2.0/Cat+and+Fiddle,+Macclesfield/53.3,-1.9/',
        ),
        [
          [53.2, -2.0],
          [53.3, -1.9],
        ],
      );
    });

    test('the data blob is full of numbers and none of them count', () {
      // !1d-2.0!2d53.2 and friends. Read as coordinates they would
      // double every stop.
      final points = pairs(
        'https://www.google.com/maps/dir/53.2,-2.0/53.3,-1.9/'
        'data=!4m14!4m13!1m5!1m1!1s0x0:0x0!2m2!1d-2.0!2d53.2',
      );

      expect(points.length, 2);
    });
  });

  group('what it refuses', () {
    test('a short link carries nothing until it is followed', () {
      expect(pairs('https://maps.app.goo.gl/abc123'), isEmpty);
      expect(GoogleMapsLink.looksShortened('https://maps.app.goo.gl/abc123'),
          isTrue);
    });

    test('0,0 is not a road', () {
      expect(
        pairs(
          'https://www.google.com/maps/dir/?api=1&origin=0,0'
          '&destination=53.2,-2.0',
        ),
        [
          [53.2, -2.0],
        ],
      );
    });

    test('a latitude past the pole', () {
      expect(
        pairs(
          'https://www.google.com/maps/dir/?api=1&origin=95.0,-2.0'
          '&destination=53.2,-2.0',
        ),
        [
          [53.2, -2.0],
        ],
      );
    });

    test('something that is not a link at all', () {
      expect(pairs('the cat and fiddle'), isEmpty);
      expect(pairs(''), isEmpty);
      expect(pairs('   '), isEmpty);
    });

    test('a maps link with no route in it', () {
      // Somebody shared a PLACE rather than directions.
      expect(pairs('https://www.google.com/maps/@53.25,-1.95,11z'), isEmpty);
    });
  });

  group('is this even a maps link', () {
    test('the ones that are', () {
      expect(
        GoogleMapsLink.looksLikeMaps('https://www.google.com/maps/dir/a/b'),
        isTrue,
      );
      expect(
        GoogleMapsLink.looksLikeMaps('https://maps.app.goo.gl/xyz'),
        isTrue,
      );
      expect(
        GoogleMapsLink.looksLikeMaps('https://google.co.uk/maps/dir/a/b'),
        isTrue,
      );
    });

    test('and the ones that are not', () {
      expect(GoogleMapsLink.looksLikeMaps('https://example.com/x'), isFalse);
      expect(GoogleMapsLink.looksLikeMaps('Cat and Fiddle'), isFalse);
    });
  });
}
