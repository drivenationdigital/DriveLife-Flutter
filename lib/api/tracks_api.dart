import 'dart:convert';

import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Tracks & raceways.
///
/// Its own service, not a parameter on the venue one. Sharing them produced
/// two bugs on the first run: the venue endpoint's blog locator only accepted
/// `venues` posts, so every track came back 404, and "My tracks" ran the
/// venue query and listed the user's venues. Both followed from treating a
/// track as a venue with a different label, which it is not — it has its own
/// owner and follower fields, and attaches events differently.
class TracksApiService {
  static final AuthService _auth = AuthService();

  static Future<Map<String, String>?> _headers() async {
    final token = await _auth.getToken();
    if (token == null) return null;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<int?> _userId() async {
    final user = await _auth.getUser();
    final id = user?['id'];
    if (id is int) return id;
    return int.tryParse('$id');
  }

  /// The user's saved country, which decides which site to look at first.
  static Future<String> _country() async {
    final user = await _auth.getUser();
    final last = user?['last_location'];
    if (last is Map && last.isNotEmpty) {
      final country = '${last['country'] ?? ''}'.trim();
      if (country.isNotEmpty) return country;
    }
    return 'GB';
  }

  static Map<String, dynamic>? _decode(http.Response response, String what) {
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    }
    debugPrint('[TracksAPI] $what -> ${response.statusCode}: ${response.body}');
    return null;
  }

  /// Tracks near a point, nearest first.
  ///
  /// [radiusMiles] overrides the radius the server infers from [location];
  /// only the map passes it.
  static Future<Map<String, dynamic>?> getTracks({
    int page = 1,
    int limit = 20,
    String location = 'near-me',
    double? latitude,
    double? longitude,
    String? customLocation,
    int? radiusMiles,
    String? search,
  }) async {
    try {
      final headers = await _headers();
      final userId = await _userId();
      if (headers == null || userId == null) return null;

      final filters = <String, dynamic>{
        'location': [location],
        if (latitude != null && longitude != null)
          'custom_location': {
            'latitude': latitude,
            'longitude': longitude,
            'address': customLocation ?? '',
          },
        if (radiusMiles != null) 'radius_miles': radiusMiles,
      };

      final uri =
          Uri.parse(
            '${ApiConfig.baseUrl}/wp-json/app/v2/get-tracks-trending',
          ).replace(
            queryParameters: {
              'user_id': userId.toString(),
              'page': page.toString(),
              'per_page': limit.toString(),
              'filters': jsonEncode(filters),
              if (search != null && search.trim().isNotEmpty)
                'search': search.trim(),
            },
          );

      return _decode(await http.get(uri, headers: headers), 'getTracks');
    } catch (e) {
      debugPrint('[TracksAPI] getTracks failed: $e');
      return null;
    }
  }

  /// One track, with its contact details and upcoming events.
  static Future<Map<String, dynamic>?> getTrack({
    required String trackId,
    String? country,
  }) async {
    try {
      final headers = await _headers();
      final userId = await _userId();
      if (headers == null || userId == null) return null;

      final uri = Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/get-track')
          .replace(
            queryParameters: {
              'track_id': trackId,
              'user_id': userId.toString(),
              // A hint only. The server checks both sites, because a post id is
              // unique within a blog and the user's country does not say where
              // the track lives.
              'site': country ?? await _country(),
            },
          );

      return _decode(await http.get(uri, headers: headers), 'getTrack');
    } catch (e) {
      debugPrint('[TracksAPI] getTrack failed: $e');
      return null;
    }
  }

  /// Follows or unfollows, and reports the state it settled on.
  ///
  /// Returns the server's `is_following` rather than a bare success, so the
  /// caller never has to assume the toggle landed the way it expected.
  static Future<bool?> toggleFollow({required String trackId}) async {
    try {
      final headers = await _headers();
      final userId = await _userId();
      if (headers == null || userId == null) return null;

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/follow-track'),
        headers: headers,
        body: jsonEncode({
          'track_id': trackId,
          'user_id': userId,
          'site': await _country(),
        }),
      );

      final data = _decode(response, 'toggleFollow');
      return data?['is_following'] as bool?;
    } catch (e) {
      debugPrint('[TracksAPI] toggleFollow failed: $e');
      return null;
    }
  }

  /// The tracks this user owns or follows, across both sites.
  static Future<Map<String, dynamic>?> getMyTracks() async {
    try {
      final headers = await _headers();
      final userId = await _userId();
      if (headers == null || userId == null) return null;

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/my-tracks',
      ).replace(queryParameters: {'user_id': userId.toString()});

      return _decode(await http.get(uri, headers: headers), 'getMyTracks');
    } catch (e) {
      debugPrint('[TracksAPI] getMyTracks failed: $e');
      return null;
    }
  }
}
