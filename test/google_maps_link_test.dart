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

    test('a blob that does not match the path is not read', () {
      // Two stops in the path, one pair in the blob. They disagree
      // about what the route is, so the blob is dropped whole rather
      // than mixed in — read as extra stops its numbers would double
      // the route back on itself.
      final points = pairs(
        'https://www.google.com/maps/dir/53.2,-2.0/53.3,-1.9/'
        'data=!4m14!4m13!1m5!1m1!1s0x0:0x0!2m2!1d-2.0!2d53.2',
      );

      expect(points, [
        [53.2, -2.0],
        [53.3, -1.9],
      ]);
    });
  });

  // ── THE ONE THAT BIT ──────────────────────────────────────────────
  //
  // A real route is planned between real places — a car park to a car
  // park — and those stops are written into the path as NAMES. Only
  // the pins dropped in between are numbers. Reading the path alone
  // gives back the middle of the route and loses both ends silently.
  group('stops the path only names', () {
    // A REAL link, as maps.app.goo.gl/DgEoefcrbJHqgyeB7 resolves. Kept
    // verbatim apart from its tracking query, because every guess at
    // this encoding has been wrong and the thing itself is the only
    // reliable fixture.
    const sevenStops =
        'https://www.google.co.uk/maps/dir/'
        'Helmsley+Market+Place+Parking,+Market+Pl,+Helmsley,+York+YO62+5BH/'
        '54.3866883,-0.9535802/'
        '54.4614216,-0.9256848/'
        '54.4986472,-0.8908063/'
        '54.4030181,-0.7482026/'
        '54.4183671,-0.6841913/'
        'Eastgate+Car+Park,+Pickering+YO18+7DP/'
        '@54.3643826,-0.9984114,10.75z/'
        'data=!4m19!4m18'
        '!1m5!1m1!1s0x487ecf00169b3ac3:0x607a67f98c15026d'
        '!2m2!1d-1.0613535!2d54.2461552'
        '!1m0!1m0!1m0!1m0!1m0'
        '!1m5!1m1!1s0x487f288f16d2af79:0xf08f4ed380242ea9'
        '!2m2!1d-0.7744189!2d54.2438582'
        '!3e0!5m1!1e1';

    test('the blob fills the two ends the path only names', () {
      // Seven stops: a car park, five dropped pins, a car park. Read
      // from the path alone this came back as the five pins — a road
      // starting and ending two stops short of where it was drawn.
      expect(pairs(sevenStops), [
        [54.2461552, -1.0613535], // Helmsley Market Place Parking
        [54.3866883, -0.9535802],
        [54.4614216, -0.9256848],
        [54.4986472, -0.8908063],
        [54.4030181, -0.7482026],
        [54.4183671, -0.6841913],
        [54.2438582, -0.7744189], // Eastgate Car Park, Pickering
      ]);
    });

    test('a dropped pin is !1m0 and carries no pair of its own', () {
      // The reason a gap FILL is right and a wholesale replace is not:
      // the blob holds two pairs for seven stops, because the five in
      // the path are not repeated. A rule that wanted one pair per
      // stop finds two, calls it a disagreement, and throws away the
      // only copy of the ends that exists.
      final blob = sevenStops.split('data=').last;

      expect('!2m2!1d'.allMatches(blob).length, 2);
      expect('!1m0'.allMatches(blob).length, 5);
    });

    test('nothing is lost, and read() says so', () {
      final read = GoogleMapsLink.read(sevenStops);

      expect(read.stops, 7);
      expect(read.points.length, 7);
    });

    test('longitude is written first and is not read first', () {
      // !1d is longitude, !2d is latitude — the opposite way round
      // from every other coordinate in the file. Swapped, this lands
      // in the Gulf of Guinea instead of Derbyshire.
      final points = pairs(
        'https://www.google.com/maps/dir/Buxton/Bakewell/'
        'data=!1m3!2m2!1d-1.9115!2d53.2588'
        '!1m3!2m2!1d-1.6753!2d53.2127',
      );

      expect(points, [
        [53.2588, -1.9115],
        [53.2127, -1.6753],
      ]);
    });

    test('the camera is still not a stop when there is a blob', () {
      // @ sits between the last stop and data=, so it has to be
      // skipped BEFORE the count that decides whether the blob is
      // trusted — counted as a stop it would make three against two
      // and throw the blob away.
      final points = pairs(
        'https://www.google.com/maps/dir/Buxton/Bakewell/'
        '@53.235,-1.79,11z/'
        'data=!1m3!2m2!1d-1.9115!2d53.2588'
        '!1m3!2m2!1d-1.6753!2d53.2127',
      );

      expect(points.length, 2);
    });

    test('with no blob the named stops are still skipped', () {
      // Unchanged, and deliberately so: a town name is not a point on
      // a road, and there is nothing here to turn it into one.
      const url = 'https://www.google.com/maps/dir/Buxton/53.3,-1.9/Bakewell/';

      expect(pairs(url), [
        [53.3, -1.9],
      ]);

      // But the count still reports all three, so the caller can say
      // what went missing rather than hand back a shorter road.
      final read = GoogleMapsLink.read(url);

      expect(read.stops, 3);
      expect(read.points.length, 1);
    });

    test('a blob that fills only some gaps fills none of them', () {
      // Two named stops, one pair. Which stop is it? Guessing puts a
      // road's end at its beginning, so neither is placed.
      expect(
        pairs(
          'https://www.google.com/maps/dir/Buxton/53.3,-1.9/Bakewell/'
          'data=!1m5!1m1!1s0x0:0x0!2m2!1d-1.9115!2d53.2588',
        ),
        [
          [53.3, -1.9],
        ],
      );
    });

    test('a percent sign in a place name does not throw', () {
      // pathSegments arrives decoded. Decoding it a second time made a
      // stray '%' a FormatException, thrown straight out of a parser
      // whose only caller is a paste handler.
      expect(
        () => pairs(
          'https://www.google.com/maps/dir/'
          '${Uri.encodeComponent('100% Garage')}/53.3,-1.9/',
        ),
        returnsNormally,
      );
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
