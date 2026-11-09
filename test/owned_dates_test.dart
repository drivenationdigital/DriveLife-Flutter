import 'package:drivelife/widgets/garage/owned_dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a car they still have', () {
    test('reads "since"', () {
      expect(
        OwnedDates.label(
          ownedSince: '2019-03-14T00:00:00.000',
          primaryCar: '1',
        ),
        'Owned since Mar 2019',
      );
    });

    test('an end date is ignored while it is current', () {
      // A current car with a stray owned_until is a data oddity, not a
      // sold one — primary_car is what decides.
      expect(
        OwnedDates.label(
          ownedSince: '2019-03-14',
          ownedUntil: '2023-09-02',
          primaryCar: '1',
        ),
        'Owned since Mar 2019',
      );
    });
  });

  group('a car they had', () {
    test('reads as a range', () {
      expect(
        OwnedDates.label(
          ownedSince: '2019-03-14',
          ownedUntil: '2023-09-02',
          primaryCar: '0',
        ),
        'Owned Mar 2019 - Sept 2023',
      );
    });

    test('with no end date it does not claim they still have it', () {
      final label = OwnedDates.label(ownedSince: '2019-03-14', primaryCar: '0');

      expect(label, 'Owned from Mar 2019');
      expect(label!.contains('since'), isFalse);
    });
  });

  group('nothing worth saying', () {
    test('a dream car has no ownership at all', () {
      expect(
        OwnedDates.label(ownedSince: '2019-03-14', primaryCar: '2'),
        isNull,
      );
    });

    test('no start date', () {
      expect(OwnedDates.label(ownedSince: '', primaryCar: '1'), isNull);
      expect(OwnedDates.label(ownedSince: null, primaryCar: '1'), isNull);
    });

    test("MySQL's zero date is not year 0", () {
      expect(OwnedDates.label(ownedSince: '0000-00-00', primaryCar: '1'), isNull);
    });
  });

  group('older rows', () {
    test('a bare year still shows', () {
      // Rows from before the date picker hold just a year. A year on its
      // own is worth showing; dropping it would lose real information.
      expect(OwnedDates.label(ownedSince: '2019', primaryCar: '1'),
          'Owned since 2019');
    });

    test('a bare year on both sides', () {
      expect(
        OwnedDates.label(ownedSince: '2019', ownedUntil: '2023', primaryCar: '0'),
        'Owned 2019 - 2023',
      );
    });

    test('unparseable is nothing, not a wrong date', () {
      expect(OwnedDates.monthYear('not a date'), isNull);
    });
  });

  test('primaryCar may arrive as an int or a string', () {
    // JSON gives a String, some callers an int. Both must mean past.
    expect(
      OwnedDates.label(ownedSince: '2019-03-01', ownedUntil: '2023-09-01', primaryCar: 0),
      'Owned Mar 2019 - Sept 2023',
    );
  });
}
