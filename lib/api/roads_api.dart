import 'dart:convert';

import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One page of roads, and whether there is another.
class RoadPage {
  final List<DrivingRoad> roads;

  /// Whether asking again with a bigger offset would return anything.
  ///
  /// Taken from the server rather than guessed from the page being
  /// full: a page that happens to end exactly on the last road is
  /// indistinguishable from one with more behind it, and guessing
  /// gives an infinite list one empty fetch at the bottom every time.
  final bool hasMore;

  const RoadPage({this.roads = const [], this.hasMore = false});

  bool get isEmpty => roads.isEmpty;
}

/// How a list of roads is ordered.
enum RoadSort {
  nearest('nearest', 'Nearest'),
  newest('new', 'Newest'),
  popular('popular', 'Most driven'),
  longest('longest', 'Longest'),
  shortest('shortest', 'Shortest');

  const RoadSort(this.code, this.label);

  /// What the server calls it.
  final String code;

  /// What a person calls it.
  final String label;
}

/// What a press of "I drove this" or "Save" came back with.
class RoadActionResult {
  /// How many people, recalculated from the rows rather than
  /// incremented — so it cannot drift away from the truth.
  final int count;

  final int vehicleId;
  final String droveOn;

  const RoadActionResult({
    required this.count,
    this.vehicleId = 0,
    this.droveOn = '',
  });
}

/// Driving roads.
///
/// ── EVERY CALL CAN COME BACK "NOT READY" ────────────────────────────
///
/// The server file ships dark: it registers no route unless
/// DL_ROADS_ENABLED is set, and answers 503 until its tables exist. So
/// a build pointed at a server without either gets a 404 or a 503 from
/// every call here, and both mean the same thing — roads are not on.
///
/// That is a normal answer rather than a failure, and [lastReady] is
/// how a screen tells it apart from a road that simply has no
/// neighbours. Nothing here throws, and nothing here shows an error for
/// a feature that is switched off.
class RoadsAPI {
  static final AuthService _auth = AuthService();

  static String get _base => AppEnvironment.wordpressBase;

  /// Whether the last call reached a server with roads switched on.
  ///
  /// Starts true so a screen does not flash "unavailable" before it has
  /// asked anything.
  static bool lastReady = true;

  static Future<Map<String, String>?> _headers() async {
    final token = await _auth.getToken();
    if (token == null) return null;

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// A 404 means the routes were never registered; a 503 means they
  /// were, but the tables are not there. Both are "not on".
  static bool _readyFrom(int status) => status != 404 && status != 503;

  /// Roads near a point, nearest first.
  ///
  /// [radius] is in miles and the server caps it. An empty list is a
  /// real answer — most of the country has no roads in this table yet.
  static Future<List<DrivingRoad>> nearby({
    required double lat,
    required double lng,
    double radius = 50,
    int limit = 20,
  }) async {
    return _list(
      Uri.parse('$_base/wp-json/app/v2/roads/nearby').replace(
        queryParameters: {
          'lat': '$lat',
          'lng': '$lng',
          'radius': '$radius',
          'limit': '$limit',
        },
      ),
      'nearby',
    );
  }

  /// One page of roads, filtered and ordered.
  ///
  /// ── ONE ENDPOINT, NOT TWO ───────────────────────────────────────
  ///
  /// Searching, filtering by length, ordering and paging all have to
  /// happen in the same query or they disagree: a radius applied in
  /// the app after a page has been fetched hides some of the twenty
  /// that came back and leaves a short page with no way to ask for
  /// more.
  ///
  /// So [from] goes to the server too. With it, distance is a column
  /// the database sorts and pages by; without it, "nearest" is not on
  /// offer.
  static Future<RoadPage> page({
    RoadPoint? from,
    String query = '',
    double? minMiles,
    double? maxMiles,
    double? withinMiles,
    RoadSort sort = RoadSort.newest,
    String? site,
    int limit = 20,
    int offset = 0,
  }) async {
    final url = Uri.parse('$_base/wp-json/app/v2/roads').replace(
      queryParameters: {
        if (site != null && site.isNotEmpty) 'site': site,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (from != null) 'lat': '${from.lat}',
        if (from != null) 'lng': '${from.lng}',
        if (minMiles != null && minMiles > 0) 'min_miles': '$minMiles',
        if (maxMiles != null && maxMiles > 0) 'max_miles': '$maxMiles',
        if (withinMiles != null && withinMiles > 0)
          'within_miles': '$withinMiles',
        'sort': sort.code,
        'limit': '$limit',
        'offset': '$offset',
      },
    );

    try {
      final headers = await _headers();
      if (headers == null) return const RoadPage();

      final response = await http.get(url, headers: headers);

      lastReady = _readyFrom(response.statusCode);

      if (response.statusCode != 200) return const RoadPage();

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return const RoadPage();

      final rows = body['roads'];
      if (rows is! List) return const RoadPage();

      return RoadPage(
        roads: rows
            .whereType<Map>()
            .map((row) => DrivingRoad.fromMap(Map<String, dynamic>.from(row)))
            .toList(),
        hasMore: body['has_more'] == true,
      );
    } catch (e) {
      debugPrint('[Roads] page threw: $e');
      return const RoadPage();
    }
  }

  /// Every road this person has submitted, whatever became of it.
  ///
  /// The only listing that ignores `status`, so it is the only one
  /// that shows a road still waiting to be checked or one that was
  /// turned down. The owner comes from the token rather than from a
  /// parameter — there is no id to change in a URL and read somebody
  /// else's submissions.
  static Future<List<DrivingRoad>> mine() async {
    return _list(
      Uri.parse('$_base/wp-json/app/v2/roads/mine'),
      'mine',
    );
  }

  /// Every road a vehicle has been down, most recent first.
  ///
  /// Lives in roads.php rather than garage.php on purpose: it is a
  /// roads question with a vehicle in it, and keeping it here is what
  /// lets the whole feature stay one file and two tables.
  ///
  /// An empty list is the normal answer for most cars, and for every
  /// car on a server that has not run roads-drives.sql. The garage
  /// page draws nothing either way.
  static Future<List<DrivingRoad>> forVehicle(int vehicleId) async {
    if (vehicleId < 1) return const [];

    return _list(
      Uri.parse('$_base/wp-json/app/v2/roads/for-vehicle').replace(
        queryParameters: {'vehicle_id': '$vehicleId', 'limit': '20'},
      ),
      'for-vehicle',
    );
  }

  static Future<List<DrivingRoad>> _list(Uri url, String what) async {
    try {
      final headers = await _headers();
      if (headers == null) return const [];

      final response = await http.get(url, headers: headers);

      lastReady = _readyFrom(response.statusCode);

      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return const [];

      final rows = body['roads'];
      if (rows is! List) return const [];

      return rows
          .whereType<Map>()
          .map((row) => DrivingRoad.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    } catch (e) {
      debugPrint('[Roads] $what threw: $e');
      return const [];
    }
  }

  /// One road, with its shape.
  ///
  /// The only call that carries the polyline — see [DrivingRoad.polyline]
  /// for why a list does not.
  static Future<DrivingRoad?> get(int id) async {
    try {
      final headers = await _headers();
      if (headers == null) return null;

      final response = await http.get(
        Uri.parse(
          '$_base/wp-json/app/v2/road',
        ).replace(queryParameters: {'id': '$id'}),
        headers: headers,
      );

      lastReady = _readyFrom(response.statusCode);

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return null;
      if (body['road'] is! Map) return null;

      return DrivingRoad.fromMap(Map<String, dynamic>.from(body['road'] as Map));
    } catch (e) {
      debugPrint('[Roads] get threw: $e');
      return null;
    }
  }

  /// Submits a road.
  ///
  /// It is created as `pending` whatever is sent: this is user-drawn
  /// geography, and some of it will be private land or somebody's
  /// street. Returns the new id, or null with [lastError] set.
  ///
  /// Send EITHER [points] or [polyline]. The server reads them through
  /// two different readers and will not interpret one as the other —
  /// a list that fails to parse is refused rather than decoded into a
  /// coordinate somewhere in the Atlantic.
  static String lastError = '';

  static Future<int?> create({
    required String title,
    List<RoadPoint>? points,
    String? polyline,
    String summary = '',
    String description = '',
    String region = '',
    String country = '',
    String site = '',
    String coverImage = '',
  }) async {
    lastError = '';

    try {
      final headers = await _headers();
      if (headers == null) return null;

      final response = await http.post(
        Uri.parse('$_base/wp-json/app/v2/road'),
        headers: headers,
        body: jsonEncode({
          'title': title,
          if (points != null)
            'points': points.map((p) => [p.lat, p.lng]).toList(),
          if (polyline != null && polyline.isNotEmpty) 'polyline': polyline,
          'summary': summary,
          'description': description,
          'region': region,
          'country': country,
          if (site.isNotEmpty) 'site': site,
          if (coverImage.isNotEmpty) 'cover_image': coverImage,
        }),
      );

      lastReady = _readyFrom(response.statusCode);

      final body = jsonDecode(response.body);

      if (body is Map && body['success'] == true) {
        return DrivingRoad.asInt(body['id']);
      }

      // The server says WHY a road was refused — too short, too long,
      // unnamed — and those are all things the person can fix, so they
      // are worth repeating rather than replacing with "failed".
      if (body is Map && body['message'] != null) {
        lastError = '${body['message']}';
      }

      return null;
    } catch (e) {
      debugPrint('[Roads] create threw: $e');
      return null;
    }
  }

  /// Changes a road this person submitted.
  ///
  /// Every field is optional and an absent one is left alone, so a
  /// screen changing only a title sends only a title.
  ///
  /// [points] is the exception worth knowing: sending it re-routes and
  /// rewrites the whole geometry. A caller that does not mean to
  /// change the route must leave it out rather than send back what it
  /// was given.
  ///
  /// Returns the road as it now stands, or null with [lastError] set.
  static Future<DrivingRoad?> update({
    required int id,
    String? title,
    String? summary,
    String? description,
    String? coverImage,
    List<RoadPoint>? points,
  }) async {
    lastError = '';

    try {
      final headers = await _headers();
      if (headers == null) return null;

      final response = await http.post(
        Uri.parse('$_base/wp-json/app/v2/road/update'),
        headers: headers,
        body: jsonEncode({
          'id': id,
          if (title != null) 'title': title,
          if (summary != null) 'summary': summary,
          if (description != null) 'description': description,
          if (coverImage != null) 'cover_image': coverImage,
          if (points != null)
            'points': points.map((p) => [p.lat, p.lng]).toList(),
        }),
      );

      lastReady = _readyFrom(response.statusCode);

      final body = jsonDecode(response.body);

      if (body is Map && body['success'] == true && body['road'] is Map) {
        return DrivingRoad.fromMap(
          Map<String, dynamic>.from(body['road'] as Map),
        );
      }

      if (body is Map && body['message'] != null) {
        lastError = '${body['message']}';
      }

      return null;
    } catch (e) {
      debugPrint('[Roads] update threw: $e');
      return null;
    }
  }

  /// "I've driven this" / "save".
  ///
  /// Safe to press twice. The server keys on (road, person, kind), so a
  /// second press is still one row — but it UPDATES rather than
  /// ignores, because the second press is often somebody correcting
  /// which car they were in.
  ///
  /// [vehicleId] and [droveOn] are optional and only mean anything for
  /// `drove`. Leaving them out records the tick without the story,
  /// which is what somebody ticking a road off while scrolling wants.
  ///
  /// Returns what the server actually recorded, read back rather than
  /// echoed: on a server that has not run roads-drives.sql the car and
  /// the date come back empty, which is how the screen learns not to
  /// show something it thinks it just saved.
  static Future<RoadActionResult?> setAction({
    required int id,
    required String kind,
    required bool on,
    int vehicleId = 0,
    String droveOn = '',
  }) async {
    final action = kind == 'drove'
        ? (on ? 'drove' : 'undrove')
        : (on ? 'save' : 'unsave');

    try {
      final headers = await _headers();
      if (headers == null) return null;

      final response = await http.post(
        Uri.parse('$_base/wp-json/app/v2/road/action'),
        headers: headers,
        body: jsonEncode({
          'id': id,
          'action': action,
          if (vehicleId > 0) 'vehicle_id': vehicleId,
          if (droveOn.isNotEmpty) 'drove_on': droveOn,
        }),
      );

      lastReady = _readyFrom(response.statusCode);

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return null;

      return RoadActionResult(
        count: DrivingRoad.asInt(body['count']),
        vehicleId: DrivingRoad.asInt(body['vehicle_id']),
        droveOn: DrivingRoad.asText(body['drove_on']),
      );
    } catch (e) {
      debugPrint('[Roads] action threw: $e');
      return null;
    }
  }
}
