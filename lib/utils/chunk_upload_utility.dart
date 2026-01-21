import 'dart:convert';
import 'package:http/http.dart' as http;

typedef ProgressCallback =
    void Function(int current, int total, double percentage);

/// Use this version if you want to show upload progress to users
class ChunkUploadUtility {
  static const String _baseUrl =
      'https://www.carevents.com/uk'; // Replace with your actual base URL
  static const int chunkSize = 500000; // 500KB chunks

  /// Parameters:
  /// - [current]: Current chunk number (0-indexed)
  /// - [total]: Total number of chunks
  /// - [percentage]: Upload percentage (0.0 to 1.0)
  /// Upload an image in chunks with progress tracking
  /// Parameters:
  /// - [base64Image]: The base64 encoded image string
  /// - [userId]: The user ID uploading the image
  /// - [type]: The type of image ('profile', 'cover', 'garage', etc.)
  /// - [onProgress]: Optional callback for upload progress updates
  static Future<Map<String, dynamic>?> uploadMediaInChunks({
    required String base64Media,
    required int userId,
    required String type,
    ProgressCallback? onProgress,
  }) async {
    try {
      // Remove data URL prefix to get pure base64
      final parts = base64Media.split(',');
      final base64Data = parts.length > 1 ? parts[1] : base64Media;

      // Extract extension from data URL (handles both image and video)
      String extension = 'jpg'; // default

      // Check for image
      final imageMatch = RegExp(r'data:image/(\w+);').firstMatch(base64Media);
      if (imageMatch != null) {
        extension = imageMatch.group(1) ?? 'jpg';
      } else {
        // Check for video
        final videoMatch = RegExp(r'data:video/(\w+);').firstMatch(base64Media);
        if (videoMatch != null) {
          extension = videoMatch.group(1) ?? 'mp4';

          // Handle special cases for video extensions
          if (extension == 'quicktime') {
            extension = 'mov';
          } else if (extension == 'x-msvideo') {
            extension = 'avi';
          } else if (extension == 'x-matroska') {
            extension = 'mkv';
          }
        }
      }

      // Generate unique filename
      final fileName =
          '${type}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      // Calculate total chunks needed
      final totalChunks = (base64Data.length / chunkSize).ceil();

      Map<String, dynamic>? lastResponse;

      print('Starting chunk upload: $totalChunks chunks for $fileName');

      // Upload chunks sequentially
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize < base64Data.length)
            ? start + chunkSize
            : base64Data.length;
        final chunk = base64Data.substring(start, end);

        final uri = Uri.parse(
          '$_baseUrl/wp-json/app/v2/upload-media-cloudflare-chunks',
        );

        // Calculate and report progress
        final percentage = (i + 1) / totalChunks;
        onProgress?.call(i, totalChunks, percentage);

        print(
          'Uploading chunk ${i + 1}/$totalChunks (${(percentage * 100).toStringAsFixed(1)}%)',
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
          throw Exception(
            'Failed to upload chunk $i: ${response.statusCode} - ${response.body}',
          );
        }
      }

      // Report 100% completion
      onProgress?.call(totalChunks, totalChunks, 1.0);

      print('Chunk upload completed successfully');
      return lastResponse;
    } catch (e) {
      print('Error uploading media in chunks: $e');
      rethrow;
    }
  }

  /// Get the media URL from the upload response
  static String? getMediaUrlFromResponse(Map<String, dynamic>? response) {
    if (response == null ||
        response['success'] != true ||
        response['media_id'] == null) {
      return null;
    }

    if (response['media_id'] is List && response['media_id'].isNotEmpty) {
      return response['media_id'][0]['url'];
    } else if (response['media_id'] is Map) {
      return response['media_id']['url'];
    }

    return null;
  }

  static String? getMediaIdFromResponse(Map<String, dynamic>? response) {
    if (response == null ||
        response['success'] != true ||
        response['media_id'] == null) {
      return null;
    }

    // Handle both array and direct object responses
    if (response['media_id'] is List && response['media_id'].isNotEmpty) {
      // Return the ID from first item in array
      final firstItem = response['media_id'][0];
      return firstItem['id']?.toString() ?? firstItem['url']?.toString();
    } else if (response['media_id'] is Map) {
      return response['media_id']['id']?.toString() ??
          response['media_id']['url']?.toString();
    } else if (response['media_id'] is String) {
      // Direct ID or URL
      return response['media_id'].toString();
    }

    return null;
  }

  /// Complete workflow: Upload image and get URL with progress tracking
  static Future<String?> uploadAndGetUrl({
    required String base64Image,
    required int userId,
    required String type,
    ProgressCallback? onProgress,
  }) async {
    try {
      final uploadResult = await uploadMediaInChunks(
        base64Media: base64Image,
        userId: userId,
        type: type,
        onProgress: onProgress,
      );

      return getMediaIdFromResponse(uploadResult);
    } catch (e) {
      print('Error in uploadAndGetUrl: $e');
      return null;
    }
  }
}
