import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';

class InteractionsAPI {
  static const String _baseUrl = 'https://www.carevents.com/uk/wp-json/app/v1';
  static final AuthService _auth = AuthService();

  static Future<Map<String, dynamic>?> maybeLikePost(String postId) async {
    try {
      final user = await _auth.getUser();
      final token = await _auth.getToken();
      if (user == null || token == null) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/toggle-like-post'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': user['id'], 'post_id': postId}),
      );

      return jsonDecode(response.body);
    } catch (e) {
      print('Error liking post: $e');
      return null;
    }
  }

  static Future<List<dynamic>> fetchComments(String postId) async {
    try {
      final user = await _auth.getUser();
      if (user == null) return [];

      final response = await http.post(
        Uri.parse('$_baseUrl/get-post-comments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': user['id'], 'post_id': postId}),
      );

      final data = jsonDecode(response.body);
      print(data);
      return data;
    } catch (e) {
      print('Error fetching comments: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> addComment(
    String postId,
    String comment, {
    int? parentId,
  }) async {
    try {
      final user = await _auth.getUser();
      if (user == null) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/add-post-comment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': user['id'],
          'post_id': postId,
          'comment': comment,
          'parent_id': parentId,
        }),
      );

      return jsonDecode(response.body);
    } catch (e) {
      print('Error adding comment: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> deleteComment(String commentId) async {
    try {
      final user = await _auth.getUser();
      if (user == null) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/delete-post-comment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': user['id'], 'comment_id': commentId}),
      );

      return jsonDecode(response.body);
    } catch (e) {
      print('Error deleting comment: $e');
      return null;
    }
  }

  static Future<void> markPostShared(int postId) async {
    try {
      final user = await _auth.getUser();
      if (user == null) return;

      await http.post(
        Uri.parse('$_baseUrl/mark-post-shared'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': user['id'], 'post_id': postId}),
      );
    } catch (e) {
      print('Error marking post shared: $e');
    }
  }

  static Future<Map<String, dynamic>?> maybeLikeComment(
    String commentId,
    String ownerId,
  ) async {
    try {
      final user = await _auth.getUser();
      if (user == null) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/toggle-like-comment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': user['id'],
          'comment_id': commentId,
          'owner_id': ownerId,
        }),
      );

      return jsonDecode(response.body);
    } catch (e) {
      print('Error liking comment: $e');
      return null;
    }
  }
}
