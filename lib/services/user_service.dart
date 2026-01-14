import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UserService {
  static const String _apiUrl = 'https://www.carevents.com/uk';
  final _storage = const FlutterSecureStorage();

  /// Fetch any user's public profile by user ID or username
  Future<Map<String, dynamic>?> getUserProfile({
    int? userId,
    String? username,
  }) async {
    if (userId == null && username == null) {
      throw ArgumentError('Either userId or username must be provided');
    }

    try {
      final token = await _storage.read(key: 'token');

      // Construct query parameters
      final queryParams = <String, String>{};
      if (userId != null) queryParams['user_id'] = userId.toString();
      if (username != null && userId == null)
        queryParams['username'] = username;

      // ✅ FIXED: Use the correct endpoint
      final uri = Uri.parse(
        '$_apiUrl/wp-json/app/v2/get-user-profile-next',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      print('📥 [UserService] Response:');
      print('   Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // ✅ Handle the actual response structure
        if (data['success'] == true && data['user'] != null) {
          final user = data['user'];

          // ✅ Flatten profile_links into main object
          final profileLinks = user['profile_links'] ?? {};

          // ✅ Convert to the format expected by the app
          final formattedUser = {
            'id': _parseId(user['id']), // Convert string to int
            'username': user['username'] ?? '',
            'first_name': user['first_name'] ?? '',
            'last_name': user['last_name'] ?? '',
            'email': user['email'] ?? '',
            'profile_image': user['profile_image'] ?? '',
            'cover_image': _getCoverImage(user['cover_image']),
            'verified': user['verified'] ?? false,

            // ✅ Handle followers/following arrays
            'followers': user['followers'] ?? [],
            'following': user['following'] ?? [],
            'posts_count': _parseCount(user['posts_count']),

            'profile_links': {
              'instagram': profileLinks['instagram'] ?? '',
              'facebook': profileLinks['facebook'] ?? '',
              'tiktok': profileLinks['tiktok'] ?? '',
              'youtube': profileLinks['youtube'] ?? '',
              'mivia': profileLinks['mivia'] ?? '',
              'custodian': profileLinks['custodian'] ?? '',
              'external_links': profileLinks['external_links'] ?? [],
            },

            // Additional fields
            'email_verified': user['email_verified'] ?? false,
            'can_update_username': user['can_update_username'] ?? false,
            'last_location': user['last_location'],
            'billing_info': user['billing_info'],
          };

          return formattedUser;
        } else {
          print('   ❌ Invalid response structure');
          return null;
        }
      } else {
        print('   ❌ Failed: ${response.statusCode}');
        print('   Body: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [UserService] Error fetching user profile: $e');
      return null;
    }
  }

  // ✅ Helper: Parse ID (handle both string and int)
  int _parseId(dynamic id) {
    if (id is int) return id;
    if (id is String) return int.tryParse(id) ?? 0;
    return 0;
  }

  // ✅ Helper: Parse count (handle both string and int)
  int _parseCount(dynamic count) {
    if (count is int) return count;
    if (count is String) return int.tryParse(count) ?? 0;
    return 0;
  }

  // ✅ Helper: Get cover image (handle array or string)
  String _getCoverImage(dynamic coverImage) {
    if (coverImage is String && coverImage.isNotEmpty) {
      return coverImage;
    }
    if (coverImage is List && coverImage.isNotEmpty) {
      return coverImage[0].toString();
    }
    return '';
  }

  /// Follow a user
  Future<bool> followUser(int userId, int sessionUserId) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) return false;

      print('🔍 [UserService] Following user $userId');

      final uri = Uri.parse('$_apiUrl/wp-json/app/v1/follow-user/');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'following_id': userId,
          'follower_id': sessionUserId,
        }),
      );

      print('📥 [UserService] Follow response: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ [UserService] Error following user: $e');
      return false;
    }
  }

  /// Check if current user is following another user
  Future<bool> isFollowing(int userId) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) return false;

      final uri = Uri.parse(
        '$_apiUrl/wp-json/app/v2/is-following/?user_id=$userId',
      );

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isFollowing = data['is_following'] ?? false;
        print('📥 [UserService] Is following user $userId: $isFollowing');
        return isFollowing;
      }
      return false;
    } catch (e) {
      print('❌ [UserService] Error checking follow status: $e');
      return false;
    }
  }

  /// Get user's followers list
  Future<List<Map<String, dynamic>>> getFollowers(int userId, int page) async {
    try {
      final token = await _storage.read(key: 'token');

      final uri = Uri.parse(
        '$_apiUrl/wp-json/app/v2/get-followers/?user_id=$userId&page=$page',
      );

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['followers'] ?? []);
      }
      return [];
    } catch (e) {
      print('❌ [UserService] Error fetching followers: $e');
      return [];
    }
  }

  /// Get user's following list
  Future<List<Map<String, dynamic>>> getFollowing(int userId) async {
    try {
      final token = await _storage.read(key: 'token');

      final uri = Uri.parse(
        '$_apiUrl/wp-json/app/v2/get-following/?user_id=$userId',
      );

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['following'] ?? []);
      }
      return [];
    } catch (e) {
      print('❌ [UserService] Error fetching following: $e');
      return [];
    }
  }

  // Remove follower
  Future<bool> removeFollower(int userId) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) return false;

      final uri = Uri.parse('$_apiUrl/wp-json/app/v2/remove-follower/');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'follower_id': userId}),
      );

      print(
        '📥 [UserService] Remove follower response: ${response.statusCode}',
      );
      return response.statusCode == 200;
    } catch (e) {
      print('❌ [UserService] Error removing follower: $e');
      return false;
    }
  }

  /// Update user profile
  Future<bool> updateProfile({
    String? firstName,
    String? lastName,
    String? bio,
    String? instagram,
    String? facebook,
    String? tiktok,
    String? youtube,
  }) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) return false;

      final uri = Uri.parse('$_apiUrl/wp-json/app/v2/update-profile/');

      final body = <String, dynamic>{};
      if (firstName != null) body['first_name'] = firstName;
      if (lastName != null) body['last_name'] = lastName;
      if (bio != null) body['bio'] = bio;
      if (instagram != null) body['instagram'] = instagram;
      if (facebook != null) body['facebook'] = facebook;
      if (tiktok != null) body['tiktok'] = tiktok;
      if (youtube != null) body['youtube'] = youtube;

      print('🔍 [UserService] Updating profile: $body');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      print('📥 [UserService] Update response: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ [UserService] Error updating profile: $e');
      return false;
    }
  }
}
