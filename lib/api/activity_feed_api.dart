import 'dart:convert';

import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/models/activity_item.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The Activity tab's two calls.
///
///   GET  app/v2/activity/feed      what we think you would like
///   POST app/v2/activity/respond   what you did with it
///
/// Administrators only, and enforced on the server — the tab is hidden
/// from everybody else, but a hidden tab is not a closed door, so
/// [fetchFeed] can legitimately come back 403 and that is not an error
/// worth showing anybody.
///
/// This is a temporary feature being tested against real data: does
/// matching somebody's interests against the activity log produce
/// something worth showing? See docs/user-interest-signals.md.
class ActivityFeedApi {
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
      '${ApiConfig.baseUrl}/wp-json/app/v2/$path',
    ).replace(queryParameters: query);
  }

  /// What we think this person would like to see.
  ///
  /// Returns null when the call could not be made or we are not allowed
  /// to make it — distinct from an empty feed, which is a real answer
  /// with a [ActivityFeed.reason] explaining itself. The tab shows
  /// nothing at all for a null and an explanation for an empty.
  ///
  /// [fresh] asks the server to skip anything already shown to this
  /// person. An ordinary load does not, because a feed that dropped
  /// everything it had just shown comes back empty on the next
  /// pull-to-refresh — so a fresh call is the only way to get DIFFERENT
  /// cards, and it can legitimately come back empty where a normal one
  /// would not.
  static Future<ActivityFeed?> fetchFeed({
    int limit = 20,
    bool fresh = false,
  }) async {
    try {
      final response = await http.get(
        _uri('activity/feed', {
          'limit': '$limit',
          if (fresh) 'fresh': '1',
        }),
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        // 403 is the ordinary answer for a non-admin and not worth a
        // noisy log; anything else is worth seeing while this is new.
        if (response.statusCode != 403) {
          debugPrint(
            'ActivityFeedApi.fetchFeed: ${response.statusCode} '
            '${response.body}',
          );
        }

        return null;
      }

      final body = jsonDecode(response.body);

      if (body is! Map || body['success'] != true) {
        return null;
      }

      final items = (body['items'] as List? ?? [])
          .whereType<Map>()
          .map((raw) => ActivityItem.fromJson(Map<String, dynamic>.from(raw)))
          .toList();

      final interests = (body['interests'] as List? ?? [])
          .whereType<Map>()
          .map(
            (raw) => ActivityInterest.fromJson(Map<String, dynamic>.from(raw)),
          )
          .toList();

      return ActivityFeed(
        items: items,
        interests: interests,
        reason: body['reason']?.toString(),
      );
    } catch (error) {
      debugPrint('ActivityFeedApi.fetchFeed failed: $error');

      return null;
    }
  }

  /// How many suggestions are waiting, for the badge on the tab.
  ///
  /// `count_only` is a separate path on the server, not `limit=1`: the
  /// ordinary feed call RECORDS a delivery for everything it returns,
  /// so counting that way would mark items as shown to somebody who has
  /// not opened the tab — and the badge would quietly consume the thing
  /// it was advertising.
  ///
  /// Returns 0 on any failure, including the 403 a non-admin gets. A
  /// badge is not worth an error.
  static Future<int> pendingCount() async {
    try {
      final response = await http.get(
        _uri('activity/feed', {'count_only': '1'}),
        headers: await _headers(),
      );

      if (response.statusCode != 200) return 0;

      final body = jsonDecode(response.body);

      if (body is! Map || body['success'] != true) return 0;

      final count = body['count'];

      return count is int ? count : int.tryParse('$count') ?? 0;
    } catch (error) {
      debugPrint('ActivityFeedApi.pendingCount failed: $error');

      return 0;
    }
  }

  /// Groups, events and venues suggested off the back of one activity.
  ///
  /// Fetched when somebody taps Interested — they have just said they
  /// like a particular car, and this is what else follows from that.
  ///
  /// Read-only on the server: nothing is recorded until one of them is
  /// tapped. Returns null on any failure, which the card shows as a
  /// retry rather than as "there is nothing".
  static Future<ActivityRelatedSet?> fetchRelated(
    int activityId, {
    int limit = 5,
  }) async {
    try {
      final response = await http.get(
        _uri('activity/related', {
          'activity_id': '$activityId',
          'limit': '$limit',
        }),
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'ActivityFeedApi.fetchRelated: ${response.statusCode} '
          '${response.body}',
        );

        return null;
      }

      final body = jsonDecode(response.body);

      if (body is! Map || body['success'] != true) {
        return null;
      }

      return ActivityRelatedSet(
        items: (body['items'] as List? ?? [])
            .whereType<Map>()
            .map(
              (raw) => ActivityRelated.fromJson(Map<String, dynamic>.from(raw)),
            )
            .toList(),
        make: (body['make'] ?? '').toString(),
        located: body['located'] != false,
      );
    } catch (error) {
      debugPrint('ActivityFeedApi.fetchRelated failed: $error');

      return null;
    }
  }

  /// Record what the viewer did with an item.
  ///
  /// `not_interested` and `hidden` also take it out of their feed from
  /// then on — the server excludes anything already responded to, so a
  /// button saying "not interested" is not contradicted next time the
  /// tab is opened.
  ///
  /// Returns true when it was recorded. A false is worth knowing about
  /// at the call site only to the extent of not pretending the tap
  /// landed; it is never worth an error dialog over a feed.
  static Future<bool> respond({
    required int activityId,
    required String response,
  }) async {
    try {
      final result = await http.post(
        _uri('activity/respond'),
        headers: await _headers(),
        body: jsonEncode({
          'activity_id': activityId,
          'response': response,
          'surface': 'activity_tab',
        }),
      );

      if (result.statusCode != 200) {
        debugPrint(
          'ActivityFeedApi.respond: ${result.statusCode} ${result.body}',
        );

        return false;
      }

      final body = jsonDecode(result.body);

      return body is Map && body['success'] == true;
    } catch (error) {
      debugPrint('ActivityFeedApi.respond failed: $error');

      return false;
    }
  }
}
