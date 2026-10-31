import 'dart:convert';

import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One day's puzzle.
class GuessGame {
  final int id;
  final String date;
  final String image;
  final List<String> options;

  final bool isOpen;
  final bool isClosed;
  final int points;

  /// Which option this user picked, or null if they have not played.
  final int? myChoice;

  /// Whether they got it right. Null until the game closes — before
  /// that the server will not say, because "was I right" asked four
  /// times is the answer.
  final bool? myCorrect;

  /// Only present once closed.
  final int? answerIndex;
  final String? answer;

  /// The clear photograph of the car. Empty until the game closes —
  /// the server withholds it on the same terms as the answer, because
  /// a clear photo of the car IS the answer.
  final String revealImage;

  const GuessGame({
    required this.id,
    required this.date,
    required this.image,
    required this.options,
    required this.isOpen,
    required this.isClosed,
    required this.points,
    this.myChoice,
    this.myCorrect,
    this.answerIndex,
    this.answer,
    this.revealImage = '',
  });

  bool get hasPlayed => myChoice != null;

  /// A number, however the server typed it.
  ///
  /// PHP hands integers back as JSON numbers normally and as STRINGS
  /// when a column comes straight out of MySQL without a cast, and
  /// `as num?` throws on a string rather than returning null.
  static int _int(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  /// The four options, whatever shape they arrive in.
  ///
  /// `as List?` on its own is a cast that THROWS rather than returning
  /// null when the value is something else — and a MySQL JSON column
  /// round-tripping through PHP can come back as a JSON string rather
  /// than an array. That is a TypeError before the screen paints,
  /// which is a crash and not a missing option.
  static List<String> _options(dynamic raw) {
    if (raw is List) return raw.map((o) => '$o').toList();

    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((o) => '$o').toList();
      } catch (_) {
        // Falls through to empty — a game with no readable options
        // shows as a photo with no buttons, which is wrong but
        // survivable.
      }
    }

    return const [];
  }

  factory GuessGame.fromMap(Map<String, dynamic> map) => GuessGame(
    id: _int(map['id']),
    date: '${map['date'] ?? ''}',
    image: '${map['image'] ?? ''}',
    options: _options(map['options']),
    isOpen: map['is_open'] == true,
    isClosed: map['is_closed'] == true,
    points: _int(map['points'], 500),
    myChoice: map['my_choice'] == null ? null : _int(map['my_choice']),
    myCorrect: map['my_correct'] is bool ? map['my_correct'] as bool : null,
    answerIndex: map['answer_index'] == null ? null : _int(map['answer_index']),
    answer: map['answer'] == null ? null : '${map['answer']}',
    revealImage: '${map['reveal_image'] ?? ''}',
  );
}

/// A row of the guess leaderboard.
class GuessRank {
  final int rank;
  final int userId;
  final String username;
  final String name;
  final String avatar;
  final String country;

  /// What the board ranks on. Correct guesses, not points — points
  /// would mix in everything else somebody has earned elsewhere.
  final int correct;

  final bool isMe;

  const GuessRank({
    required this.rank,
    required this.userId,
    required this.username,
    required this.name,
    required this.avatar,
    required this.country,
    required this.correct,
    required this.isMe,
  });

  String get bestName => name.trim().isNotEmpty ? name.trim() : username;

  factory GuessRank.fromMap(Map<String, dynamic> map) => GuessRank(
    rank: GuessGame._int(map['rank']),
    userId: GuessGame._int(map['user_id']),
    username: '${map['username'] ?? ''}',
    name: '${map['name'] ?? ''}',
    avatar: '${map['avatar'] ?? ''}',
    country: '${map['country'] ?? ''}',
    correct: GuessGame._int(map['correct']),
    isMe: map['is_me'] == true,
  );
}

/// The daily game.
class GuessAPI {
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

  /// Today's puzzle, or null when none is scheduled.
  ///
  /// Null is a normal answer, not a failure: somebody has to schedule
  /// these and may not have. The home card shows nothing rather than an
  /// empty frame.
  static Future<GuessGame?> today() async {
    try {
      final headers = await _headers();
      if (headers == null) return null;

      final response = await http.get(
        Uri.parse('$_base/wp-json/app/v2/guess/today'),
        headers: headers,
      );

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return null;
      if (body['game'] == null) return null;

      return GuessGame.fromMap(Map<String, dynamic>.from(body['game'] as Map));
    } catch (e) {
      debugPrint('[Guess] today threw: $e');
      return null;
    }
  }

  /// Lock in a guess.
  ///
  /// Returns the game as it stands afterwards, or null if it was
  /// refused — closed, or already played. The server does NOT say
  /// whether the guess was right; that arrives at close with everyone
  /// else's.
  static Future<GuessGame?> play({
    required int gameId,
    required int choice,
  }) async {
    try {
      final headers = await _headers();
      if (headers == null) return null;

      final response = await http.post(
        Uri.parse('$_base/wp-json/app/v2/guess/play'),
        headers: headers,
        body: jsonEncode({'game_id': gameId, 'choice': choice}),
      );

      final body = jsonDecode(response.body);

      if (response.statusCode != 200 ||
          body is! Map ||
          body['success'] != true) {
        debugPrint('[Guess] play refused: ${response.body}');
        return null;
      }

      return GuessGame.fromMap(Map<String, dynamic>.from(body['game'] as Map));
    } catch (e) {
      debugPrint('[Guess] play threw: $e');
      return null;
    }
  }

  /// Closed games, newest first.
  static Future<List<GuessGame>> history({int days = 7}) async {
    try {
      final headers = await _headers();
      if (headers == null) return const [];

      final response = await http.get(
        Uri.parse('$_base/wp-json/app/v2/guess/history?days=$days'),
        headers: headers,
      );

      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return const [];

      return (body['games'] as List? ?? const [])
          .whereType<Map>()
          .map((g) => GuessGame.fromMap(Map<String, dynamic>.from(g)))
          .toList();
    } catch (e) {
      debugPrint('[Guess] history threw: $e');
      return const [];
    }
  }

  /// The board, and where the caller sits on it.
  static Future<({List<GuessRank> entries, int correct, int? rank})>
  leaderboard({String scope = 'worldwide'}) async {
    const fallback = (entries: <GuessRank>[], correct: 0, rank: null);

    try {
      final headers = await _headers();
      if (headers == null) return fallback;

      final response = await http.get(
        Uri.parse('$_base/wp-json/app/v2/guess/leaderboard?scope=$scope'),
        headers: headers,
      );

      if (response.statusCode != 200) return fallback;

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return fallback;

      final entries = (body['leaderboard'] as List? ?? const [])
          .whereType<Map>()
          .map((r) => GuessRank.fromMap(Map<String, dynamic>.from(r)))
          .toList();

      final me = body['me'] is Map
          ? Map<String, dynamic>.from(body['me'] as Map)
          : const <String, dynamic>{};

      return (
        entries: entries,
        correct: GuessGame._int(me['correct']),
        rank: me['rank'] == null ? null : GuessGame._int(me['rank']),
      );
    } catch (e) {
      debugPrint('[Guess] leaderboard threw: $e');
      return fallback;
    }
  }
}
