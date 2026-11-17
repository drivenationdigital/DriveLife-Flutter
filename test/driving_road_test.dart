import 'package:drivelife/models/driving_road.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading a road back off the wire.
///
/// Worth testing because the numbers here come out of MySQL columns
/// that PHP types inconsistently: `length_miles` is a DECIMAL and
/// arrives as the string "12.40", while `drove_count` is an INT and
/// arrives as a number. A cast that works for one throws on the other,
/// and the symptom is a screen that is blank for no visible reason.
void main() {
  group('reading the payload', () {
    test('the ordinary case', () {
      final road = DrivingRoad.fromMap(const {
        'id': 7,
        'site': 'GB',
        'title': 'Cat and Fiddle',
        'slug': 'cat-and-fiddle',
        'summary': 'A537 between Macclesfield and Buxton',
        'region': 'Peak District',
        'length_miles': 11.4,
        'status': 'published',
        'drove_count': 3,
        'start': {'lat': 53.2585, 'lng': -2.0074},
        'mid': {'lat': 53.2444, 'lng': -1.9609},
      });

      expect(road.id, 7);
      expect(road.title, 'Cat and Fiddle');
      expect(road.lengthMiles, 11.4);
      expect(road.isPublished, isTrue);
      expect(road.start.lat, 53.2585);
      expect(road.mid.isReal, isTrue);
    });

    test('a DECIMAL column arriving as a string', () {
      // length_miles is DECIMAL(7,2). PHP hands it back as "12.40".
      final road = DrivingRoad.fromMap(const {
        'id': '7',
        'length_miles': '12.40',
        'drove_count': '3',
      });

      expect(road.id, 7);
      expect(road.lengthMiles, 12.4);
      expect(road.droveCount, 3);
    });

    test('a missing payload is not a crash', () {
      final road = DrivingRoad.fromMap(const {});

      expect(road.id, 0);
      expect(road.title, '');
      expect(road.lengthMiles, 0);
      expect(road.hasShape, isFalse);
      expect(road.mid.isReal, isFalse);
    });

    test('a list row carries no shape, a detail row does', () {
      final listRow = DrivingRoad.fromMap(const {'id': 7});
      final detail = DrivingRoad.fromMap(const {
        'id': 7,
        'polyline': '_p~iF~ps|U',
      });

      // Twenty roads' worth of geometry is most of a megabyte for a
      // screen that draws none of it, so the list leaves it out.
      expect(listRow.hasShape, isFalse);
      expect(detail.hasShape, isTrue);
    });

    test('what this person has done with it', () {
      final road = DrivingRoad.fromMap(const {
        'id': 7,
        'i_drove': true,
        'i_saved': false,
      });

      expect(road.iDrove, isTrue);
      expect(road.iSaved, isFalse);
    });

    test('a signed-out reader is told neither, not told no', () {
      // The server omits both keys when nobody is signed in. They read
      // as false, which is what the buttons should show.
      final road = DrivingRoad.fromMap(const {'id': 7});

      expect(road.iDrove, isFalse);
      expect(road.iSaved, isFalse);
    });
  });

  group('a coordinate', () {
    test('a real one', () {
      expect(const RoadPoint(53.25, -2.0).isReal, isTrue);
    });

    test('0,0 is not a place a road is', () {
      // The Gulf of Guinea. Every time, this is a coordinate that
      // failed to parse upstream rather than somewhere anybody drove.
      expect(RoadPoint.none.isReal, isFalse);
      expect(const RoadPoint(0, 0).isReal, isFalse);
    });

    test('but 0 latitude with a real longitude is', () {
      expect(const RoadPoint(0, -1.1).isReal, isTrue);
    });

    test('something that is not a map', () {
      expect(RoadPoint.fromMap(null).isReal, isFalse);
      expect(RoadPoint.fromMap('53.25,-2.0').isReal, isFalse);
    });
  });

  group('the labels', () {
    test('a long road is a whole number', () {
      expect(
        const DrivingRoad(id: 1, lengthMiles: 11.4).lengthLabel,
        '11 miles',
      );
    });

    test('a short one keeps its decimal', () {
      // "2 miles" and "2.4 miles" are the same claim at a scale where
      // the difference is a fifth of the road.
      expect(
        const DrivingRoad(id: 1, lengthMiles: 2.4).lengthLabel,
        '2.4 miles',
      );
    });

    test('no length says nothing rather than "0 miles"', () {
      expect(const DrivingRoad(id: 1).lengthLabel, '');
    });

    test('how far away', () {
      expect(
        const DrivingRoad(id: 1, distanceMiles: 12.3).awayLabel,
        '12 miles away',
      );
    });

    test('closer than a mile is said in words', () {
      // "0 miles away" reads as a bug rather than as "it is here".
      expect(
        const DrivingRoad(id: 1, distanceMiles: 0.4).awayLabel,
        'Less than a mile away',
      );
    });

    test('a list that was not a nearby query says nothing', () {
      expect(const DrivingRoad(id: 1).awayLabel, '');
    });
  });

  group('copyWith, for a button that was just pressed', () {
    test('the flag and the count move together', () {
      const road = DrivingRoad(id: 1, droveCount: 3);

      final after = road.copyWith(iDrove: true, droveCount: 4);

      expect(after.iDrove, isTrue);
      expect(after.droveCount, 4);
    });

    test('and nothing else moves with them', () {
      const road = DrivingRoad(
        id: 1,
        title: 'Cat and Fiddle',
        lengthMiles: 11.4,
        polyline: '_p~iF~ps|U',
      );

      final after = road.copyWith(iSaved: true);

      expect(after.title, 'Cat and Fiddle');
      expect(after.lengthMiles, 11.4);
      expect(after.polyline, '_p~iF~ps|U');
      expect(after.iDrove, isFalse);
    });
  });
}
