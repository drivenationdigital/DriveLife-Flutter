import 'dart:convert';

import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// DriveLife's own long-form videos.
///
/// ── THE ENDPOINT DOES NOT EXIST YET ─────────────────────────────────
///
/// So [list] asks for it, and falls back to [sample] when the server
/// has never heard of it. That is deliberate and temporary, and it is
/// the same shape the membership work used: the screen is built
/// against the real call, and something stands in until the call is
/// real, so the UI can be looked at and argued with today.
///
/// The fallback is keyed on the request FAILING, not on a flag, so the
/// day `/app/v2/videos` returns anything at all the sample data stops
/// being used with nothing to remember to switch off. It is also
/// barred from release builds - see [_sampleAllowed] - because sample
/// videos on a customer's phone is worse than an empty section.
///
/// ── WHAT THE SERVER HAS TO RETURN ───────────────────────────────────
///
///   GET /app/v2/videos?limit=10
///   {
///     "success": true,
///     "data": [
///       {
///         "post_id": 12345,
///         "title": "...",
///         "description": "...",
///         "thumbnail_url": "...",
///         "video_url": "...",
///         "duration": 2840,
///         "published_at": "2026-11-01T09:00:00Z",
///         "like_count": 12,
///         "comment_count": 4,
///         "liked": false
///       }
///     ]
///   }
///
/// `post_id` is the important one: it is a real post, so likes and
/// comments go through InteractionsAPI exactly as they do everywhere
/// else. See the note on [LongVideo].
class VideosApiException implements Exception {
  final String message;

  const VideosApiException(this.message);

  @override
  String toString() => message;
}

class VideosAPI {
  VideosAPI._();

  static String get _base => '${ApiConfig.baseUrl}/wp-json/app/v2';
  static final AuthService _auth = AuthService();

  /// Sample data is a development convenience and must never ship.
  static bool get _sampleAllowed => !kReleaseMode;

  static Future<Map<String, String>> _headers() async {
    final token = await _auth.getToken();

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// The videos for the row on the media tab.
  static Future<List<LongVideo>> list({int limit = 10, String? search}) async {
    final term = search?.trim() ?? '';

    final uri = Uri.parse('$_base/videos').replace(
      queryParameters: {
        'limit': '$limit',
        if (term.isNotEmpty) 'search': term,
      },
    );

    try {
      final response = await http
          .get(uri, headers: await _headers())
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 200) {
        debugPrint('[videos] HTTP ${response.statusCode}');

        return _fallback(searching: term.isNotEmpty);
      }

      final body = jsonDecode(response.body);

      if (body is! Map || body['data'] is! List) {
        return _fallback(searching: term.isNotEmpty);
      }

      return [
        for (final item in body['data'] as List)
          if (item is Map<String, dynamic>) LongVideo.fromJson(item),
      ];
    } catch (e) {
      debugPrint('[videos] list failed: $e');

      return _fallback(searching: term.isNotEmpty);
    }
  }

  static List<LongVideo> _fallback({bool searching = false}) {
    // Never while searching. Sample data appearing because a search
    // request failed would look like results for the term typed,
    // which is worse than an empty list.
    if (searching) return const [];

    return _sampleAllowed ? sample : const [];
  }

  /// Stand-in videos, for building the screen before the endpoint is
  /// written. Debug builds only.
  ///
  /// The clips are Google's public test files, which is enough to prove
  /// playback, scrubbing, resuming and rotation work. The post ids are
  /// deliberately NOT plausible: a real id here would attach real
  /// comments to a fake video.
  static List<LongVideo> get sample => const [
    LongVideo(
      postId: 'sample-1',
      title: 'Cold start: winter drives in the Peak District',
      description:
          'An early morning run out through the Peaks, and what the cold '
          'does to a car that has sat all week.',
      thumbnailUrl:
          'https://storage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
      videoUrl:
          'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      durationSeconds: 596,
      likeCount: 48,
      commentCount: 12,
    ),
    LongVideo(
      postId: 'sample-2',
      title: 'Garage tour: twenty years of one marque',
      description:
          'A collection built slowly, and the three cars the owner says '
          'he will never sell.',
      thumbnailUrl:
          'https://storage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg',
      videoUrl:
          'https://storage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      durationSeconds: 653,
      likeCount: 91,
      commentCount: 27,
    ),
    LongVideo(
      postId: 'sample-3',
      title: 'Breakfast run, start to finish',
      description: 'Ninety cars, one car park, and a very long queue for bacon.',
      thumbnailUrl:
          'https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg',
      videoUrl:
          'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
      durationSeconds: 15,
      likeCount: 7,
      commentCount: 2,
    ),
  ];

  /// Whether this person may upload, and whether the server can.
  ///
  /// Only so the button can be hidden. The endpoints enforce it on
  /// their own - see dl_videos_is_admin - because a button in a
  /// binary anybody can decompile is a courtesy, not a control.
  static Future<({bool canUpload, bool configured})> uploadPermission() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_base/videos/can-upload'),
            headers: await _headers(),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 200) {
        return (canUpload: false, configured: false);
      }

      final body = jsonDecode(response.body);

      if (body is! Map) return (canUpload: false, configured: false);

      return (
        canUpload: body['can_upload'] == true,
        configured: body['configured'] == true,
      );
    } catch (e) {
      debugPrint('[videos] permission check failed: $e');

      return (canUpload: false, configured: false);
    }
  }

  /// Starts an upload: creates the draft and mints the one-time URL.
  ///
  /// [sizeBytes] is required by tus - Cloudflare cannot reserve the
  /// upload without knowing how big it is up front.
  static Future<({int postId, String uploadUrl})?> startUpload({
    required String title,
    required int sizeBytes,
    String description = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/videos/upload'),
            headers: await _headers(),
            body: jsonEncode({
              'title': title,
              'description': description,
              'size': sizeBytes,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      final body = jsonDecode(response.body);

      if (response.statusCode != 200 || body is! Map || body['success'] != true) {
        debugPrint('[videos] start upload: ${response.statusCode} ${response.body}');

        throw VideosApiException(
          body is Map && body['message'] is String
              ? body['message'] as String
              : 'Could not start the upload.',
        );
      }

      return (
        postId: int.tryParse('${body['post_id']}') ?? 0,
        uploadUrl: '${body['upload_url']}',
      );
    } on VideosApiException {
      rethrow;
    } catch (e) {
      debugPrint('[videos] start upload failed: $e');

      throw const VideosApiException('Could not start the upload.');
    }
  }

  /// How the encode is going.
  ///
  /// Cloudflare transcodes after the bytes land, so "uploaded" and
  /// "playable" are minutes apart on a long video. The screen polls
  /// this rather than claiming success at the end of the upload.
  static Future<
    ({String state, bool ready, String error, int duration, int pct})?
  >
  status(int postId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_base/videos/$postId/status'),
            headers: await _headers(),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);

      if (body is! Map) return null;

      return (
        state: '${body['state'] ?? ''}',
        ready: body['ready'] == true,
        error: '${body['error'] ?? ''}',
        duration: int.tryParse('${body['duration'] ?? 0}') ?? 0,
        pct: int.tryParse('${body['pct'] ?? 0}') ?? 0,
      );
    } catch (e) {
      debugPrint('[videos] status failed: $e');

      return null;
    }
  }

  /// Publishes it, or saves a new title and description.
  ///
  /// The server refuses to publish anything Cloudflare has not
  /// finished, so a card on the media tab can never open onto nothing.
  /// Saves whatever is passed, and only that.
  ///
  /// [thumbnailUrl] of `''` CLEARS a custom thumbnail, falling back
  /// to the frame Cloudflare picked. Null leaves it alone. The two
  /// are different answers and the empty string is a real one.
  static Future<bool> update({
    required int postId,
    String? title,
    String? description,
    bool? publish,
    String? thumbnailUrl,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/videos/$postId'),
            headers: await _headers(),
            body: jsonEncode({
              if (title != null) 'title': title,
              if (description != null) 'description': description,
              if (publish != null) 'publish': publish,
              if (thumbnailUrl != null) 'thumbnail': thumbnailUrl,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      final body = jsonDecode(response.body);

      return response.statusCode == 200 &&
          body is Map &&
          body['success'] == true;
    } catch (e) {
      debugPrint('[videos] update failed: $e');

      return false;
    }
  }

  /// Counts one view.
  ///
  /// Called once playback has actually run for a few seconds, not
  /// when the screen opens - see dl_videos_record_view for why.
  /// Quiet on failure: a lost view is not worth telling anybody
  /// about, and certainly not worth interrupting a video for.
  static Future<int?> markViewed(String postId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/videos/$postId/viewed'),
            headers: await _headers(),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);

      if (body is! Map) return null;

      return int.tryParse('${body['view_count'] ?? ''}');
    } catch (e) {
      debugPrint('[videos] view failed: $e');

      return null;
    }
  }

  /// Removes a video, here and on Cloudflare.
  ///
  /// Admin only, enforced on the server. Deleting on Cloudflare too is
  /// the point: a video removed from the app but left on Stream keeps
  /// costing storage minutes forever.
  static Future<bool> delete(String postId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$_base/videos/$postId'),
            headers: await _headers(),
          )
          .timeout(ApiConfig.requestTimeout);

      final body = jsonDecode(response.body);

      return response.statusCode == 200 &&
          body is Map &&
          body['success'] == true;
    } catch (e) {
      debugPrint('[videos] delete failed: $e');

      return false;
    }
  }
}
