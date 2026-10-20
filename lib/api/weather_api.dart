import 'dart:convert';

import 'package:http/http.dart' as http;

/// The forecast for one day in one place.
class DayForecast {
  /// The day this describes, in the venue's local time.
  final DateTime date;

  /// WMO weather code — what [label] and [icon] are derived from.
  final int code;

  /// Degrees celsius.
  final double high;
  final double low;

  /// 0–100. The chance of rain at some point in the day, not how much.
  final int rainChance;

  /// Miles per hour, the day's maximum.
  final double windMph;

  const DayForecast({
    required this.date,
    required this.code,
    required this.high,
    required this.low,
    required this.rainChance,
    required this.windMph,
  });

  /// Whether this is a day to put a car cover in the boot.
  ///
  /// Used to decide whether the forecast is worth drawing attention to. The
  /// thresholds are deliberately generous: a meet is outdoors and on gravel
  /// as often as tarmac, and people drive an hour to get to one.
  bool get isRough => rainChance >= 50 || windMph >= 30;
}

/// Forecasts for event pages.
///
/// Open-Meteo: no API key, no account, no billing — which is why it is here
/// rather than a provider that needs one wiring through the build.
///
/// ONE THING TO SETTLE BEFORE THIS SHIPS WIDELY: Open-Meteo's free tier is
/// for non-commercial use, under 10,000 calls a day. DriveLife sells
/// tickets, so strictly it wants their commercial plan — or a swap to a
/// provider whose free tier allows trade. Everything provider-specific is
/// in [_url] and [_parse], so a swap is this one file.
class WeatherApi {
  WeatherApi._();

  /// How far ahead the forecast is worth showing.
  ///
  /// Open-Meteo returns 16 days. Past about a week a daily forecast is not
  /// information, so an event in three months shows nothing at all rather
  /// than a number nobody should plan around.
  static const int horizonDays = 10;

  /// Answers already fetched this session, keyed by place and day.
  ///
  /// A forecast does not move fast enough to be worth asking twice while
  /// somebody taps between an event and the list it came from.
  static final Map<String, DayForecast?> _cache = {};

  /// Clears the cache. For tests, and for a pull-to-refresh that should mean
  /// what it says.
  static void clearCache() => _cache.clear();

  /// The forecast for [date] at [latitude]/[longitude], or null.
  ///
  /// Null for every reason it could fail: no network, a bad response, a
  /// date beyond the horizon, a date in the past. The event page shows
  /// nothing in that case, which is the right answer — a weather block that
  /// says "unavailable" is a row of furniture telling you it is broken.
  static Future<DayForecast?> forDay({
    required double latitude,
    required double longitude,
    required DateTime date,
  }) async {
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime.now();
    final from = DateTime(today.year, today.month, today.day);
    final ahead = day.difference(from).inDays;

    if (ahead < 0 || ahead > horizonDays) return null;

    final key =
        '${latitude.toStringAsFixed(3)},'
        '${longitude.toStringAsFixed(3)},'
        '${_ymd(day)}';

    if (_cache.containsKey(key)) return _cache[key];

    try {
      final response = await http
          .get(_url(latitude, longitude, day))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return _cache[key] = null;

      return _cache[key] = _parse(jsonDecode(response.body), day);
    } catch (_) {
      // Cached as a failure, so a page that is rebuilt twenty times while
      // the user scrolls does not retry twenty times.
      return _cache[key] = null;
    }
  }

  static Uri _url(double latitude, double longitude, DateTime day) {
    return Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,'
          'precipitation_probability_max,wind_speed_10m_max',
      // The venue's timezone, not the phone's. An event is on the day the
      // venue says it is.
      'timezone': 'auto',
      'wind_speed_unit': 'mph',
      'start_date': _ymd(day),
      'end_date': _ymd(day),
    });
  }

  static DayForecast? _parse(dynamic body, DateTime day) {
    if (body is! Map) return null;

    final daily = body['daily'];
    if (daily is! Map) return null;

    double? number(String field) {
      final values = daily[field];
      if (values is! List || values.isEmpty) return null;
      final value = values.first;
      if (value is num) return value.toDouble();
      return double.tryParse('$value');
    }

    final high = number('temperature_2m_max');
    final low = number('temperature_2m_min');
    final code = number('weather_code');

    // Temperature is the one thing this cannot be drawn without.
    if (high == null || low == null) return null;

    return DayForecast(
      date: day,
      code: code?.round() ?? 0,
      high: high,
      low: low,
      rainChance: number('precipitation_probability_max')?.round() ?? 0,
      windMph: number('wind_speed_10m_max') ?? 0,
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
