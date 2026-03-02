import 'dart:convert';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:drivelife/screens/create-post/create_post_screen.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/utils/chunk_upload_utility.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:tus_client_dart/tus_client_dart.dart';
import 'package:cross_file/cross_file.dart' show XFile;

class PostsAPI {
  static const String _baseUrl = 'https://www.carevents.com/uk';
  static const _storage = FlutterSecureStorage();
  static final AuthService _authService = AuthService();

  static Future<List<dynamic>> getPosts({
    required String token,
    required int userId,
    int page = 1,
    int limit = 10,
    int followingOnly = 0,
    int newsOnly = 0,
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/wp-json/app/v2/get-posts?user_id=$userId&following_only=$followingOnly&news_only=$newsOnly&page=$page&limit=$limit',
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

  static Future<List<Map<String, dynamic>>> fetchTaggableEntities({
    required String search,
    required String entityType,
    required List<TaggedEntity> taggedEntities,
  }) async {
    String endpoint;

    switch (entityType) {
      case 'car':
        endpoint = '/wp-json/app/v1/get-taggable-vehicles';
        break;
      case 'events':
        endpoint = '/wp-json/app/v1/get-taggable-events';
        break;
      case 'users':
      default:
        endpoint = '/wp-json/app/v1/get-taggable-entities';
        break;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'search': search,
          'user_id': 'USER_ID', // Get from your auth
          'tagged_entities': taggedEntities.map((e) => e.toJson()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error fetching taggable entities: $e');
      return [];
    }
  }

  static Future<String?> _uploadVideoToCloudflare(
    XFile videoFile, {
    Function(double progress)? onProgress,
  }) async {
    try {
      final user = await _authService.getParentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final fileSize = await videoFile.length();
      print(
        'Uploading video: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB',
      );

      // ── Step 1: Get direct upload URL from your server ──────
      final fileName =
          'video_${user['id']}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      // Base64 encode the filename for TUS metadata
      final fileNameB64 = base64Encode(utf8.encode(fileName));

      final urlResponse = await http.post(
        Uri.parse(
          'https://www.carevents.com/uk/wp-json/app/v2/create-stream-upload',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'file_size': fileSize,
          'file_name': fileName, // ← send to server too
        }),
      );
      if (urlResponse.statusCode != 200) {
        throw Exception('Failed to get upload URL: ${urlResponse.statusCode}');
      }

      final urlData = jsonDecode(urlResponse.body);
      final uploadUrl = urlData['upload_url'] as String;
      final streamId = urlData['stream_id'] as String;

      print('Got CF upload URL, stream ID: $streamId');

      // ── Step 2: Upload directly to Cloudflare via TUS ───────
      final client = TusClient(
        videoFile,
        store: TusMemoryStore(),
        maxChunkSize: 5 * 1024 * 1024, // 5MB chunks — TUS handles resuming
      );

      await client.upload(
        uri: Uri.parse(uploadUrl),
        headers: {},
        onProgress: (double progress, Duration eta) {
          // ↓ TUS gives bytes uploaded, we convert to 0.0–1.0 for easier UI handling
          final realProgress = progress / 100;
          final clamped = realProgress.clamp(0.0, 1.0);

          print(
            'Video upload: ${(clamped * 100).toStringAsFixed(1)}% | ETA: ${eta.inSeconds}s',
          );
          onProgress?.call(clamped); 
        },
        onComplete: () {
          onProgress?.call(100); // ← ensure 100% is always reported
          print('Video upload complete: $streamId');
        },
      );

      return streamId; // ← return CF stream ID, same as before
    } catch (e) {
      print('Error uploading video to Cloudflare: $e');
      rethrow;
    }
  }

  /// Upload media files using chunk upload utility
  static Future<List<Map<String, dynamic>>> uploadMediaFiles({
    required List<MediaItem> mediaList,
    required int userId,
    Function(int current, int total, double percentage)? onProgress,
  }) async {
    final uploadedMedia = <Map<String, dynamic>>[];

    for (int i = 0; i < mediaList.length; i++) {
      final media = mediaList[i];

      try {
        String? mediaId;

        if (media.isVideo) {
          // ↓ Direct TUS upload to Cloudflare — no base64, no WordPress middleman
          mediaId = await _uploadVideoToCloudflare(
            XFile(media.file.path),
            onProgress: (progress) {
              final overall = (i + progress) / mediaList.length;
              onProgress?.call(i, mediaList.length, overall);
            },
          );
        } else {
          // Images stay on existing chunk upload (already working fine)
          final bytes = await media.file.readAsBytes();
          final base64String = base64Encode(bytes);
          final extension = media.file.path.split('.').last.toLowerCase();
          final mimeType = _getMimeType(extension, false);
          final base64Image = 'data:$mimeType;base64,$base64String';

          mediaId = await ChunkUploadUtility.uploadAndGetUrl(
            base64Image: base64Image,
            userId: userId,
            type: 'post',
            onProgress: (current, total, percentage) {
              final overall = (i + percentage) / mediaList.length;
              onProgress?.call(i, mediaList.length, overall);
            },
          );
        }

        if (mediaId != null) {
          uploadedMedia.add({
            'url': mediaId,
            'type': media.isVideo ? 'video' : 'image',
            'mime': _getMimeType(
              media.file.path.split('.').last.toLowerCase(),
              media.isVideo,
            ),
            'height': media.height,
            'width': media.width,
            'server': 'cloudflare',
          });
        }
      } catch (e) {
        print('Error uploading media $i: $e');
        throw Exception('Failed to upload media ${i + 1}');
      }
    }

    return uploadedMedia;
  }

  static String _getMimeType(String extension, bool isVideo) {
    if (isVideo) {
      switch (extension) {
        case 'mp4':
          return 'video/mp4';
        case 'mov':
          return 'video/quicktime';
        case 'avi':
          return 'video/x-msvideo';
        default:
          return 'video/mp4';
      }
    } else {
      switch (extension) {
        case 'jpg':
        case 'jpeg':
          return 'image/jpeg';
        case 'png':
          return 'image/png';
        case 'gif':
          return 'image/gif';
        case 'webp':
          return 'image/webp';
        default:
          return 'image/jpeg';
      }
    }
  }

  /// Create post
  static Future<Map<String, dynamic>> createPost({
    required int userId,
    required List<Map<String, dynamic>> media,
    required String caption,
    String? location,
    String? linkType,
    String? linkUrl,
    dynamic associationId,
    String? associationType,
    List<Map<String, dynamic>>? mentionedUsers,
    List<Map<String, dynamic>>? mentionedHashtags,
    String? newsContent, // Add news content parameter
  }) async {
    try {
      final body = {
        'user_id': userId.toString(),
        'caption': caption,
        'location': location ?? '',
        'media': json.encode(media),
      };

      if (linkType != null && linkUrl != null) {
        body['asc_link_type'] = linkType;
        body['asc_link'] = linkUrl;
      }

      if (newsContent != null) {
        body['news_content'] = newsContent;
      }

      if (associationId != null && associationType != null) {
        if (associationType != 'car') {
          body['association_id'] = associationId.toString();
          body['association_type'] = associationType;
        }
      }

      if (mentionedUsers != null && mentionedUsers.isNotEmpty) {
        body['mentioned_users'] = json.encode(mentionedUsers);
      }

      if (mentionedHashtags != null && mentionedHashtags.isNotEmpty) {
        body['mentioned_hashtags'] = json.encode(mentionedHashtags);
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/wp-json/app/v1/create-post'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        if (data['error'] != null) {
          throw Exception(data['error']);
        }
        return data;
      } else {
        throw Exception('Failed to create post: ${response.statusCode}');
      }
    } catch (e) {
      print('Error creating post: $e');
      rethrow;
    }
  }

  /// Add tags to post
  static Future<Map<String, dynamic>?> addTagsForPost({
    required int userId,
    required int postId,
    required List<TaggedEntity> tags,
  }) async {
    try {
      final tagsJson = tags
          .map(
            (tag) => {
              'x': tag.x ?? 0.5,
              'y': tag.y ?? 0.5,
              'index': tag.index,
              'label': tag.label,
              'type': tag.type,
              'id': tag.id,
            },
          )
          .toList();

      final response = await http.post(
        Uri.parse('$_baseUrl/wp-json/app/v1/add-tags'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId,
          'post_id': postId,
          'tags': tagsJson,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error adding tags: $e');
      return null;
    }
  }

  /// Delete post
  static Future<bool> deletePost({
    required String postId,
    required String userId,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('No auth token found');
        return false;
      }

      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/delete-post');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'user_id': userId, 'post_id': postId}),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print('Failed to delete post: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error deleting post: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> updatePost({
    required int userId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/wp-json/app/v1/edit-post');

      final body = {'user_id': userId, ...data};

      print('Updating post with data: $body');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData;
      } else {
        print('Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error updating post: $e');
      return null;
    }
  }
}
