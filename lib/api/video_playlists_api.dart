import 'dart:convert';

import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One playlist, as the picker and the shelf read it.
class VideoPlaylist {
  final int id;
  final String title;

  /// How many videos are in it.
  final int count;

  /// Curated by DriveLife rather than by this person.
  final bool isPublic;

  /// Whether it already holds the video the picker was opened for.
  /// Always false when no video was named.
  final bool contains;

  /// The first video's poster frame, for the card.
  final String coverUrl;

  /// Everything in it, added up, in seconds.
  final int durationSeconds;

  const VideoPlaylist({
    required this.id,
    required this.title,
    this.count = 0,
    this.isPublic = false,
    this.contains = false,
    this.coverUrl = '',
    this.durationSeconds = 0,
  });

  VideoPlaylist copyWith({bool? contains, int? count}) => VideoPlaylist(
    id: id,
    title: title,
    count: count ?? this.count,
    isPublic: isPublic,
    contains: contains ?? this.contains,
    coverUrl: coverUrl,
    durationSeconds: durationSeconds,
  );

  /// "Empty", "1 video", "12 videos".
  String get countLabel => switch (count) {
    <= 0 => 'Empty',
    1 => '1 video',
    _ => '$count videos',
  };

  /// How long it would take to watch the lot: "2 hr 14 min".
  ///
  /// Rounded to minutes, and never seconds. Nobody deciding whether
  /// to start a playlist cares about the seconds, and "2 hr 14 min 7
  /// sec" claims a precision the sum of six encodes does not have.
  String get runtimeLabel {
    if (durationSeconds <= 0) return '';

    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;

    if (hours > 0) {
      return minutes > 0 ? '$hours hr $minutes min' : '$hours hr';
    }

    // Under a minute is still "1 min". A playlist of one short clip
    // saying "0 min" reads as empty.
    return '${minutes < 1 ? 1 : minutes} min';
  }

  factory VideoPlaylist.fromJson(Map<String, dynamic> json) {
    int asInt(Object? value) => int.tryParse('${value ?? ''}') ?? 0;

    return VideoPlaylist(
      id: asInt(json['id']),
      title: '${json['title'] ?? ''}'.trim(),
      count: asInt(json['count']),
      isPublic: json['is_public'] == true,
      contains: json['contains'] == true,
      coverUrl: '${json['cover_url'] ?? ''}',
      durationSeconds: asInt(json['duration']),
    );
  }
}

/// Playlists of long-form videos.
///
/// Everything here needs a signed-in person: a playlist belongs to
/// somebody. The one exception is a public playlist, which anybody
/// signed in can read but only its owner or an administrator can
/// change - enforced on the server, not here.
class VideoPlaylistsAPI {
  VideoPlaylistsAPI._();

  static String get _base => '${ApiConfig.baseUrl}/wp-json/app/v2';
  static final AuthService _auth = AuthService();

  static Future<Map<String, String>> _headers() async {
    final token = await _auth.getToken();

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Every playlist this person can see.
  ///
  /// [forVideo] makes each one say whether it already holds that
  /// video, which is what turns the picker from a list into a set of
  /// checkboxes.
  static Future<List<VideoPlaylist>> list({String? forVideo}) async {
    try {
      final uri = Uri.parse('$_base/video-playlists').replace(
        queryParameters: {
          if (forVideo != null && forVideo.isNotEmpty) 'video_id': forVideo,
        },
      );

      final response = await http
          .get(uri, headers: await _headers())
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body);

      if (body is! Map || body['data'] is! List) return const [];

      return [
        for (final item in body['data'] as List)
          if (item is Map<String, dynamic>) VideoPlaylist.fromJson(item),
      ];
    } catch (e) {
      debugPrint('[playlists] list failed: $e');

      return const [];
    }
  }

  /// Makes one. Returns it, so the picker can tick it immediately
  /// rather than reloading the whole list to find it.
  static Future<VideoPlaylist?> create(String title) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/video-playlists'),
            headers: await _headers(),
            body: jsonEncode({'title': title}),
          )
          .timeout(ApiConfig.requestTimeout);

      final body = jsonDecode(response.body);

      if (response.statusCode != 200 ||
          body is! Map ||
          body['success'] != true) {
        return null;
      }

      return VideoPlaylist.fromJson(Map<String, dynamic>.from(body));
    } catch (e) {
      debugPrint('[playlists] create failed: $e');

      return null;
    }
  }

  /// Puts a video in, or takes it out.
  static Future<bool> setMembership({
    required int playlistId,
    required String videoId,
    required bool inPlaylist,
  }) async {
    final action = inPlaylist ? 'add' : 'remove';

    try {
      final response = await http
          .post(
            Uri.parse('$_base/video-playlists/$playlistId/$action'),
            headers: await _headers(),
            body: jsonEncode({'video_id': videoId}),
          )
          .timeout(ApiConfig.requestTimeout);

      final body = jsonDecode(response.body);

      return response.statusCode == 200 &&
          body is Map &&
          body['success'] == true;
    } catch (e) {
      debugPrint('[playlists] $action failed: $e');

      return false;
    }
  }

  /// What is in one, in order.
  static Future<({VideoPlaylist? playlist, List<LongVideo> videos})> videos(
    int playlistId,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_base/video-playlists/$playlistId'),
            headers: await _headers(),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 200) {
        return (playlist: null, videos: const <LongVideo>[]);
      }

      final body = jsonDecode(response.body);

      if (body is! Map) return (playlist: null, videos: const <LongVideo>[]);

      return (
        playlist: body['playlist'] is Map<String, dynamic>
            ? VideoPlaylist.fromJson(
                body['playlist'] as Map<String, dynamic>,
              )
            : null,
        videos: [
          for (final item in (body['data'] as List? ?? const []))
            if (item is Map<String, dynamic>) LongVideo.fromJson(item),
        ],
      );
    } catch (e) {
      debugPrint('[playlists] videos failed: $e');

      return (playlist: null, videos: const <LongVideo>[]);
    }
  }

  static Future<bool> delete(int playlistId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$_base/video-playlists/$playlistId'),
            headers: await _headers(),
          )
          .timeout(ApiConfig.requestTimeout);

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[playlists] delete failed: $e');

      return false;
    }
  }
}
