import 'dart:convert';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:drivelife/screens/create-post/create_post_screen.dart';
import 'package:drivelife/utils/chunk_upload_utility.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class PostsAPI {
  static const String _baseUrl = 'https://www.carevents.com/uk';
  static const _storage = FlutterSecureStorage();

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
        // Convert file to base64
        final bytes = await media.file.readAsBytes();
        final base64String = base64Encode(bytes);

        // Get mime type
        final extension = media.file.path.split('.').last.toLowerCase();
        final mimeType = _getMimeType(extension, media.isVideo);
        final base64Image = 'data:$mimeType;base64,$base64String';

        // Upload using chunk utility
        final mediaId = await ChunkUploadUtility.uploadAndGetUrl(
          base64Image: base64Image,
          userId: userId,
          type: 'post',
          onProgress: (current, total, percentage) {
            // Calculate overall progress
            final overallProgress = (i + percentage) / mediaList.length;
            onProgress?.call(i, mediaList.length, overallProgress);
          },
        );

        if (mediaId != null) {
          uploadedMedia.add({
            'url': mediaId,
            'type': media.isVideo ? 'video' : 'image',
            'mime': mimeType,
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
    int? associationId,
    String? associationType,
    List<Map<String, dynamic>>? mentionedUsers,
    List<Map<String, dynamic>>? mentionedHashtags,
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
      final token = await _storage.read(key: 'token');
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
}
