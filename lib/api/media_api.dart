import 'dart:convert';

import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/models/media_models.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thrown when a media-matches call fails, carrying a message safe to surface.
class MediaApiException implements Exception {
  final String message;
  const MediaApiException(this.message);

  @override
  String toString() => message;
}

/// Client for `dl-media-matches.php` — the "Images of you" endpoints.
///
/// Every call needs the Bearer token; the backend resolves the user from it, so
/// no user ID is ever sent. Failures throw [MediaApiException] rather than
/// returning empty, so the screens can tell "nothing pending" apart from
/// "couldn't reach the server".
class MediaAPI {
  MediaAPI._();

  static const String _base = '${ApiConfig.baseUrl}/wp-json/app/v2';
  static final AuthService _auth = AuthService();

  static Future<Map<String, String>> _headers() async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) {
      throw const MediaApiException('You need to be signed in.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Decodes a response body, turning any non-2xx or `success: false` into a
  /// [MediaApiException] carrying the server's own message where there is one.
  static Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      // Fall through — a non-JSON body is handled by the status check below.
    }

    if (response.statusCode == 401) {
      throw const MediaApiException('Your session has expired.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MediaApiException(
        body?['message']?.toString() ??
            'Something went wrong (${response.statusCode}).',
      );
    }

    if (body == null) {
      throw const MediaApiException('Unexpected response from the server.');
    }

    if (body['success'] == false) {
      throw MediaApiException(
        body['message']?.toString() ?? 'Request failed.',
      );
    }

    return body;
  }

  /// Photos matched to the signed-in user's garage vehicles.
  ///
  /// [status] is one of `pending`, `accepted`, `declined`, `ignored`, `all`.
  static Future<PendingImagesResponse> getMatches({
    String status = 'pending',
    int page = 1,
    int limit = 20,
  }) async {
    print('$_base/media-matches');
    final uri = Uri.parse('$_base/media-matches').replace(
      queryParameters: {
        'status': status,
        'page': '$page',
        'limit': '$limit',
      },
    );

    try {
      final response = await http
          .get(uri, headers: await _headers())
          .timeout(ApiConfig.requestTimeout);

          print(response.body);

      return PendingImagesResponse.fromJson(_decode(response));
    } on MediaApiException {
      rethrow;
    } catch (e) {
      debugPrint('MediaAPI.getMatches failed: $e');
      throw const MediaApiException('Could not load your images.');
    }
  }

  /// Events with community photo galleries, busiest first.
  ///
  /// When nothing has photos yet the backend returns upcoming/recent events
  /// instead, flagged via [EventGalleriesResponse.isFallback].
  static Future<EventGalleriesResponse> getEventGalleries({
    int limit = 10,
  }) async {
    final uri = Uri.parse(
      '$_base/media-galleries',
    ).replace(queryParameters: {'limit': '$limit'});

    try {
      final response = await http
          .get(uri, headers: await _headers())
          .timeout(ApiConfig.requestTimeout);

      return EventGalleriesResponse.fromJson(_decode(response));
    } on MediaApiException {
      rethrow;
    } catch (e) {
      debugPrint('MediaAPI.getEventGalleries failed: $e');
      throw const MediaApiException('Could not load event galleries.');
    }
  }

  /// Posts ordered by like count, highest first.
  static Future<List<PopularImage>> getPopularImages({
    int limit = 30,
    int page = 1,
  }) async {
    final uri = Uri.parse('$_base/media-popular').replace(
      queryParameters: {'limit': '$limit', 'page': '$page'},
    );

    try {
      final response = await http
          .get(uri, headers: await _headers())
          .timeout(ApiConfig.requestTimeout);

      final body = _decode(response);
      return ((body['data'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PopularImage.fromJson)
          .where((image) => image.imageUrl.isNotEmpty)
          .toList();
    } on MediaApiException {
      rethrow;
    } catch (e) {
      debugPrint('MediaAPI.getPopularImages failed: $e');
      throw const MediaApiException('Could not load popular images.');
    }
  }

  /// Accept or decline a single photo. [decision] is `accepted` or `declined`.
  static Future<void> decide({
    required String mediaId,
    required String decision,
  }) async {
    final uri = Uri.parse('$_base/media-matches/decide');

    try {
      final response = await http
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode({'media_id': mediaId, 'decision': decision}),
          )
          .timeout(ApiConfig.requestTimeout);

      _decode(response);
    } on MediaApiException {
      rethrow;
    } catch (e) {
      debugPrint('MediaAPI.decide failed: $e');
      throw const MediaApiException('Could not save that. Try again.');
    }
  }

  /// Accept or decline everything still pending. Returns how many changed.
  static Future<int> decideAll({
    required String decision,
    int? vehicleId,
  }) async {
    final uri = Uri.parse('$_base/media-matches/decide-all');

    try {
      final response = await http
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode({
              'decision': decision,
              if (vehicleId != null) 'vehicle_id': vehicleId,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      final body = _decode(response);
      return int.tryParse(body['affected']?.toString() ?? '') ?? 0;
    } on MediaApiException {
      rethrow;
    } catch (e) {
      debugPrint('MediaAPI.decideAll failed: $e');
      throw const MediaApiException('Could not save that. Try again.');
    }
  }
}
