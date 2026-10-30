import 'dart:convert';

import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One row of the leaderboard.
class LeaderboardEntry {
  final int rank;
  final int userId;
  final String username;
  final String name;
  final String avatar;

  /// Two-letter code, or empty. Shown under the name as the place.
  final String country;

  /// Lifetime points — what the board ranks on. See points.php for why
  /// that and not the spendable balance.
  final int points;

  final bool isMe;

  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.username,
    required this.name,
    required this.avatar,
    required this.country,
    required this.points,
    required this.isMe,
  });

  factory LeaderboardEntry.fromMap(Map<String, dynamic> map) =>
      LeaderboardEntry(
        rank: _int(map['rank']),
        userId: _int(map['user_id']),
        username: '${map['username'] ?? ''}',
        name: '${map['name'] ?? ''}',
        avatar: '${map['avatar'] ?? ''}',
        country: '${map['country'] ?? ''}',
        points: _int(map['points']),
        isMe: map['is_me'] == true,
      );

  /// What to show, preferring the display name.
  String get bestName => name.trim().isNotEmpty ? name.trim() : username;

  static int _int(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }
}

/// A person's own standing.
class MyPoints {
  /// Spendable.
  final int current;

  /// Ever earned. What the leaderboard ranks on.
  final int lifetime;

  /// Null when they have never earned anything.
  ///
  /// Deliberately not a number: before anything awards points everybody
  /// is on zero, and "#40,000" shared by the entire user base is not a
  /// position. The screen says nothing rather than something untrue.
  final int? rank;

  final String country;

  const MyPoints({
    required this.current,
    required this.lifetime,
    required this.rank,
    required this.country,
  });

  static const empty = MyPoints(
    current: 0,
    lifetime: 0,
    rank: null,
    country: '',
  );

  factory MyPoints.fromMap(Map<String, dynamic> map) => MyPoints(
    current: LeaderboardEntry._int(map['current']),
    lifetime: LeaderboardEntry._int(map['lifetime']),
    rank: map['rank'] == null ? null : LeaderboardEntry._int(map['rank']),
    country: '${map['country'] ?? ''}',
  );
}

/// Which slice of the board to show.
enum LeaderboardScope {
  worldwide('worldwide', 'Worldwide'),
  country('country', 'My country');

  final String id;
  final String label;

  const LeaderboardScope(this.id, this.label);
}

/// Points and the leaderboard.
///
/// Nothing awards points yet, so every one of these returns zero or an
/// empty list today. That is the expected state — the endpoints are real
/// and the numbers are not there to be read.
class PointsAPI {
  static final AuthService _auth = AuthService();

  static String get _base => AppEnvironment.wordpressBase;

  static Future<Map<String, String>?> _headers() async {
    final token = await _auth.getToken();
    if (token == null) return null;

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// The signed-in person's balance and rank.
  static Future<MyPoints> mine() async {
    try {
      final headers = await _headers();
      if (headers == null) return MyPoints.empty;

      final response = await http.get(
        Uri.parse('$_base/wp-json/app/v2/points/me'),
        headers: headers,
      );

      if (response.statusCode != 200) return MyPoints.empty;

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return MyPoints.empty;

      return MyPoints.fromMap(Map<String, dynamic>.from(body));
    } catch (e) {
      debugPrint('[Points] mine threw: $e');
      return MyPoints.empty;
    }
  }

  /// The board, and the caller's own standing alongside it.
  ///
  /// Returns both together because the screen shows both and splitting
  /// them would be two round trips for one view.
  static Future<({List<LeaderboardEntry> entries, MyPoints me})> leaderboard({
    LeaderboardScope scope = LeaderboardScope.worldwide,
    int limit = 50,
    int offset = 0,
  }) async {
    const fallback = (entries: <LeaderboardEntry>[], me: MyPoints.empty);

    try {
      final headers = await _headers();
      if (headers == null) return fallback;

      final response = await http.get(
        Uri.parse(
          '$_base/wp-json/app/v2/points/leaderboard'
          '?scope=${scope.id}&limit=$limit&offset=$offset',
        ),
        headers: headers,
      );

      if (response.statusCode != 200) return fallback;

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return fallback;

      final entries = (body['leaderboard'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) => LeaderboardEntry.fromMap(Map<String, dynamic>.from(row)),
          )
          .toList();

      final me = body['me'] is Map
          ? MyPoints.fromMap(Map<String, dynamic>.from(body['me'] as Map))
          : MyPoints.empty;

      return (entries: entries, me: me);
    } catch (e) {
      debugPrint('[Points] leaderboard threw: $e');
      return fallback;
    }
  }
}
