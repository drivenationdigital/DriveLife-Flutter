import 'dart:convert';

import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/models/group_content.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Global groups — scene, marque and model.
///
/// These are NOT clubs. A club is a WordPress post on one regional
/// blog; a global group is a row in `ce_groups` with no blog and no
/// geography, visible to every user everywhere. They are served from
/// their own endpoints and have their own id space, which is why
/// [GlobalGroup.type] exists: group 42 and club 42 are different
/// things, and a bare id cannot tell you which you are holding.
///
/// Read only. There is no join, leave or post here — membership is a
/// later step, and nothing in this file can change anything.
///
/// See docs/global-groups-design.md.
class GlobalGroupsApi {
  static final AuthService _authService = AuthService();

  static Future<Map<String, String>> _headers() async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final token = await _authService.getToken();

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  static Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse(
      '${ApiConfig.baseUrl}/wp-json/app/v1/$path',
    ).replace(queryParameters: query);
  }

  /// Groups of one or more kinds.
  ///
  /// [kinds] is sent as a comma-separated list because the app's
  /// "Marque & model" section is two kinds in one list and should not
  /// cost two round trips.
  ///
  /// Returns an empty list rather than throwing: a section that fails
  /// to load should disappear, not take the page down with it.
  static Future<List<GlobalGroup>> fetchGroups({
    List<String> kinds = const [],
    String? search,
    bool mine = false,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final query = <String, String>{
        'page': '$page',
        'per_page': '$perPage',
        if (kinds.isNotEmpty) 'kind': kinds.join(','),
        // Only groups this person has joined. Used by YOUR GROUPS,
        // which otherwise shows clubs alone and silently omits every
        // global group somebody has joined.
        if (mine) 'mine': '1',
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      };

      final response = await http.get(
        _uri('groups', query),
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        debugPrint('[GlobalGroups] list failed: ${response.statusCode}');
        return const [];
      }

      final body = json.decode(response.body);

      if (body is! Map || body['success'] != true) {
        return const [];
      }

      final raw = body['groups'];

      if (raw is! List) return const [];

      return raw
          .whereType<Map>()
          .map((e) => GlobalGroup.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[GlobalGroups] list error: $e');
      return const [];
    }
  }

  /// One group, by slug.
  ///
  /// By slug and not by id, deliberately: a bare number is ambiguous
  /// between a group and a club, and a slug is not.
  static Future<GlobalGroup?> fetchGroup(String slug) async {
    try {
      final response = await http.get(
        _uri('groups/$slug'),
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        debugPrint('[GlobalGroups] detail failed: ${response.statusCode}');
        return null;
      }

      final body = json.decode(response.body);

      if (body is! Map || body['success'] != true || body['group'] is! Map) {
        return null;
      }

      return GlobalGroup.fromJson(Map<String, dynamic>.from(body['group']));
    } catch (e) {
      debugPrint('[GlobalGroups] detail error: $e');
      return null;
    }
  }

  /// The vehicles matched into a group.
  ///
  /// Empty until dl-global-groups-refresh.php has run — an empty list
  /// means the refresh has not happened, not that nothing matches.
  static Future<List<GlobalGroupVehicle>> fetchVehicles(
    String slug, {
    int page = 1,
    int perPage = 24,
  }) async {
    try {
      final response = await http.get(
        _uri('groups/$slug/vehicles', {
          'page': '$page',
          'per_page': '$perPage',
        }),
        headers: await _headers(),
      );

      if (response.statusCode != 200) return const [];

      final body = json.decode(response.body);

      if (body is! Map || body['success'] != true) return const [];

      final raw = body['vehicles'];

      if (raw is! List) return const [];

      return raw
          .whereType<Map>()
          .map((e) => GlobalGroupVehicle.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[GlobalGroups] vehicles error: $e');
      return const [];
    }
  }

  /// The Latest feed: posts and spots, newest first.
  ///
  /// Returns RAW POST MAPS, not a model, because the screen renders
  /// them with the same PostCard a club feed uses — and that widget
  /// takes the server's row as a Map rather than a typed object. The
  /// endpoint sends the club shape for exactly this reason.
  ///
  /// Reads the activity index, so it is empty until the refresh pass
  /// has run — except for posts made directly to the group, which are
  /// indexed as they are created.
  static Future<List<Map<String, dynamic>>> fetchActivity(
    String slug, {
    int page = 1,
    int perPage = 15,
  }) async {
    // 'data', the same key the club feed uses.
    return _list('groups/$slug/activity', 'data', page: page, perPage: perPage);
  }

  /// The Spots grid.
  static Future<List<GlobalGroupSpot>> fetchSpots(
    String slug, {
    int page = 1,
    int perPage = 30,
  }) async {
    final raw = await _list(
      'groups/$slug/spots',
      'spots',
      page: page,
      perPage: perPage,
    );

    return raw.map(GlobalGroupSpot.fromJson).toList();
  }

  /// The Events tab.
  ///
  /// Always empty today: nothing relates an event to a global group —
  /// no column, no link table, no rule. The endpoint exists so this
  /// tab is wired like its three neighbours rather than being a
  /// special case, and so there is one place to change when that
  /// relationship is designed.
  static Future<List<GlobalGroupEvent>> fetchEvents(String slug) async {
    final raw = await _list('groups/$slug/events', 'events');
    return raw.map(GlobalGroupEvent.fromJson).toList();
  }

  /// "Based on your garage" — groups whose rules match a car this
  /// person owns.
  ///
  /// Suggestions only. Nothing is joined by fetching these, and a
  /// group the user has already left is never suggested again.
  static Future<List<GlobalGroup>> fetchSuggested({int limit = 5}) async {
    try {
      final response = await http.get(
        _uri('groups/suggested', {'limit': '$limit'}),
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        debugPrint('[GlobalGroups] suggested failed: ${response.statusCode}');
        return const [];
      }

      final body = json.decode(response.body);

      if (body is! Map || body['success'] != true) return const [];

      final raw = body['suggestions'];

      if (raw is! List) return const [];

      return raw
          .whereType<Map>()
          .map((e) => GlobalGroup.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[GlobalGroups] suggested error: $e');
      return const [];
    }
  }

  /// Join a group. Returns true only if the server confirmed it.
  ///
  /// The caller needs the real answer rather than a fire-and-forget,
  /// because the button has to go back to "Join" if this failed —
  /// showing "Joined" for a membership that does not exist is the one
  /// outcome worth avoiding.
  static Future<bool> join(String slug) => _membership(slug, 'join');

  /// Leave a group. The server keeps a tombstone, so the group will
  /// not come back as a suggestion afterwards.
  static Future<bool> leave(String slug) => _membership(slug, 'leave');

  static Future<bool> _membership(String slug, String action) async {
    try {
      final response = await http.post(
        _uri('groups/$slug/$action'),
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        debugPrint('[GlobalGroups] $action failed: ${response.statusCode}');
        return false;
      }

      final body = json.decode(response.body);

      return body is Map && body['success'] == true;
    } catch (e) {
      debugPrint('[GlobalGroups] $action error: $e');
      return false;
    }
  }

  /// Shared plumbing for the paged list endpoints.
  ///
  /// Returns an empty list on any failure, logging the reason: a tab
  /// that cannot load should show its empty state, not an exception.
  static Future<List<Map<String, dynamic>>> _list(
    String path,
    String key, {
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final response = await http.get(
        _uri(path, {'page': '$page', 'per_page': '$perPage'}),
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        debugPrint('[GlobalGroups] $path failed: ${response.statusCode}');
        return const [];
      }

      final body = json.decode(response.body);

      if (body is! Map || body['success'] != true) return const [];

      final raw = body[key];

      if (raw is! List) return const [];

      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('[GlobalGroups] $path error: $e');
      return const [];
    }
  }
}

/// A global group as the API returns it.
class GlobalGroup {
  final int id;
  final String slug;
  final String kind;
  final String title;
  final String? strapline;
  final String? description;
  final String? coverImage;
  final String? logo;
  final int memberCount;
  final int vehicleCount;
  final bool isFeatured;
  final bool isMember;

  /// draft | published | hidden.
  ///
  /// Exposed so the app can show a badge while testing. Every group is
  /// a draft today, and the endpoint is deliberately returning drafts —
  /// if this were hidden, a test build would look identical to a live
  /// one and the difference is the whole point.
  final String status;

  /// What the group matches on, for the detail screen.
  final List<GlobalGroupRule> rules;

  /// Why this group was suggested: "Because of your Mazda MX-5".
  ///
  /// Only set on /groups/suggested. A recommendation that explains
  /// itself is one somebody can disagree with, which is the whole
  /// difference between a suggestion and a guess.
  final String? reason;

  /// The tab-bar numbers, sent with the detail so the tabs render with
  /// their counts on the first frame rather than four requests deep.
  final int latestCount;
  final int garageCount;
  final int spotCount;
  final int eventCount;

  const GlobalGroup({
    required this.id,
    required this.slug,
    required this.kind,
    required this.title,
    this.strapline,
    this.description,
    this.coverImage,
    this.logo,
    this.memberCount = 0,
    this.vehicleCount = 0,
    this.isFeatured = false,
    this.isMember = false,
    this.status = 'draft',
    this.rules = const [],
    this.reason,
    this.latestCount = 0,
    this.garageCount = 0,
    this.spotCount = 0,
    this.eventCount = 0,
  });

  String? get image => coverImage ?? logo;

  factory GlobalGroup.fromJson(Map<String, dynamic> json) {
    final rawRules = json['rules'];

    // Only the detail endpoint sends counts; the list leaves them out
    // to stay cheap, so a summary falls back to zero.
    final counts = json['counts'] is Map
        ? Map<String, dynamic>.from(json['counts'] as Map)
        : const <String, dynamic>{};

    int count(String key) => (counts[key] as num?)?.toInt() ?? 0;

    return GlobalGroup(
      reason: json['reason'] as String?,
      latestCount: count('latest'),
      garageCount: count('garages'),
      spotCount: count('spots'),
      eventCount: count('events'),
      id: (json['ID'] as num?)?.toInt() ?? 0,
      slug: json['slug'] as String? ?? '',
      kind: json['kind'] as String? ?? 'scene',
      title: json['title'] as String? ?? '',
      strapline: json['strapline'] as String?,
      description: json['description'] as String?,
      coverImage: json['cover_image'] as String?,
      logo: json['logo'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      vehicleCount: (json['vehicle_count'] as num?)?.toInt() ?? 0,
      isFeatured: json['is_featured'] == true,
      isMember: json['is_member'] == true,
      status: json['status'] as String? ?? 'draft',
      rules: rawRules is List
          ? rawRules
                .whereType<Map>()
                .map(
                  (e) => GlobalGroupRule.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
    );
  }
}

/// One clause of what belongs in a group.
class GlobalGroupRule {
  final String type;
  final String value;
  final String? valueTo;

  const GlobalGroupRule({
    required this.type,
    required this.value,
    this.valueTo,
  });

  factory GlobalGroupRule.fromJson(Map<String, dynamic> json) =>
      GlobalGroupRule(
        type: json['type'] as String? ?? '',
        value: json['value'] as String? ?? '',
        valueTo: json['value_to'] as String?,
      );

  /// "Make is Mazda", "Year 1900–1989".
  String get label {
    switch (type) {
      case 'make':
        return 'Make is $value';
      case 'model':
        return 'Model is $value';
      case 'variant':
        return 'Variant is $value';
      case 'keyword':
        return 'Mentions "$value"';
      case 'year_range':
        return valueTo == null ? 'Year $value' : 'Year $value–$valueTo';
      default:
        return '$type $value';
    }
  }
}

// ─── Shared content shapes ───────────────────────────────────────────
//
// These live in models/group_content.dart because CLUBS return the same
// shapes from different queries — a global group matches vehicles by
// rule, a club takes its members' — and the app should not have two
// models for one payload.
//
// Kept as aliases rather than renamed at every call site: the old names
// read perfectly well here, and a rename would touch files that have
// nothing else to do with this change.

typedef GlobalGroupUser = GroupUser;
typedef GlobalGroupPost = GroupPost;
typedef GlobalGroupSpot = GroupSpot;
typedef GlobalGroupEvent = GroupEvent;
typedef GlobalGroupVehicle = GroupVehicle;
