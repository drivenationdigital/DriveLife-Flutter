import 'dart:convert';
import 'package:http/http.dart' as http;

class PostsAPI {
  static const String _baseUrl = 'https://www.carevents.com/uk';

  static Future<List<dynamic>> getPosts({
    required String token,
    required int userId,
    int page = 1,
    int limit = 10,
    int followingOnly = 0,
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/wp-json/app/v2/get-posts?user_id=$userId&following_only=$followingOnly&page=$page&limit=$limit',
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
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      } else {
        print('Failed to fetch posts: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching posts: $e');
    }

    return [];
  }

  static Future<Map<String, dynamic>?> getPostById(
    String id,
    String userId,
  ) async {
    try {
      final uri = Uri.parse('$_baseUrl/get-post?post_id=$id&user_id=$userId');
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'];
      } else {
        print('Failed to load post: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching post: $e');
      return null;
    }
  }
}
