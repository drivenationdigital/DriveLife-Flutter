import 'dart:convert';

import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A one-time notice from the server.
@immutable
class Announcement {
  /// Permanent, and written to the database on dismissal. Renaming one
  /// re-shows it to everybody who had already dismissed it.
  final String key;

  final String title;
  final String? intro;

  /// Paragraphs, shown one under another. Sent as a list rather than one
  /// string because the breaks matter: a single blob reads as terms and
  /// conditions, and two short paragraphs read as news.
  final List<String> body;

  /// The sign-off. Kept apart from [body] so it reads as one rather than
  /// as a final paragraph.
  final String? outro;

  final String cta;

  const Announcement({
    required this.key,
    required this.title,
    this.intro,
    required this.body,
    this.outro,
    required this.cta,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      key: (json['key'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      intro: (json['intro']?.toString().trim().isEmpty ?? true)
          ? null
          : json['intro'].toString(),
      body: (json['body'] as List? ?? [])
          .map((line) => line.toString())
          .where((line) => line.trim().isNotEmpty)
          .toList(),
      outro: (json['outro']?.toString().trim().isEmpty ?? true)
          ? null
          : json['outro'].toString(),
      cta: (json['cta'] ?? 'Got it').toString(),
    );
  }

  bool get isUsable => key.isNotEmpty && title.isNotEmpty;
}

/// One-time notices, decided by the server.
///
/// Deliberately not FeatureTipsProvider, which remembers dismissals in
/// SharedPreferences. That is right for pointing at a new button and wrong
/// here for two reasons: it does not know when an account was created — so a
/// notice about something done to existing data would be shown to people it
/// never happened to — and it is per-device, so the same person on a phone
/// and a tablet would be told twice.
class AnnouncementApi {
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

  static Uri _uri(String path) =>
      Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/$path');

  /// The notice waiting for this person, or null.
  ///
  /// Null for every failure as well as for "nothing to say". A notice that
  /// could not be fetched is a notice that waits until next time, which is
  /// the whole point of the server remembering rather than the device.
  static Future<Announcement?> pending() async {
    try {
      final response = await http.get(
        _uri('announcement'),
        headers: await _headers(),
      );

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);

      if (body is! Map || body['success'] != true) return null;

      final raw = body['announcement'];

      if (raw is! Map) return null;

      final announcement = Announcement.fromJson(
        Map<String, dynamic>.from(raw),
      );

      return announcement.isUsable ? announcement : null;
    } catch (error) {
      debugPrint('AnnouncementApi.pending failed: $error');

      return null;
    }
  }

  /// Mark it dismissed. Fire and forget from the caller's point of view —
  /// a lost write costs one extra showing, never a stuck dialog.
  static Future<bool> markSeen(String key) async {
    try {
      final response = await http.post(
        _uri('announcement/seen'),
        headers: await _headers(),
        body: jsonEncode({'key': key}),
      );

      return response.statusCode == 200;
    } catch (error) {
      debugPrint('AnnouncementApi.markSeen failed: $error');

      return false;
    }
  }
}
