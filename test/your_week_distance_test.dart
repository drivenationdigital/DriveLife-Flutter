import 'package:drivelife/models/user_model.dart';
import 'package:drivelife/widgets/home/your_week.dart';
import 'package:flutter_test/flutter_test.dart';

LastLocation at(double lat, double lng) =>
    LastLocation(latitude: lat, longitude: lng, updatedAt: '', country: 'GB');

void main() {
  // Real places, real distances, so a broken formula fails loudly rather
  // than returning a plausible-looking number.
  final london = at(51.5074, -0.1278);

  group('miles between two points', () {
    test('London to Birmingham is about 101 miles', () {
      final miles = YourWeekPanelState.debugMilesFrom(london, {
        'latitude': 52.4862,
        'longitude': -1.8904,
      });

      expect(miles, isNotNull);
      expect(miles!, closeTo(101, 3));
    });

    test('London to Manchester is about 163 miles', () {
      final miles = YourWeekPanelState.debugMilesFrom(london, {
        'latitude': 53.4808,
        'longitude': -2.2426,
      });

      expect(miles!, closeTo(163, 4));
    });

    test('London to Edinburgh is about 332 miles', () {
      final miles = YourWeekPanelState.debugMilesFrom(london, {
        'latitude': 55.9533,
        'longitude': -3.1883,
      });

      expect(miles!, closeTo(332, 6));
    });

    test('the same place is zero', () {
      final miles = YourWeekPanelState.debugMilesFrom(london, {
        'latitude': 51.5074,
        'longitude': -0.1278,
      });

      expect(miles!, closeTo(0, 0.01));
    });

    test('east-west distance is not overstated', () {
      // The flat-earth shortcut's signature failure. At London's
      // latitude a degree of longitude is about 0.62 of a degree of
      // latitude, so Pythagoras on raw degrees would return roughly 69
      // miles here instead of 43.
      final miles = YourWeekPanelState.debugMilesFrom(london, {
        'latitude': 51.5074,
        'longitude': 0.8722, // one degree east
      });

      expect(miles!, closeTo(43, 1));
    });
  });

  group('coordinates that mean "we do not know"', () {
    test('missing', () {
      expect(YourWeekPanelState.debugMilesFrom(london, {}), isNull);
    });

    test('null island is treated as unset, not as a point off Africa', () {
      expect(
        YourWeekPanelState.debugMilesFrom(london, {
          'latitude': 0,
          'longitude': 0,
        }),
        isNull,
      );
    });

    test('strings parse, because the API sends them that way', () {
      final miles = YourWeekPanelState.debugMilesFrom(london, {
        'latitude': '52.4862',
        'longitude': '-1.8904',
      });

      expect(miles!, closeTo(101, 3));
    });

    test('unparseable strings are null rather than zero', () {
      expect(
        YourWeekPanelState.debugMilesFrom(london, {
          'latitude': 'TBA',
          'longitude': 'TBA',
        }),
        isNull,
      );
    });
  });

  group('how it reads', () {
    test('under ten miles keeps a decimal', () {
      expect(
        YourWeekPanelState.debugDistanceLabel({'distance': 2.4}),
        '2.4 mi',
      );
    });

    test('ten and over rounds', () {
      expect(
        YourWeekPanelState.debugDistanceLabel({'distance': 14.3}),
        '14 mi',
      );
    });

    test('no distance means no label, not "0 mi"', () {
      expect(YourWeekPanelState.debugDistanceLabel({}), isNull);
      expect(
        YourWeekPanelState.debugDistanceLabel({'distance': double.infinity}),
        isNull,
      );
    });
  });

  group('parsing the API date format', () {
    // The events endpoint sends "01/26/2026 18:00": slashes, a space
    // before the time, and MONTH FIRST. DateTime.tryParse returns null
    // for every one of them, which is why every card read "Date TBA".
    test('month comes first, not the day', () {
      final d = YourWeekPanelState.debugParseEventDate('01/26/2026 18:00');

      expect(d, isNotNull);
      expect(d!.year, 2026);
      expect(d.month, 1, reason: '01 is January, not the 1st');
      expect(d.day, 26);
      expect(d.hour, 18);
      expect(d.minute, 0);
    });

    test('the ambiguous case, where day-first would silently be wrong', () {
      // 05/06 is 6 May read correctly and 5 June read backwards. Nothing
      // throws either way, which is what makes it worth a test.
      final d = YourWeekPanelState.debugParseEventDate('05/06/2026 09:30');

      expect(d!.month, 5);
      expect(d.day, 6);
      expect(d.hour, 9);
      expect(d.minute, 30);
    });

    test('a date with no time is midnight', () {
      final d = YourWeekPanelState.debugParseEventDate('12/25/2026');

      expect(d!.month, 12);
      expect(d.day, 25);
      expect(d.hour, 0);
    });

    test('ISO still works, so a fixed API would not break this', () {
      final d = YourWeekPanelState.debugParseEventDate('2026-01-26T18:00:00');

      expect(d!.month, 1);
      expect(d.day, 26);
      expect(d.hour, 18);
    });

    test('rubbish is null rather than a wrong date', () {
      for (final bad in ['', '   ', 'TBA', 'soon', '26/2026', null]) {
        expect(
          YourWeekPanelState.debugParseEventDate(bad),
          isNull,
          reason: 'should not invent a date from "$bad"',
        );
      }
    });

    test('an impossible month is rejected, not wrapped into next year', () {
      // DateTime(2026, 26, 1) silently rolls over to February 2028.
      expect(
        YourWeekPanelState.debugParseEventDate('26/01/2026 10:00'),
        isNull,
      );
    });
  });
}
