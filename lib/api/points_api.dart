import 'dart:convert';

import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One row of the leaderboard.
/// What the server pays for each action.
///
/// The amounts used to be written out in four places in the app, and
/// one of them was missed when the rewards were reduced — the guess
/// card promised 500 for an award that paid 50. They now come from
/// /app/v2/points/rules so the server is the only place they live.
class PointsRules {
  /// rule name -> amount. Unknown rules are simply absent.
  final Map<String, int> amounts;

  /// The user-facing explanation, written by the server so wording can
  /// be corrected without a release.
  final String summary;

  const PointsRules({required this.amounts, required this.summary});

  /// Today's real values, used until the fetch lands and whenever it
  /// fails. Kept honest deliberately: a fallback that OVERSTATES a
  /// reward is the exact failure this endpoint exists to prevent.
  static const PointsRules fallback = PointsRules(
    amounts: {
      'post_added': 50,
      'spot_added': 50,
      'gallery_added': 75,
      'guess_correct': 50,
      'vehicle_added': 150,
    },
    summary:
        'Posts and spots earn 50, galleries 75 and vehicles 150, with a '
        'daily limit on each.\n\n'
        'We trust you to log real cars. Delete something you earned '
        'points for and those points come back off — your balance '
        'never drops below zero.',
  );

  /// What one action pays, or the fallback's figure if the server has
  /// not been heard from.
  int amountFor(String rule) => amounts[rule] ?? fallback.amounts[rule] ?? 0;

  factory PointsRules.fromMap(Map<String, dynamic> map) {
    final raw = map['rules'];
    final amounts = <String, int>{};

    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is Map && value['amount'] != null) {
          final amount = value['amount'];
          amounts['$key'] = amount is num
              ? amount.toInt()
              : int.tryParse('$amount') ?? 0;
        }
      });
    }

    final summary = map['summary'];

    return PointsRules(
      amounts: amounts.isEmpty ? fallback.amounts : amounts,
      summary: summary is String && summary.trim().isNotEmpty
          ? summary
          : fallback.summary,
    );
  }
}

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

/// One line in somebody's points history.
///
/// A signed [amount]: positive is earned, negative is taken back —
/// either a reversal, because the thing that paid was deleted, or a
/// redemption. The server picks the wording, so a rule added later needs
/// no app release to read properly.
class PointsEntry {
  /// The ledger row id. Only used as a list key.
  final int id;

  /// Signed. Never zero — the server filters those out, because a
  /// reversal that recovered nothing is bookkeeping rather than history.
  final int amount;

  /// What the balance stood at immediately after this row.
  final int balanceAfter;

  /// "Post created", "Vehicle removed", "Redeemed".
  final String label;

  /// An admin's note on a manual grant, when there is one.
  final String? reason;

  /// UTC, as the server stores it.
  final DateTime? at;

  const PointsEntry({
    required this.id,
    required this.amount,
    required this.balanceAfter,
    required this.label,
    this.reason,
    this.at,
  });

  bool get isGain => amount > 0;

  factory PointsEntry.fromMap(Map<String, dynamic> map) {
    final raw = map['created_at']?.toString();

    return PointsEntry(
      id: int.tryParse('${map['id']}') ?? 0,
      amount: int.tryParse('${map['amount']}') ?? 0,
      balanceAfter: int.tryParse('${map['balance_after']}') ?? 0,
      label: (map['label']?.toString().trim().isNotEmpty ?? false)
          ? map['label'].toString().trim()
          : 'Points adjustment',
      reason: (map['reason']?.toString().trim().isNotEmpty ?? false)
          ? map['reason'].toString().trim()
          : null,
      // The ledger stores 'Y-m-d H:i:s' with no zone marker, and writes
      // it with current_time('mysql', 1) — so it is UTC and has to be
      // told so, or every entry reads hours out for anybody not on GMT.
      at: raw == null ? null : DateTime.tryParse('${raw}Z'.replaceAll(' ', 'T')),
    );
  }
}

/// A page of points history.
class PointsHistory {
  final List<PointsEntry> entries;
  final bool hasMore;
  final int total;

  const PointsHistory({
    required this.entries,
    required this.hasMore,
    required this.total,
  });

  static const empty = PointsHistory(
    entries: <PointsEntry>[],
    hasMore: false,
    total: 0,
  );
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

  /// What each action is worth, and the words that explain it.
  ///
  /// No token: it is a price list, identical for everybody, and the
  /// last step of signup needs it before there is reliably one.
  ///
  /// Returns NULL when it could not be fetched, rather than the
  /// fallback.
  ///
  /// The caller already holds [PointsRules.fallback] and keeps showing
  /// it, so handing it back here would say nothing — and it would make
  /// a failure indistinguishable from a server that happens to agree
  /// with the fallback, which is exactly the case where a retry is
  /// worth attempting.
  ///
  /// A malformed but successful response is NOT a failure: fromMap
  /// fills the gaps from the fallback per field and that is returned,
  /// because the server did answer.
  static Future<PointsRules?> rules() async {
    try {
      final response = await http.get(
        Uri.parse('$_base/wp-json/app/v2/points/rules'),
        headers: const {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        debugPrint('[Points] rules failed: ${response.statusCode}');
        return null;
      }

      final body = jsonDecode(response.body);

      if (body is! Map || body['success'] != true) return null;

      return PointsRules.fromMap(Map<String, dynamic>.from(body));
    } catch (e) {
      debugPrint('[Points] rules threw: $e');
      return null;
    }
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

  /// Where this person's points came from, and where they went.
  ///
  /// Newest first. Throws nothing: a failure is an empty page, which
  /// the screen shows as "nothing yet" with a retry rather than an
  /// error nobody can act on.
  ///
  /// Signed in only, and the server reads the user from the token —
  /// there is no user id to pass, deliberately, because this is
  /// somebody's own earning history.
  static Future<PointsHistory> history({int page = 1, int perPage = 30}) async {
    try {
      final headers = await _headers();
      if (headers == null) return PointsHistory.empty;

      final uri = Uri.parse('$_base/wp-json/app/v2/points/history').replace(
        queryParameters: {'page': '$page', 'per_page': '$perPage'},
      );

      final response = await http.get(uri, headers: headers);

      if (response.statusCode != 200) {
        debugPrint('[Points] history failed: ${response.statusCode}');
        return PointsHistory.empty;
      }

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return PointsHistory.empty;

      final rows = (body['data'] as List<dynamic>?) ?? const [];

      return PointsHistory(
        entries: rows
            .whereType<Map<String, dynamic>>()
            .map(PointsEntry.fromMap)
            .toList(),
        hasMore: body['has_more'] == true,
        total: int.tryParse('${body['total']}') ?? 0,
      );
    } catch (e) {
      debugPrint('[Points] history threw: $e');
      return PointsHistory.empty;
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
