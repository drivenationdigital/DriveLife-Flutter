import 'package:drivelife/screens/garage/garage_list_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ordering of the Past shelf in the garage.
///
/// Worth testing because getting it wrong is invisible: the list still
/// renders, it is just in the wrong order, and nobody can tell whether
/// a date was misparsed or the sort was backwards by looking at it.
/// The dd/MM/yyyy case is the dangerous one — read as MM/dd it still
/// produces a valid date, just the wrong one.
void main() {
  group('garageOwnershipDate', () {
    test('parses the ISO form the app writes', () {
      final date = garageOwnershipDate('2019-03-15T00:00:00.000');

      expect(date, isNotNull);
      expect(date!.year, 2019);
      expect(date.month, 3);
      expect(date.day, 15);
    });

    test('parses a plain ISO date', () {
      final date = garageOwnershipDate('2021-07-04');

      expect(date!.year, 2021);
      expect(date.month, 7);
      expect(date.day, 4);
    });

    test('legacy dd/MM/yyyy is read DAY first', () {
      // The trap: read as MM/dd this is 3 December, which is a
      // perfectly valid date and silently wrong.
      final date = garageOwnershipDate('03/12/2018');

      expect(date!.day, 3);
      expect(date.month, 12);
      expect(date.year, 2018);
    });

    test('"present" is a sentinel, not a date', () {
      expect(garageOwnershipDate('present'), isNull);
      expect(garageOwnershipDate('Present'), isNull);
    });

    test('empty, null and whitespace give null', () {
      expect(garageOwnershipDate(null), isNull);
      expect(garageOwnershipDate(''), isNull);
      expect(garageOwnershipDate('   '), isNull);
    });

    test('rubbish gives null rather than throwing', () {
      // A garage that will not load is far worse than one ordered oddly.
      for (final value in ['not a date', '//', '1/2', '99/99/9999', 42]) {
        expect(() => garageOwnershipDate(value), returnsNormally);
        expect(garageOwnershipDate(value), isNull, reason: '$value');
      }
    });
  });

  group('sortPastVehiclesNewestFirst', () {
    test('most recently owned comes first', () {
      final vehicles = [
        _car('Corsa', since: '2011-01-01', until: '2015-01-01'),
        _car('Golf GTI', since: '2022-01-01', until: '2024-01-01'),
        _car('Focus ST', since: '2019-01-01', until: '2022-01-01'),
      ];

      sortPastVehiclesNewestFirst(vehicles);

      expect(
        vehicles.map((v) => v['model']).toList(),
        ['Golf GTI', 'Focus ST', 'Corsa'],
      );
    });

    test('keyed on when ownership ended, not began', () {
      // Overlapping ownership: the Golf was bought LATER but sold
      // first. On a Past shelf the question is what was owned most
      // recently, so the Civic — kept until 2023 — leads.
      final vehicles = [
        _car('Golf', since: '2020-01-01', until: '2021-01-01'),
        _car('Civic', since: '2018-01-01', until: '2023-01-01'),
      ];

      sortPastVehiclesNewestFirst(vehicles);

      expect(vehicles.first['model'], 'Civic');
    });

    test('an unparseable end date falls back to the start date', () {
      // Every past vehicle has an end date — that is what puts it on
      // this shelf — so this is the half-filled record, not a current
      // car that wandered in.
      final vehicles = [
        _car('Old', since: '2010-01-01', until: '2012-01-01'),
        _car('Half record', since: '2023-01-01', until: 'not a date'),
      ];

      sortPastVehiclesNewestFirst(vehicles);

      expect(vehicles.first['model'], 'Half record');
    });

    test('undated vehicles sink to the bottom', () {
      final vehicles = [
        _car('No dates', since: null, until: null),
        _car('Dated', since: '2015-01-01', until: '2016-01-01'),
      ];

      sortPastVehiclesNewestFirst(vehicles);

      expect(vehicles.first['model'], 'Dated');
      expect(vehicles.last['model'], 'No dates');
    });

    test('legacy and ISO rows sort together correctly', () {
      // A garage with records written years apart.
      final vehicles = [
        _car('ISO newer', since: '2023-06-01', until: '2024-01-01'),
        _car('Legacy older', since: '01/02/2012', until: '01/02/2014'),
        _car('Legacy middle', since: '05/09/2018', until: '01/01/2020'),
      ];

      sortPastVehiclesNewestFirst(vehicles);

      expect(
        vehicles.map((v) => v['model']).toList(),
        ['ISO newer', 'Legacy middle', 'Legacy older'],
      );
    });

    test('lists of nought and one are left alone', () {
      final empty = <dynamic>[];
      expect(() => sortPastVehiclesNewestFirst(empty), returnsNormally);

      final one = [_car('Only', since: '2015-01-01', until: '2016-01-01')];
      sortPastVehiclesNewestFirst(one);
      expect(one.single['model'], 'Only');
    });

    test('all-undated is left in its original order', () {
      // Rather than shuffling on every pull to refresh.
      final vehicles = [
        _car('A', since: null, until: null),
        _car('B', since: null, until: null),
        _car('C', since: null, until: null),
      ];

      sortPastVehiclesNewestFirst(vehicles);

      expect(vehicles.map((v) => v['model']).toList(), ['A', 'B', 'C']);
    });
  });
}

Map<String, dynamic> _car(
  String model, {
  required String? since,
  required String? until,
}) {
  return <String, dynamic>{
    'model': model,
    'owned_since': since,
    'owned_until': until,
  };
}
