// ─────────────────────────────────────────────────────────────────────────────
// stories_service.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StoryItem {
  final int storyId;
  final String imageUrl;
  final String? blurredImageUrl;
  final String username;
  final String? profileImage;
  final String timeAgo;
  final bool isSeen;
  final int seenCount; // add this

  const StoryItem({
    required this.storyId,
    required this.imageUrl,
    this.blurredImageUrl,
    required this.username,
    this.profileImage,
    this.timeAgo = '',
    this.isSeen = false,
    this.seenCount = 0, // add this
  });

  factory StoryItem.fromApi(
    Map<String, dynamic> json,
    String username,
    String? profileImage,
  ) {
    return StoryItem(
      storyId: json['story_id'] as int,
      imageUrl: json['image_url'] as String,
      blurredImageUrl: json['image_blurred_url'] as String?,
      username: username,
      profileImage: profileImage,
      timeAgo: json['time_ago'] as String? ?? '',
      isSeen: json['is_seen'] as bool? ?? false,
      seenCount: json['seen_count'] as int? ?? 0, // add this
    );
  }
}

class StoryUser {
  final int userId;
  final String username;
  final String displayName;
  final String? profileImage;
  final List<StoryItem> stories;
  bool seen; // true when all stories are seen

  StoryUser({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.stories,
    this.profileImage,
    this.seen = false,
  });

  factory StoryUser.fromApi(Map<String, dynamic> json) {
    final username = json['username'] as String;
    final profileImage = json['profile_image'] as String?;
    final storiesJson = json['stories'] as List? ?? [];

    final stories = storiesJson
        .map(
          (s) => StoryItem.fromApi(
            s as Map<String, dynamic>,
            username,
            profileImage,
          ),
        )
        .toList();

    return StoryUser(
      userId: json['user_id'] as int,
      username: username,
      displayName: json['display_name'] as String? ?? username,
      profileImage: profileImage,
      stories: stories,
      seen: json['all_seen'] as bool? ?? false,
    );
  }
}

class StoriesService {
  static const String _base = 'https://www.carevents.com/wp-json/app/v2';
  static final AuthService _authService = AuthService();

  static Future<Map<String, dynamic>?> getUploadUrl(String token) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/stories/upload-url'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) return data;
    } catch (e) {
      debugPrint('getUploadUrl error: $e');
    }
    return null;
  }

  static Future<bool> uploadImageToCloudflare({
    required String uploadUrl,
    required String imageId,
    required File imageFile,
    Function(double progress)? onProgress,
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

      onProgress?.call(0.3);

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        throw Exception('CF image upload failed: ${response.statusCode}');
      }

      onProgress?.call(1.0);
      return true;
    } catch (e) {
      debugPrint('uploadImageToCloudflare error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> createStory({
    required String token,
    required String cfImageId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/stories/create'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'cf_image_id': cfImageId}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) return data;
    } catch (e) {
      debugPrint('createStory error: $e');
    }
    return null;
  }

  static Future<bool> uploadStory({
    required String token,
    required File imageFile,
    Function(double progress)? onProgress,
  }) async {
    final uploadData = await getUploadUrl(token);
    if (uploadData == null) return false;

    final uploadUrl = uploadData['upload_url'] as String;
    final cfImageId = uploadData['image_id'] as String;

    final uploaded = await uploadImageToCloudflare(
      uploadUrl: uploadUrl,
      imageId: cfImageId,
      imageFile: imageFile,
      onProgress: onProgress,
    );
    if (!uploaded) return false;

    final story = await createStory(token: token, cfImageId: cfImageId);
    return story != null;
  }

  static Future<List<StoryUser>> getFeed() async {
    try {
      final token = await _authService.getToken();
      final res = await http.get(
        Uri.parse('$_base/stories'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] != true) return [];

      return (data['data'] as List).map((u) => StoryUser.fromApi(u)).toList();
    } catch (e) {
      debugPrint('getFeed error: $e');
      return [];
    }
  }

  // ── 5. Mark story as seen ─────────────────────────────────────────────────
  static Future<void> markSeen({required int storyId}) async {
    try {
      final token = await _authService.getToken();
      await http.post(
        Uri.parse('$_base/stories/$storyId/seen'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      debugPrint('markSeen error: $e');
    }
  }

  // ── 6. Delete story ───────────────────────────────────────────────────────
  static Future<bool> deleteStory({
    required int storyId,
  }) async {
    try {
       final token = await _authService.getToken();
      final res = await http.delete(
        Uri.parse('$_base/stories/$storyId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (e) {
      debugPrint('deleteStory error: $e');
      return false;
    }
  }
}
