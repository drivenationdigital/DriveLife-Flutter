import 'dart:io';

import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/models/club_api_models.dart';
import 'package:drivelife/models/event_media.dart';
import 'package:drivelife/models/my_clubs.dart';
import 'package:drivelife/utils/event_media_uploader.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:drivelife/services/auth_service.dart';

class ClubApiService {
  static final AuthService _authService = AuthService();
  static final _uploader = ChunkedFileUploader(apiUrl: ApiConfig.baseUrl);

  /// Get authorization headers
  static Future<Map<String, String>> _getHeaders() async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final authToken = await _authService.getToken();

    if (authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }

    return headers;
  }

  static Future<Map<String, dynamic>?> fetchClubDetail(String clubId) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/wp-json/app/v1/club-detail?club_id=$clubId',
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['club'];
        }
      }
      throw Exception('Failed to load club details');
    } catch (e) {
      print('Error fetching club details: $e');
      throw e;
    }
  }

  /// Invite a club administrator
  ///
  /// [encryptedClubId] - Encrypted club ID from the server
  /// [email] - Email address of the person to invite
  ///
  /// Returns [ApiResponse<ClubAdministrator>] with the new invitation
  static Future<ApiResponse<ClubAdministrator>> inviteClubAdmin(
    String encryptedClubId,
    String email,
  ) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/club/$encryptedClubId/invite-admin',
      );

      final response = await http.post(
        url,
        headers: await _getHeaders(),
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;

        if (json['success'] == true && json['data'] != null) {
          final admin = ClubAdministrator.fromJson(
            json['data'] as Map<String, dynamic>,
          );

          return ApiResponse<ClubAdministrator>(
            success: true,
            data: admin,
            message: json['message'] as String?,
          );
        }

        return ApiResponse<ClubAdministrator>(
          success: false,
          message:
              json['message'] as String? ?? 'Failed to invite administrator',
        );
      }

      return _handleError(response);
    } catch (e) {
      return _handleError<ClubAdministrator>(e);
    }
  }

  /// Remove a club administrator
  ///
  /// [encryptedClubId] - Encrypted club ID from the server
  /// [userId] - Encrypted user ID (for active admins)
  /// [invitationId] - Encrypted invitation ID (for pending invites)
  ///
  /// Returns [ApiResponse<void>] indicating success or failure
  static Future<ApiResponse<void>> removeClubAdmin(
    String encryptedClubId, {
    String? userId,
    String? invitationId,
  }) async {
    if (userId == null && invitationId == null) {
      return ApiResponse<void>(
        success: false,
        message: 'Either userId or invitationId must be provided',
      );
    }

    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/club/$encryptedClubId/remove-admin',
      );

      final body = <String, String>{};
      if (userId != null) body['user_id'] = userId;
      if (invitationId != null) body['invitation_id'] = invitationId;

      final request = http.Request('DELETE', url)
        ..headers.addAll(await _getHeaders())
        ..body = jsonEncode(body);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;

        return ApiResponse<void>(
          success: json['success'] as bool? ?? false,
          message: json['message'] as String?,
        );
      }

      return _handleError(response);
    } catch (e) {
      return _handleError<void>(e);
    }
  }

  /// Get user's clubs (clubs they own)
  static Future<ApiResponse<MyClubsResponse>> getMyClubs() async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/clubs/my-clubs',
      );

      final response = await http.get(url, headers: await _getHeaders());

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;

        if (json['success'] == true && json['data'] != null) {
          final clubsData = MyClubsResponse.fromJson(
            json['data'] as Map<String, dynamic>,
          );

          return ApiResponse<MyClubsResponse>(success: true, data: clubsData);
        }

        return ApiResponse<MyClubsResponse>(
          success: false,
          message: json['message'] as String? ?? 'Failed to load clubs',
        );
      }

      return _handleError(response);
    } catch (e) {
      return _handleError<MyClubsResponse>(e);
    }
  }

  /// Handle API errors
  static ApiResponse<T> _handleError<T>(dynamic error) {
    if (error is http.Response) {
      try {
        final json = jsonDecode(error.body);
        return ApiResponse<T>(
          success: false,
          message: json['message'] ?? 'An error occurred',
        );
      } catch (_) {
        return ApiResponse<T>(
          success: false,
          message: 'HTTP ${error.statusCode}: ${error.reasonPhrase}',
        );
      }
    }

    if (error is SocketException) {
      return ApiResponse<T>(success: false, message: 'No internet connection');
    }

    return ApiResponse<T>(success: false, message: error.toString());
  }

  // In your chunked_file_uploader.dart file

  static Future<Map<String, dynamic>?> uploadClubImages({
    required String clubId,
    required List<ImageData> images,
    required String type, // 'logo' or 'cover'
    Function(double progress)? onProgress,
  }) async {
    try {
      final result = await _uploader.updateClubImages(
        clubId: clubId,
        mediaList: images,
        mediaGroup: type,
        onOverallProgress: onProgress,
      );

      print('✅ [ClubApi] Images uploaded successfully');
      return result;
    } catch (e) {
      print('❌ [ClubApi] Exception: $e');
      return null;
    }
  }

  static Future<ApiResponse<ClubEditData>> getClubEditData(
    String encryptedClubId,
  ) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/club/$encryptedClubId',
      );
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final clubData = ClubEditData.fromJson(
            data['data'] as Map<String, dynamic>,
          );

          return ApiResponse<ClubEditData>(
            success: true,
            data: clubData,
            message: data['message'] as String?,
          );
        }

        return ApiResponse<ClubEditData>(
          success: false,
          message: data['message'] as String? ?? 'Failed to load club data',
        );
      }

      return _handleError(response);
    } catch (e) {
      print('Error fetching club edit data: $e');
      return _handleError<ClubEditData>(e);
    }
  }

  static Future<ApiResponse<void>> updateClubData(
    String encryptedClubId,
    ClubUpdateRequest updateRequest,
  ) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/club/$encryptedClubId',
      );

      final response = await http.post(
        url,
        headers: await _getHeaders(),
        body: jsonEncode(updateRequest.toJson()),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;

        return ApiResponse<void>(
          success: json['success'] as bool? ?? false,
          message: json['message'] as String?,
        );
      }

      return _handleError(response);
    } catch (e) {
      return _handleError<void>(e);
    }
  }

  static Future<String?> createClubInitial({
    required String title,
    required String type,
  }) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) {
        print('❌ No user token found');
        return null;
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v1/create-club'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'club_title': title, 'club_type': type}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['club_id'];
        }
      }
      throw Exception('Failed to create club');
    } catch (e) {
      print('Error creating club: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> deleteClub({
    required String clubId,
    required String site,
  }) async {
    final token = await AuthService().getToken();
    if (token == null) {
      print('❌ No user token found');
      return null;
    }

    try {
      final response = await http.delete(
        Uri.parse(
          '${ApiConfig.baseUrl}/wp-json/app/v1/club/$clubId?site=$site',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      }
      throw Exception('Failed to delete club');
    } catch (e) {
      print('Error deleting club: $e');
      return null;
    }
  }

  static Future<List<ClubCategory>> fetchClubCategories() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v1/club-categories'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List categoriesJson = data['categories'];
          return categoriesJson
              .map((json) => ClubCategory.fromJson(json))
              .toList();
        }
      }
      throw Exception('Failed to load categories');
    } catch (e) {
      print('Error fetching categories: $e');
      throw e;
    }
  }
}
