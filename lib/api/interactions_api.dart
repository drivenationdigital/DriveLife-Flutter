import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';

class CommentsResponse {
  final List<dynamic> comments;
  final bool enableGifs;
  final bool enableImages;

  CommentsResponse({
    required this.comments,
    this.enableGifs = true,
    this.enableImages = true,
  });

  factory CommentsResponse.empty() => CommentsResponse(comments: const []);
}

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

 static Future<CommentsResponse> fetchComments(String postId) async {
    try {
      final user = await _auth.getUser();
      if (user == null) return CommentsResponse.empty();

      final response = await http.post(
        Uri.parse('$_baseUrl/get-post-comments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': user['id'],
          'post_id': postId,
          'version': 'v3', // ← ask for the new shape
        }),
      );

      final data = jsonDecode(response.body);

      // v3 shape: { comments: [...], enable_gifs, enable_images }
      if (data is Map<String, dynamic> && data.containsKey('comments')) {
        return CommentsResponse(
          comments: (data['comments'] as List?) ?? const [],
          enableGifs: data['enable_gifs'] ?? true,
          enableImages: data['enable_images'] ?? true,
        );
      }

      // Legacy shape: bare list
      if (data is List) {
        return CommentsResponse(comments: data);
      }

      return CommentsResponse.empty();
    } catch (e) {
      print('Error fetching comments: $e');
      return CommentsResponse.empty();
    }
  }

  static Future<Map<String, dynamic>?> addComment(
    String postId,
    String comment, {
    int? parentId,
    String? gifUrl,
    String? imageUrl,
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
          'gif_url': gifUrl,
          'image_url': imageUrl,
        }),
      );

      return jsonDecode(response.body);
    } catch (e) {
      print('Error adding comment: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getCommentUploadUrl() async {
    try {
      final user = await _auth.getUser();
      final token = await _auth.getToken();
      if (user == null || token == null) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/comments/upload-url'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) return data;
    } catch (e) {
      debugPrint('getCommentUploadUrl error: $e');
    }
    return null;
  }

  static Future<bool> uploadCommentImageToCloudflare({
    required String uploadUrl,
    required File imageFile,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      final stream = http.ByteStream(imageFile.openRead());
      final length = await imageFile.length();

      request.files.add(
        http.MultipartFile(
          'file',
          stream,
          length,
          filename: imageFile.path.split('/').last,
        ),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('uploadCommentImageToCloudflare error: $e');
      return false;
    }
  }

  /// Convenience: get upload URL, upload, return the CF image ID (or null on failure)
  static Future<String?> uploadCommentImage(File file) async {
    final uploadData = await getCommentUploadUrl();
    if (uploadData == null) return null;

    final uploadUrl = uploadData['upload_url'] as String;
    final imageId = uploadData['image_id'] as String;

    final ok = await uploadCommentImageToCloudflare(
      uploadUrl: uploadUrl,
      imageFile: file,
    );

    print(ok);

    return ok ? imageId : null;
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
