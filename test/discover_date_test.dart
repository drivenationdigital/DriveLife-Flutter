import 'package:drivelife/screens/discover/discover_place.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the event date shown on Discover's result cards.
///
/// The format the server sends is the trap: `MM/DD/YYYY HH:MM`, month first,
/// built by PHP's `date('m/d/Y', ...)`. Anything that assumed day-first would
/// read 01/02/2026 as 1 February rather than 2 January — wrong for the first
/// twelve days of every month, and never obviously wrong.
void main() {
  Map<String, dynamic> json(dynamic startDate) => {
    'id': 1,
    'title': 'Teesside Auto Show',
    'location': 'Middlesbrough',
    'latitude': 54.57,
    'longitude': -1.23,
    'start_date': startDate,
  };

  group('parsing', () {
    test('reads the month-first format the endpoint sends', () {
      final place = DiscoverPlace.fromEvent(json('01/02/2026 18:00'))!;

      // 2 January, not 1 February.
      expect(place.startsAt, DateTime(2026, 1, 2));
    });

    test('reads a date with no time', () {
      final place = DiscoverPlace.fromEvent(json('10/18/2026'))!;
      expect(place.startsAt, DateTime(2026, 10, 18));
    });

    test('leaves the date off rather than showing a wrong one', () {
      for (final bad in [null, '', 'TBC', '2026-10-18', '13/01/2026', '//']) {
        expect(
          DiscoverPlace.fromEvent(json(bad))!.startsAt,
          isNull,
          reason: 'start_date "$bad" should not produce a date',
        );
      }
    });

    test('rejects a day that does not exist in that month', () {
      // DateTime rolls 31 February into March rather than refusing it, which
      // would put an event on a date the server never sent.
      expect(DiscoverPlace.fromEvent(json('02/31/2026'))!.startsAt, isNull);
    });

    test('a venue has no date', () {
      final venue = DiscoverPlace.fromVenue({
        'ID': 1,
        'title': 'Croft Circuit',
        'latitude': 54.45,
        'longitude': -1.55,
      })!;

      expect(venue.startsAt, isNull);
    });
  });

  group('label', () {
    final now = DateTime(2026, 10, 1);

    test('drops the year when it is this year', () {
      // The cards are narrow and the date shares its line with the location;
      // "2026" on every row buys nothing and costs the place name.
      expect(
        discoverDateLabel(DateTime(2026, 10, 18), now: now),
        'Sun 18 Oct',
      );
    });

    test('keeps the year when it is not', () {
      expect(
        discoverDateLabel(DateTime(2027, 3, 4), now: now),
        'Thu 4 Mar 27',
      );
    });

    test('is null when there is no date', () {
      expect(discoverDateLabel(null, now: now), isNull);
    });
  });
}
