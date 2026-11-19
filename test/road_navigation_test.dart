import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/models/road_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Handing a road to a maps app.
void main() {
  List<RoadPoint> line(int count) => List.generate(
    count,
    (i) => RoadPoint(53.0 + (i * 0.01), -2.0),
  );

  group('thinning the line down to a URL', () {
    test('a short road goes through whole', () {
      expect(RoadNavigation.sample(line(4), 10).length, 4);
    });

    test('a long one comes down to the limit', () {
      expect(RoadNavigation.sample(line(400), 10).length, 10);
    });

    test('both ends survive', () {
      // The ends are the two points that must be right: one is where
      // the road starts and the other is the destination.
      final sampled = RoadNavigation.sample(line(400), 10);

      expect(sampled.first.lat, closeTo(53.0, 0.0001));
      expect(sampled.last.lat, closeTo(53.0 + (399 * 0.01), 0.0001));
    });

    test('and the order', () {
      final sampled = RoadNavigation.sample(line(400), 10);

      for (var i = 1; i < sampled.length; i++) {
        expect(sampled[i].lat, greaterThan(sampled[i - 1].lat));
      }
    });

    test('the points are spread, not bunched at the start', () {
      // Taking the first nine would pin the route to the first few
      // hundred metres and leave the maps app free to rejoin the main
      // road for the rest of it.
      final sampled = RoadNavigation.sample(line(400), 10);

      final middle = sampled[5].lat;

      expect(middle, greaterThan(53.0 + (150 * 0.01)));
      expect(middle, lessThan(53.0 + (250 * 0.01)));
    });

    test('nothing in, nothing out', () {
      expect(RoadNavigation.sample(const [], 10), isEmpty);
    });

    test('a point at 0,0 is not a stop', () {
      // The Gulf of Guinea. Sending somebody there is worse than
      // leaving the point out.
      final sampled = RoadNavigation.sample(const [
        RoadPoint(53.0, -2.0),
        RoadPoint(0, 0),
        RoadPoint(53.1, -2.0),
      ], 10);

      expect(sampled.length, 2);
    });
  });

  group('the directions URL', () {
    test('ends at the end of the road', () {
      final url = RoadNavigation.directionsUrl(const [
        RoadPoint(53.0, -2.0),
        RoadPoint(53.1, -2.1),
      ])!;

      expect(url.queryParameters['destination'], '53.100000,-2.100000');
    });

    test('and starts at the start of the road', () {
      // NOT at the driver's location. That spent one of the nine free
      // waypoints on getting to the road, which meant a road imported
      // with ten points could not be sent at all — and it drew a leg
      // across a county over the top of the thing being looked at.
      final url = RoadNavigation.directionsUrl(const [
        RoadPoint(53.0, -2.0),
        RoadPoint(53.1, -2.1),
      ])!;

      expect(url.queryParameters['origin'], '53.000000,-2.000000');
    });

    test('a two-point road carries no waypoints parameter at all', () {
      // Empty is not the same as absent: Google reads an empty
      // waypoints parameter as a stop it cannot find.
      final url = RoadNavigation.directionsUrl(const [
        RoadPoint(53.0, -2.0),
        RoadPoint(53.1, -2.1),
      ])!;

      expect(url.queryParameters.containsKey('waypoints'), isFalse);
    });

    test('the middle becomes the waypoints, and only the middle', () {
      final url = RoadNavigation.directionsUrl(const [
        RoadPoint(53.0, -2.0),
        RoadPoint(53.1, -2.0),
        RoadPoint(53.2, -2.0),
      ])!;

      expect(url.queryParameters['origin'], '53.000000,-2.000000');
      expect(url.queryParameters['waypoints'], '53.100000,-2.000000');
      expect(url.queryParameters['destination'], '53.200000,-2.000000');
    });

    test('latitude first, which is the opposite of GeoJSON', () {
      // Swapped, this sends somebody to the Indian Ocean — and at UK
      // latitudes both numbers are a similar size, so the URL looks
      // perfectly reasonable.
      final url = RoadNavigation.directionsUrl(const [
        RoadPoint(53.2585, -2.0074),
        RoadPoint(53.2300, -1.9100),
      ])!;

      expect(url.queryParameters['destination'], startsWith('53.23'));
    });

    test('driving, not walking', () {
      expect(
        RoadNavigation.directionsUrl(line(3))!.queryParameters['travelmode'],
        'driving',
      );
    });

    test('a long road still fits inside the waypoint limit', () {
      final url = RoadNavigation.directionsUrl(line(600))!;

      final waypoints = url.queryParameters['waypoints']!.split('|');

      // An origin, a destination and nine waypoints between them is
      // the free allowance — and all eleven are usable now that the
      // origin is the road rather than the driver.
      expect(waypoints.length, RoadNavigation.maxStops - 2);
      expect(waypoints.length, lessThanOrEqualTo(9));
    });

    test('a road imported with ten points sends all ten', () {
      // The case that prompted this. Google takes ten stops before the
      // destination; spending one on the driver's location meant a
      // ten-point import lost a point every time.
      final url = RoadNavigation.directionsUrl(line(10))!;

      final stops = <String>[
        url.queryParameters['origin']!,
        ...url.queryParameters['waypoints']!.split('|'),
        url.queryParameters['destination']!,
      ];

      expect(stops.length, 10);
      expect(stops.toSet().length, 10, reason: 'no point sent twice');
    });

    test('a road with one point has no route', () {
      expect(RoadNavigation.directionsUrl(const [RoadPoint(53, -2)]), isNull);
      expect(RoadNavigation.directionsUrl(const []), isNull);
    });
  });

  group('getting to the start', () {
    test('is just the first point', () {
      final url = RoadNavigation.startUrl(const [
        RoadPoint(53.0, -2.0),
        RoadPoint(53.1, -2.1),
      ])!;

      expect(url.queryParameters['destination'], '53.000000,-2.000000');
      expect(url.queryParameters.containsKey('waypoints'), isFalse);
    });

    test('and there is none without a road', () {
      expect(RoadNavigation.startUrl(const []), isNull);
    });
  });
}
