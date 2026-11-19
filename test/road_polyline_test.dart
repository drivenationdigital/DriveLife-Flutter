import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/models/road_polyline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opening the shape of a road.
///
/// The same worked example php-api/tools/roads-test.php uses, on
/// purpose: neither end owns this format, so the only thing worth
/// asserting is that both agree with the specification and therefore
/// with Mapbox, which is where these strings come from.
void main() {
  // The published example from the format's own specification.
  const spec = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

  final specPoints = [
    const RoadPoint(38.5, -120.2),
    const RoadPoint(40.7, -120.95),
    const RoadPoint(43.252, -126.453),
  ];

  List<List<double>> pairs(List<RoadPoint> points) =>
      points.map((p) => [p.lat, p.lng]).toList();

  group('decoding', () {
    test('the specification example', () {
      expect(pairs(RoadPolyline.decode(spec)), pairs(specPoints));
    });

    test('and back to the same string', () {
      expect(RoadPolyline.encode(specPoints), spec);
    });

    test('a UK road survives the round trip', () {
      final road = [
        const RoadPoint(53.2585, -2.0074),
        const RoadPoint(53.2621, -2.0153),
        const RoadPoint(53.2689, -2.0201),
      ];

      expect(pairs(RoadPolyline.decode(RoadPolyline.encode(road))), pairs(road));
    });

    test('a road heading south-west still heads south-west', () {
      // Every delta is negative here, which is where a sign error
      // hides: a broken decoder sends the road north-east instead.
      final road = [
        const RoadPoint(53.0, -2.0),
        const RoadPoint(52.9, -2.1),
        const RoadPoint(52.8, -2.2),
      ];

      expect(pairs(RoadPolyline.decode(RoadPolyline.encode(road))), pairs(road));
    });

    test('an empty string is an empty line', () {
      expect(RoadPolyline.decode(''), isEmpty);
      expect(RoadPolyline.encode(const []), '');
    });

    test('half a pair is not a point', () {
      // Eight characters is a whole latitude and half a longitude. A
      // latitude on its own would be a coordinate on the Greenwich
      // meridian, which is a real place and the wrong one.
      expect(RoadPolyline.decode(spec.substring(0, 8)), isEmpty);
    });

    test('a complete pair followed by half of one keeps the pair', () {
      expect(
        pairs(RoadPolyline.decode(spec.substring(0, 13))),
        [
          [38.5, -120.2],
        ],
      );
    });
  });

  group('GeoJSON ordering', () {
    test('longitude comes first, which is the opposite of everywhere else', () {
      // Swapped, a road in Macclesfield draws in the Indian Ocean —
      // and at UK latitudes both numbers are a similar size, so nothing
      // looks wrong until it is on screen.
      expect(
        RoadPolyline.toGeoJson([const RoadPoint(53.2585, -2.0074)]),
        [
          [-2.0074, 53.2585],
        ],
      );
    });
  });

  group('the box around a road', () {
    final road = [
      const RoadPoint(53.25, -2.01),
      const RoadPoint(53.27, -1.98),
      const RoadPoint(53.24, -1.96),
    ];

    test('holds every point', () {
      final bounds = RoadBounds.of(road)!;

      expect(bounds.minLat, 53.24);
      expect(bounds.maxLat, 53.27);
      expect(bounds.minLng, -2.01);
      expect(bounds.maxLng, -1.96);
    });

    test('its centre is in the middle', () {
      final centre = RoadBounds.of(road)!.centre;

      expect(centre.lat, closeTo(53.255, 0.0001));
      expect(centre.lng, closeTo(-1.985, 0.0001));
    });

    test('there is no box around nothing', () {
      // Null rather than a box at 0,0, which would send the camera to
      // the Gulf of Guinea.
      expect(RoadBounds.of(const []), isNull);
    });

    test('one point is its own box', () {
      final bounds = RoadBounds.of([const RoadPoint(53.25, -2.01)])!;

      expect(bounds.minLat, bounds.maxLat);
      expect(bounds.centre.lat, 53.25);
    });
  });

  group('the zoom that fits it', () {
    const width = 400.0;
    const height = 600.0;

    double zoomOf(List<RoadPoint> points) =>
        RoadBounds.of(points)!.zoomFor(widthPx: width, heightPx: height);

    test('a longer road is zoomed further out', () {
      final short = zoomOf([
        const RoadPoint(53.25, -2.01),
        const RoadPoint(53.27, -1.98),
      ]);

      final long = zoomOf([
        const RoadPoint(53.25, -2.01),
        const RoadPoint(54.50, -1.00),
      ]);

      expect(long, lessThan(short));
    });

    test('a UK B-road lands somewhere sensible', () {
      // Not an exact number — the point is that an eight-mile road is
      // not shown at county scale or from a hedgerow.
      final zoom = zoomOf([
        const RoadPoint(53.2585, -2.0074),
        const RoadPoint(53.2300, -1.9100),
      ]);

      expect(zoom, greaterThan(9));
      expect(zoom, lessThan(14));
    });

    test('a road with no length is not infinity', () {
      // Both spans are zero, so the fit is a division by zero. It
      // answers "as close as we go" instead.
      final zoom = zoomOf([
        const RoadPoint(53.25, -2.01),
        const RoadPoint(53.25, -2.01),
      ]);

      expect(zoom.isFinite, isTrue);
      expect(zoom, 16);
    });

    test('a road across a continent is still a usable zoom', () {
      final zoom = zoomOf([
        const RoadPoint(60.0, -8.0),
        const RoadPoint(36.0, 20.0),
      ]);

      expect(zoom.isFinite, isTrue);
      expect(zoom, greaterThanOrEqualTo(3));
    });

    test('the tighter axis wins', () {
      // A tall, narrow road in a tall, narrow viewport: height is what
      // constrains it, and fitting the width while the ends run off the
      // top is not fitting.
      final tall = RoadBounds.of([
        const RoadPoint(52.0, -2.0),
        const RoadPoint(54.0, -1.99),
      ])!;

      final wide = RoadBounds.of([
        const RoadPoint(53.0, -3.0),
        const RoadPoint(53.01, -1.0),
      ])!;

      expect(
        tall.zoomFor(widthPx: width, heightPx: height),
        lessThan(10),
      );
      expect(
        wide.zoomFor(widthPx: width, heightPx: height),
        lessThan(10),
      );
    });

    test('a viewport with no size does not return a nonsense zoom', () {
      // Which happens for one frame before layout.
      final bounds = RoadBounds.of([
        const RoadPoint(53.25, -2.01),
        const RoadPoint(53.27, -1.98),
      ])!;

      expect(bounds.zoomFor(widthPx: 0, heightPx: 0), 12);
    });
  });
}
