import 'dart:async';
import 'dart:convert';

import 'package:drivelife/config/mapbox_config.dart';
import 'package:drivelife/models/driving_road.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One place somebody can search for.
class PlaceHit {
  /// What to show: "Helmsley, North Yorkshire, England".
  final String label;

  /// The first line of it, bolder in the list: "Helmsley".
  final String name;

  final RoadPoint point;

  const PlaceHit({
    required this.label,
    required this.name,
    required this.point,
  });

  /// Everything after the name, or empty.
  String get detail {
    final rest = label.startsWith('$name, ')
        ? label.substring(name.length + 2)
        : '';

    return rest;
  }
}

/// Finding a place on the map by name.
///
/// ── WHY THIS EXISTS ─────────────────────────────────────────────────
///
/// Drawing a road starts with getting the map to the road, and the only
/// way to do that was to pan. The map opens on wherever the phone last
/// was, so a road two counties away is a long drag at a zoom where you
/// cannot tell one lane from the next — and zooming out to travel means
/// arriving somewhere you then have to zoom back into.
///
/// ── WHAT IT DOES NOT DO ─────────────────────────────────────────────
///
/// Place a point. A geocoder answers with the middle of a town, and the
/// start of a road is not the middle of a town — dropping a point there
/// would be a wrong answer that looks like a right one. It moves the
/// camera and leaves the tapping to the person who knows where the road
/// actually begins.
abstract final class PlaceSearch {
  const PlaceSearch._();

  /// Mapbox's forward geocoder, which the map's own token already pays
  /// for. No second account, no second key to rotate.
  static const String _base =
      'https://api.mapbox.com/geocoding/v5/mapbox.places';

  /// Short enough to feel instant, long enough that typing a town name
  /// is one request rather than eight.
  static const Duration debounce = Duration(milliseconds: 350);

  /// Whether a stored country is one a geocoder can filter on.
  ///
  /// ── WHY THIS IS CHECKED AND NOT TRUSTED ─────────────────────────
  ///
  /// `last_location.country` is a real ISO code on anything written
  /// recently, and is NOT on older rows: it used to be written as
  /// 'non-UK' for anywhere outside Britain, which is not a country and
  /// which Mapbox would reject — taking the whole search down with it
  /// rather than just the filter.
  ///
  /// Two letters is the whole of the rule. 'GB' passes, 'non-UK'
  /// fails, '' fails, and a failure means an unfiltered search rather
  /// than no search.
  @visibleForTesting
  static bool usableCountry(String? code) {
    final text = (code ?? '').trim();

    return text.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(text);
  }

  /// Places matching [query], nearest to [near] first.
  ///
  /// [country] is an ISO 3166-1 alpha-2 code, and the results are held
  /// to it.
  ///
  /// ── WHY A COUNTRY AND NOT JUST PROXIMITY ────────────────────────
  ///
  /// Proximity only sorts. A search for "Richmond" from Yorkshire
  /// still returns Virginia, two rows down, looking exactly as
  /// legitimate as the one eight miles away — and picking it drops a
  /// point on the wrong continent, which the map then flies to.
  ///
  /// Roads are added where somebody drives, so the country is a real
  /// constraint rather than a preference. Null or unusable leaves the
  /// search worldwide, which is the right failure: somebody whose
  /// country we do not know should still be able to find a road.
  ///
  /// Returns an empty list for anything that goes wrong. A search box
  /// that shows nothing is a search box that found nothing, which is
  /// the honest reading of a failure here and is survivable — the map
  /// is still there to pan.
  static Future<List<PlaceHit>> find(
    String query, {
    RoadPoint? near,
    String? country,
  }) async {
    final text = query.trim();

    // Two characters match most of the country. The request would
    // succeed and the list would be noise.
    if (text.length < 3 || !MapboxConfig.isConfigured) return const [];

    try {
      final uri = Uri.parse(
        '$_base/${Uri.encodeComponent(text)}.json',
      ).replace(
        queryParameters: {
          'access_token': MapboxConfig.token,
          'limit': '5',
          // Roads are found by the place they are near, so towns and
          // landmarks matter more than house numbers here.
          'types': 'place,locality,neighborhood,poi,address,region',
          // Biases results towards the map, so "Newport" finds the one
          // up the road before the one in Rhode Island.
          if (near != null && near.isReal)
            'proximity': '${near.lng},${near.lat}',

          // And this rules the other one out entirely. Lowercase
          // because Mapbox documents the parameter that way, though it
          // accepts either.
          if (usableCountry(country)) 'country': country!.trim().toLowerCase(),
        },
      );

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[PlaceSearch] ${response.statusCode} for "$text"');

        return const [];
      }

      return parse(response.body);
    } catch (e) {
      debugPrint('[PlaceSearch] threw: $e');

      return const [];
    }
  }

  /// What is at a point, or null.
  ///
  /// ── WHY A TAPPED POINT GETS A NAME NOW ──────────────────────────
  ///
  /// It did not, and the list read "Dropped pin" for every point
  /// somebody had placed by hand. Seven of those is not a route
  /// anybody can check, and it survived being saved — a road reopened
  /// for editing listed nothing but dropped pins however carefully it
  /// had been drawn.
  ///
  /// One request per tap, which is the cost of the list being
  /// readable. It runs AFTER the point is placed and fills the name in
  /// when it lands, so nothing waits on it and a failure leaves the
  /// point exactly where it was with the name it already had.
  ///
  /// `address` first: on a road, the useful answer is the road, not
  /// the town it is near.
  static Future<PlaceHit?> describe(RoadPoint point, {String? country}) async {
    if (!point.isReal || !MapboxConfig.isConfigured) return null;

    try {
      final uri = Uri.parse(
        '$_base/${point.lng},${point.lat}.json',
      ).replace(
        queryParameters: {
          'access_token': MapboxConfig.token,
          'limit': '1',
          'types': 'address,poi,neighborhood,locality,place',
          if (usableCountry(country))
            'country': country!.trim().toLowerCase(),
        },
      );

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final hits = parse(response.body);

      return hits.isEmpty ? null : hits.first;
    } catch (e) {
      debugPrint('[PlaceSearch] describe threw: $e');

      return null;
    }
  }

  /// The hits in a geocoder response.
  ///
  /// Separate from the request so it can be tested without a network
  /// and without a token, and because every way this can go wrong is a
  /// content problem rather than an IO one.
  ///
  /// NOTE THE ORDER. GeoJSON writes `center` as [longitude, latitude],
  /// the opposite way round from every other coordinate in this app.
  /// Read in the order they are written, a search for Helmsley lands
  /// off the coast of Somalia.
  @visibleForTesting
  static List<PlaceHit> parse(String body) {
    final Object? decoded;

    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const [];
    }

    if (decoded is! Map) return const [];

    final features = decoded['features'];

    if (features is! List) return const [];

    final out = <PlaceHit>[];

    for (final feature in features) {
      if (feature is! Map) continue;

      final centre = feature['center'];

      if (centre is! List || centre.length < 2) continue;

      final lng = _double(centre[0]);
      final lat = _double(centre[1]);

      if (lng == null || lat == null) continue;

      final point = RoadPoint(lat, lng);

      // isReal refuses 0,0 and anything past the poles, which is the
      // same guard the rest of the roads code uses.
      if (!point.isReal || lat.abs() > 90 || lng.abs() > 180) continue;

      final label = '${feature['place_name'] ?? ''}'.trim();
      final name = '${feature['text'] ?? ''}'.trim();

      if (label.isEmpty && name.isEmpty) continue;

      out.add(
        PlaceHit(
          label: label.isEmpty ? name : label,
          name: name.isEmpty ? label : name,
          point: point,
        ),
      );
    }

    return out;
  }

  static double? _double(dynamic value) {
    if (value is num) return value.toDouble();

    return double.tryParse('$value');
  }
}
