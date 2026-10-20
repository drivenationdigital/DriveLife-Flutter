import 'package:drivelife/api/weather_api.dart';
import 'package:drivelife/widgets/events/event_weather.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The forecast on an event page.
///
/// Two things matter here and neither is the networking: that a forecast is
/// only offered when it means something, and that a rough day is recognised
/// as one. Meets are outdoors and people drive an hour to reach them.
void main() {
  DayForecast forecast({
    int code = 0,
    double high = 18,
    double low = 9,
    int rain = 0,
    double wind = 5,
  }) => DayForecast(
    date: DateTime(2026, 6, 1),
    code: code,
    high: high,
    low: low,
    rainChance: rain,
    windMph: wind,
  );

  group('a day worth warning about', () {
    test('a dry, still day is not', () {
      expect(forecast(rain: 10, wind: 8).isRough, isFalse);
    });

    test('an even chance of rain is', () {
      expect(forecast(rain: 50).isRough, isTrue);
    });

    test('so is wind, whatever the sky is doing', () {
      // A still, bright day at 35mph still has covers and pop-ups in it.
      expect(forecast(code: 0, rain: 0, wind: 35).isRough, isTrue);
    });

    test('just below either threshold is not', () {
      expect(forecast(rain: 49, wind: 29).isRough, isFalse);
    });
  });

  group('describeWeather', () {
    test('names the codes that change a plan', () {
      expect(describeWeather(0).label, 'Clear');
      expect(describeWeather(3).label, 'Overcast');
      expect(describeWeather(61).label, 'Rain');
      expect(describeWeather(95).label, 'Thunderstorms');
    });

    test('a bright day with some cloud gets the half sun', () {
      // Codes 1 and 2 are "mainly clear" and "partly cloudy". A plain
      // cloud there reads as overcast and makes a good day look written
      // off, which is the whole reason this is a Cupertino glyph.
      for (final code in [1, 2]) {
        expect(describeWeather(code).icon, CupertinoIcons.cloud_sun_fill);
        expect(describeWeather(code).label, 'Some cloud');
      }
    });

    test('clear is a sun with no cloud on it', () {
      expect(describeWeather(0).icon, CupertinoIcons.sun_max_fill);
    });

    test('every glyph comes from one family', () {
      // Mixing Material and Cupertino shows two drawing styles depending
      // on the forecast, which looks like a bug on whichever day is rarer.
      for (var code = 0; code <= 99; code++) {
        expect(
          describeWeather(code).icon.fontFamily,
          CupertinoIcons.cloud_fill.fontFamily,
          reason: 'code $code',
        );
      }
    });

    test('covers every code the API can return', () {
      // No gaps and no crashes across the whole WMO range — an unmapped
      // code would otherwise reach the page as an exception.
      for (var code = 0; code <= 99; code++) {
        expect(describeWeather(code).label, isNotEmpty, reason: 'code $code');
      }
    });
  });

  group('when no forecast is offered at all', () {
    setUp(WeatherApi.clearCache);

    test('for an event that has already happened', () async {
      final result = await WeatherApi.forDay(
        latitude: 53.8,
        longitude: -1.5,
        date: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(result, isNull);
    });

    test('for one beyond the horizon', () async {
      // A fortnight out, a daily forecast is not information. Showing
      // nothing beats showing a number nobody should plan around.
      final result = await WeatherApi.forDay(
        latitude: 53.8,
        longitude: -1.5,
        date: DateTime.now().add(const Duration(days: 60)),
      );

      expect(result, isNull);
    });
  });

  testWidgets('draws nothing without somewhere to forecast for', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EventWeather(latitude: null, longitude: null, date: null),
        ),
      ),
    );
    await tester.pump();

    // An online event, or one with no address yet. No card, no placeholder,
    // nothing saying it is unavailable.
    expect(find.byType(Container), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
