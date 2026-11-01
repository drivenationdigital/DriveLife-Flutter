import 'dart:convert';

import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/models/group_content.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The two group tabs a club did not already have.
///
/// Clubs serve Latest and Events through their existing endpoints;
/// these fill in Garages and Spots. Both are DERIVED, not stored:
///
///   Garages  vehicles owned by the club's current members
///   Spots    posts made to the club that carry a spotted vehicle
///
/// Nothing is written anywhere to produce them — they are a join over
/// data that already exists, computed per request. So a car is in a
/// club's garage because its owner is a member today, and leaves with
/// them; there is no relationship to keep in step and nothing to
/// migrate if the rule changes.
///
/// The payloads match the global group endpoints field for field,
/// which is why this returns the same [GroupVehicle] and [GroupSpot]
/// the group screen uses.
class ClubTabsApi {
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

  /// Vehicles owned by the club's members.
  static Future<List<GroupVehicle>> fetchGarages(
    int clubId, {
    int page = 1,
    int perPage = 24,
  }) async {
    final raw = await _list(
      'club/$clubId/garages',
      'vehicles',
      page: page,
      perPage: perPage,
    );

    return raw.map(GroupVehicle.fromJson).toList();
  }

  /// Spot posts made to the club.
  static Future<List<GroupSpot>> fetchSpots(
    int clubId, {
    int page = 1,
    int perPage = 30,
  }) async {
    final raw = await _list(
      'club/$clubId/spots',
      'spots',
      page: page,
      perPage: perPage,
    );

    return raw.map(GroupSpot.fromJson).toList();
  }

  /// The numbers on the tab bar, in one request rather than two.
  static Future<ClubTabCounts> fetchCounts(int clubId) async {
    try {
      final response = await http.get(
        _uri('club/$clubId/tab-counts'),
        headers: await _headers(),
      );

      if (response.statusCode != 200) return const ClubTabCounts();

      final body = json.decode(response.body);

      if (body is! Map || body['success'] != true) {
        return const ClubTabCounts();
      }

      final counts = body['counts'];

      if (counts is! Map) return const ClubTabCounts();

      return ClubTabCounts(
        garages: (counts['garages'] as num?)?.toInt() ?? 0,
        spots: (counts['spots'] as num?)?.toInt() ?? 0,
        members: (counts['members'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('[ClubTabs] counts error: $e');
      return const ClubTabCounts();
    }
  }

  /// Returns an empty list on any failure, logging the reason: a tab
  /// that cannot load should show its empty state, not an exception.
  static Future<List<Map<String, dynamic>>> _list(
    String path,
    String key, {
    int page = 1,
    int perPage = 24,
  }) async {
    try {
      final response = await http.get(
        _uri(path, {'page': '$page', 'per_page': '$perPage'}),
        headers: await _headers(),
      );

      if (response.statusCode != 200) {
        debugPrint('[ClubTabs] $path failed: ${response.statusCode}');
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
      debugPrint('[ClubTabs] $path error: $e');
      return const [];
    }
  }
}

class ClubTabCounts {
  final int garages;
  final int spots;
  final int members;

  const ClubTabCounts({this.garages = 0, this.spots = 0, this.members = 0});
}
