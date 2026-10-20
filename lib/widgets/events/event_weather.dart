import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../api/weather_api.dart';

/// What a WMO weather code means, in a word and a glyph.
///
/// The codes are the standard set Open-Meteo returns. They are grouped
/// rather than mapped one to one: the difference between "slight" and
/// "moderate" drizzle is not a thing anybody deciding whether to drive to a
/// car meet needs spelled out.
///
/// Cupertino glyphs rather than Material ones, for the whole set. Material
/// has no sun-behind-cloud — its nearest is a plain cloud, which reads as
/// overcast and makes a bright day with a bit of cloud look like a write-off.
/// Cupertino has the half-sun, and once one icon comes from that family they
/// all have to, or the card shows two drawing styles depending on the day.
({IconData icon, String label}) describeWeather(int code) {
  if (code == 0) {
    return (icon: CupertinoIcons.sun_max_fill, label: 'Clear');
  }
  if (code <= 2) {
    // 1 and 2 are "mainly clear" and "partly cloudy" — sun with cloud.
    return (icon: CupertinoIcons.cloud_sun_fill, label: 'Some cloud');
  }
  if (code == 3) {
    return (icon: CupertinoIcons.cloud_fill, label: 'Overcast');
  }
  if (code <= 48) {
    return (icon: CupertinoIcons.cloud_fog_fill, label: 'Fog');
  }
  if (code <= 57) {
    return (icon: CupertinoIcons.cloud_drizzle_fill, label: 'Drizzle');
  }
  if (code <= 67) {
    return (icon: CupertinoIcons.cloud_rain_fill, label: 'Rain');
  }
  if (code <= 77) {
    return (icon: CupertinoIcons.cloud_snow_fill, label: 'Snow');
  }
  if (code <= 82) {
    return (icon: CupertinoIcons.cloud_heavyrain_fill, label: 'Showers');
  }
  if (code <= 86) {
    return (icon: CupertinoIcons.cloud_snow_fill, label: 'Snow showers');
  }
  return (icon: CupertinoIcons.cloud_bolt_rain_fill, label: 'Thunderstorms');
}

/// The forecast for an event's day, on the event's page.
///
/// Shows nothing at all when there is nothing worth showing — no
/// coordinates, no date, a date too far out to forecast, or a request that
/// failed. A weather card that says "unavailable" is furniture telling you
/// it is broken; an absent one costs the reader nothing.
///
/// Meets are outdoors, and people drive an hour to reach one. Knowing on
/// Thursday that Saturday is washed out is the difference between changing
/// plans and wasting a morning.
class EventWeather extends StatefulWidget {
  final double? latitude;
  final double? longitude;

  /// The day the event starts.
  final DateTime? date;

  const EventWeather({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.date,
  });

  @override
  State<EventWeather> createState() => _EventWeatherState();
}

class _EventWeatherState extends State<EventWeather> {
  static const Color _ink = Color(0xFF111111);
  static const Color _muted = Color(0xFF8A8A8E);
  static const Color _gold = Color(0xFFAE9159);

  DayForecast? _forecast;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EventWeather old) {
    super.didUpdateWidget(old);

    // The full event arrives after the page is first built, so the
    // coordinates and the date can turn up later than this widget does.
    if (old.latitude != widget.latitude ||
        old.longitude != widget.longitude ||
        old.date != widget.date) {
      _load();
    }
  }

  Future<void> _load() async {
    final lat = widget.latitude;
    final lng = widget.longitude;
    final date = widget.date;

    if (lat == null || lng == null || date == null) {
      if (mounted) setState(() => _done = true);
      return;
    }

    final forecast = await WeatherApi.forDay(
      latitude: lat,
      longitude: lng,
      date: date,
    );

    if (!mounted) return;
    setState(() {
      _forecast = forecast;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final forecast = _forecast;

    // Nothing while it loads, rather than a placeholder that shifts the
    // page when it resolves into nothing.
    if (!_done || forecast == null) return const SizedBox.shrink();

    final weather = describeWeather(forecast.code);

    // No horizontal margin: the event page already pads this column, and a
    // widget that insets itself as well can only ever be right on the one
    // screen it was written against.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: forecast.isRough
            ? const Color(0xFFFFF6E8)
            : const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: forecast.isRough
              ? const Color(0xFFF0DCBC)
              : const Color(0xFFEDEDED),
        ),
      ),
      child: Row(
        children: [
          Icon(weather.icon, size: 30, color: forecast.isRough ? _gold : _ink),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${weather.label} · ${forecast.high.round()}°',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _detail(forecast),
                  style: const TextStyle(fontSize: 13.5, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The line under the headline.
  ///
  /// Leads with whatever would change someone's plans. Rain and wind are
  /// the two that do, so they come first when they are worth saying and are
  /// left out entirely when they are not — a dry, still day does not need
  /// telling you it is 5% likely to rain.
  String _detail(DayForecast f) {
    final parts = <String>[];

    if (f.rainChance >= 20) parts.add('${f.rainChance}% chance of rain');
    if (f.windMph >= 20) parts.add('wind ${f.windMph.round()} mph');

    parts.add('low ${f.low.round()}°');

    final line = parts.join(' · ');
    return '${line[0].toUpperCase()}${line.substring(1)}';
  }
}
