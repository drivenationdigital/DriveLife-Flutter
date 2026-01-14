import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ProfileAPI {
  static const String _baseUrl = 'https://www.carevents.com/uk';
  static const _storage = FlutterSecureStorage();

  /// Add user profile links
  static Future<Map<String, dynamic>?> addUserProfileLinks({
    required Map<String, String> link,
    required String type,
  }) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        print('No auth token found');
        return null;
      }

      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/add-profile-links');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'link': link, 'type': type}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Failed to add profile link: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error adding profile link: $e');
      return null;
    }
  }

  /// Update social links
  static Future<Map<String, dynamic>?> updateSocialLinks(
    Map<String, String> links,
  ) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        print('No auth token found');
        return null;
      }

      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/update-social-links');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'links': links}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return data;
      } else {
        print('Failed to update social links: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error updating social links: $e');
      return null;
    }
  }

  /// Remove profile link
  static Future<bool> removeProfileLink(String linkId) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        print('No auth token found');
        return false;
      }

      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/remove-profile-link');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'link_id': linkId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['error'] == null;
      }
      return false;
    } catch (e) {
      print('Error removing profile link: $e');
      return false;
    }
  }

  /// Update user details
  static Future<Map<String, dynamic>?> updateUserDetails({
    required Map<String, dynamic> details,
    bool emailChanged = false,
  }) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        print('No auth token found');
        return null;
      }

      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/update-user-details');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({...details, 'email_changed': emailChanged}),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Connection timed out');
            },
          );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Failed to update user details: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error updating user details: $e');
      rethrow;
    }
  }

  /// Upload image in chunks to Cloudflare
  static Future<Map<String, dynamic>?> _uploadImageInChunks({
    required String base64Image,
    required int userId,
    required String type, // 'profile' or 'cover'
  }) async {
    try {
      const chunkSize = 500000; // 500KB chunks

      // Remove data URL prefix to get pure base64
      final parts = base64Image.split(',');
      final base64Data = parts.length > 1 ? parts[1] : base64Image;

      // Extract extension
      final extensionMatch = RegExp(
        r'data:image/(\w+);',
      ).firstMatch(base64Image);
      final extension = extensionMatch?.group(1) ?? 'jpg';

      // Generate filename
      final fileName =
          '${type}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      // Calculate total chunks
      final totalChunks = (base64Data.length / chunkSize).ceil();

      Map<String, dynamic>? lastResponse;

      // Upload chunks sequentially
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize < base64Data.length)
            ? start + chunkSize
            : base64Data.length;
        final chunk = base64Data.substring(start, end);

        final uri = Uri.parse(
          '$_baseUrl/wp-json/app/v1/upload-media-cloudflare-chunks',
        );

        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'file_name': fileName,
            'chunk_index': i,
            'total_chunks': totalChunks,
            'chunk_data': chunk,
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data['success'] != true) {
            throw Exception(data['message'] ?? 'Chunk upload failed');
          }

          lastResponse = data;
        } else {
          throw Exception('Failed to upload chunk $i');
        }
      }

      return lastResponse;
    } catch (e) {
      print('Error uploading image in chunks: $e');
      rethrow;
    }
  }

  /// Update profile image
  static Future<Map<String, dynamic>?> updateProfileImage({
    required String base64Image,
    int? userId,
  }) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        print('No auth token found');
        return null;
      }

      // Get user ID if not provided
      int? userIdToUse = userId;
      if (userIdToUse == null) {
        // TODO: Get from UserProvider or storage
        print('User ID required');
        return null;
      }

      // Upload image in chunks
      final uploadResult = await _uploadImageInChunks(
        base64Image: base64Image,
        userId: userIdToUse,
        type: 'profile',
      );

      if (uploadResult == null ||
          uploadResult['success'] != true ||
          uploadResult['media_id'] == null) {
        throw Exception('Failed to upload image');
      }

      final mediaUrl = uploadResult['media_id'][0]['url'];

      // Save media ID to profile
      final uri = Uri.parse('$_baseUrl/wp-json/app/v2/save-profile-media-id');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': userIdToUse,
          'media_id': mediaUrl,
          'type': 'profile',
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Failed to save profile image: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error updating profile image: $e');
      rethrow;
    }
  }

  /// Update cover image
  static Future<Map<String, dynamic>?> updateCoverImage({
    required String base64Image,
    int? userId,
  }) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        print('No auth token found');
        return null;
      }

      // Get user ID if not provided
      int? userIdToUse = userId;
      if (userIdToUse == null) {
        // TODO: Get from UserProvider or storage
        print('User ID required');
        return null;
      }

      // Upload image in chunks
      final uploadResult = await _uploadImageInChunks(
        base64Image: base64Image,
        userId: userIdToUse,
        type: 'cover',
      );

      if (uploadResult == null ||
          uploadResult['success'] != true ||
          uploadResult['media_id'] == null) {
        throw Exception('Failed to upload image');
      }

      final mediaUrl = uploadResult['media_id'][0]['url'];

      // Save media ID to cover
      final uri = Uri.parse('$_baseUrl/wp-json/app/v2/save-cover-media-id');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': userIdToUse,
          'media_id': mediaUrl,
          'type': 'cover',
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Failed to save cover image: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error updating cover image: $e');
      rethrow;
    }
  }

  /// Update username
  static Future<Map<String, dynamic>?> updateUsername({
    required String username,
    int? userId,
  }) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      // Get user ID if not provided
      int? userIdToUse = userId;
      if (userIdToUse == null) {
        return {'success': false, 'message': 'User ID not provided'};
      }

      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/update-username');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'user_id': userIdToUse, 'username': username}),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Connection timed out');
            },
          );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Failed to update username: ${response.statusCode}');
        return {'success': false, 'message': 'Failed to update username'};
      }
    } catch (e) {
      print('Error updating username: $e');
      rethrow;
    }
  }

  /// Update selected content IDs
  static Future<Map<String, dynamic>?> updateContentIds({
    required List<int> contentIds,
    required int userId,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/update-selected-content');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'content_ids': contentIds}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Failed to update content IDs: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error updating content IDs: $e');
      return null;
    }
  }

  /// Update about user content IDs
  static Future<Map<String, dynamic>?> updateAboutUserIds({
    required List<int> contentIds,
    required int userId,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/update-about-content');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'content_ids': contentIds}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Failed to update about user IDs: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error updating about user IDs: $e');
      return null;
    }
  }

  /// Update password
  static Future<Map<String, dynamic>?> updatePassword({
    required String newPassword,
    required String oldPassword,
  }) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        print('No auth token found');
        return null;
      }

      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/update-password');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'new_password': newPassword,
              'old_password': oldPassword,
            }),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Connection timed out');
            },
          );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Failed to update password: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error updating password: $e');
      rethrow;
    }
  }
}
