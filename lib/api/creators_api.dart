import 'dart:convert';

import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/models/creator.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The YouTube channels DriveLife features.
///
/// ── ONE WRITE, AND IT IS NOT AN ADMIN ONE ───────────────────────────
///
/// Adding a creator, featuring one, flagging the podcast and deleting
/// are done in the data admin tool - see
/// tools/dataadmin-app/dl-watch-admin.php. The REST write endpoints
/// for those still exist and are still admin-gated; nothing here calls
/// them.
///
/// Following is the exception, because it belongs to the person using
/// the app rather than to whoever runs it.
///
/// ── NO SAMPLE FALLBACK ──────────────────────────────────────────────
///
/// VideosAPI stands in with sample data when its endpoint is missing,
/// because that screen had to be looked at before the server existed.
/// This one does the opposite: a failure returns an empty list and the
/// Favourite Creators row hides itself.
///
/// The difference is that an empty creators row is a correct and
/// likely state - a fresh installation has none - whereas invented
/// creators would be invented PEOPLE, with names and faces, which is
/// not something to put on a screen and hope somebody notices is fake.
class CreatorsAPI {
  CreatorsAPI._();

  static String get _base => '${ApiConfig.baseUrl}/wp-json/app/v2';
  static final AuthService _auth = AuthService();

  /// Follows or unfollows. Any signed-in person.
  ///
  /// Explicit rather than a toggle, so two taps racing each other
  /// cannot land on the opposite of what was last on screen.
  ///
  /// Returns whether it worked. The caller has already redrawn
  /// optimistically and puts it back if this is false.
  static Future<bool> setFollowing(int creatorId, bool following) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/creators/$creatorId/follow'),
            headers: await _headers(),
            body: jsonEncode({'follow': following}),
          )
          .timeout(ApiConfig.requestTimeout);

      final body = jsonDecode(response.body);

      return response.statusCode == 200 &&
          body is Map &&
          body['success'] == true;
    } catch (e) {
      debugPrint('[creators] follow failed: $e');

      return false;
    }
  }

  static Future<Map<String, String>> _headers() async {
    final token = await _auth.getToken();

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// The creators, in the order somebody put them in.
  ///
  /// [featured] narrows it to the Favourite Creators row.
  /// [featured] is the editorial list alone. [home] is that list PLUS
  /// whoever this person follows, with the followed ones first - which
  /// is what the Favourite Creators row wants.
  static Future<List<Creator>> list({
    int limit = 20,
    bool featured = false,
    bool home = false,
    String? search,
  }) async {
    final term = search?.trim() ?? '';

    final uri = Uri.parse('$_base/creators').replace(
      queryParameters: {
        'limit': '$limit',
        if (featured) 'featured': '1',
        if (home) 'home': '1',
        if (term.isNotEmpty) 'search': term,
      },
    );

    try {
      final response = await http
          .get(uri, headers: await _headers())
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 200) {
        debugPrint('[creators] HTTP ${response.statusCode}');

        return const [];
      }

      final body = jsonDecode(response.body);

      if (body is! Map || body['data'] is! List) return const [];

      return (body['data'] as List)
          .whereType<Map>()
          .map((row) => Creator.fromJson(Map<String, dynamic>.from(row)))
          // A creator with no name is a row nothing can be drawn
          // for. The server already drops these; this is the belt to
          // its braces.
          .where((creator) => creator.name.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[creators] list failed: $e');

      return const [];
    }
  }
}
