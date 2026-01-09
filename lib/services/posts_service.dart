import 'dart:convert';
import 'package:drivelife/models/post_model.dart';
import 'package:drivelife/services/post_cache.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PostsService {
  static const String _apiUrl = 'https://www.carevents.com/uk';
  final _storage = const FlutterSecureStorage();
  final _cache = PostCache(); // ✅ Cache instance

  /// Fetch posts for a specific user with pagination
  ///
  /// Parameters:
  /// - userId: The user's ID
  /// - page: Page number (default: 1)
  /// - limit: Items per page (default: 9)
  /// - tagged: Whether to fetch tagged posts (default: false)
  /// - forceRefresh: Whether to bypass cache (default: false)
  Future<PostsResponse?> getUserPosts({
    required int userId,
    int page = 1,
    int limit = 9,
    bool tagged = false,
    bool forceRefresh = false,
  }) async {
    try {
      final token = await _storage.read(key: 'token');

      final queryParams = {
        'user_id': userId.toString(),
        'tagged': tagged ? '1' : '0',
        'page': page.toString(),
        'limit': limit.toString(),
      };

      final uri = Uri.parse(
        '$_apiUrl/wp-json/app/v2/get-user-posts',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PostsResponse.fromJson(data);
      } else {
        print('Failed to load posts: ${response.statusCode}');
        return PostsResponse(totalPages: 0, page: 1, limit: limit, data: []);
      }
    } catch (e) {
      print('Error fetching posts: $e');
      return null;
    }
  }

  /// Fetch a single post by ID with full details
  ///
  /// This endpoint returns more detailed information including:
  /// - Author details
  /// - Like and comment counts
  /// - Whether current user has liked the post
  ///
  /// Returns raw JSON Map for compatibility with PostCard
  /// Uses 10-minute cache to reduce API calls
  Future<Map<String, dynamic>?> getPostById({
    required String postId,
    bool forceRefresh = false,
  }) async {
    // ✅ Check cache first (unless force refresh)
    if (!forceRefresh) {
      final cached = _cache.get(postId);
      if (cached != null) {
        return cached; // Return cached data
      }
    }

    // Cache miss or force refresh - fetch from API
    try {
      final token = await _storage.read(key: 'token');
      final userData = await _storage.read(key: 'user_data');

      if (userData == null) return null;

      final user = jsonDecode(userData);
      final userId = user['id'];

      final uri = Uri.parse('$_apiUrl/wp-json/app/v2/get-post').replace(
        queryParameters: {'post_id': postId, 'user_id': userId.toString()},
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

        // ✅ Store in cache
        _cache.set(postId, data);

        return data;
      } else {
        print('Failed to load post: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching post: $e');
      return null;
    }
  }

  /// Like a post
  Future<bool> likePost(String postId) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) return false;

      final uri = Uri.parse('$_apiUrl/wp-json/app/v2/like-post');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'post_id': postId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error liking post: $e');
      return false;
    }
  }

  /// Unlike a post
  Future<bool> unlikePost(String postId) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) return false;

      final uri = Uri.parse('$_apiUrl/wp-json/app/v2/unlike-post');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'post_id': postId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error unliking post: $e');
      return false;
    }
  }

  /// Delete a post
  Future<bool> deletePost(String postId) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) return false;

      final uri = Uri.parse('$_apiUrl/wp-json/app/v2/delete-post');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'post_id': postId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting post: $e');
      return false;
    }
  }
}
