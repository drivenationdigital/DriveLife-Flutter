import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:drivelife/models/event_media.dart';

class ChunkedFileUploader {
  final String apiUrl;

  ChunkedFileUploader({required this.apiUrl});

  Future<bool> uploadFileInChunks({
    required String entityId, // Changed from eventId
    required ImageData imageData,
    int chunkSize = 1024 * 600,
    required Function(double progress) onProgress,
    String mediaGroup = 'gallery',
    required String uploadType, // ✅ ADD THIS - 'event' or 'venue'
  }) async {
    try {
      final base64Data = imageData.base64;
      final totalChunks = (base64Data.length / chunkSize).ceil();

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}${imageData.extension}';

      bool uploadSuccess = false;

      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize > base64Data.length)
            ? base64Data.length
            : start + chunkSize;

        String base64Chunk;
        if (i == totalChunks - 1) {
          base64Chunk = base64Data.substring(start);
        } else {
          base64Chunk = base64Data.substring(start, end);
        }

        // ✅ CHANGE THIS - Dynamic endpoint based on uploadType
        final endpoint = uploadType == 'venue'
            ? '/wp-json/app/v2/update-venue-images-cloudflare'
            : '/wp-json/app/v2/update-event-images-cloudflare';

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$apiUrl$endpoint'),
        );

        // ✅ CHANGE THIS - Dynamic field name based on uploadType
        final idFieldName = uploadType == 'venue' ? 'venue_id' : 'event_id';
        request.fields[idFieldName] = entityId;
        request.fields['media_group'] = mediaGroup;
        request.fields['file_name'] = fileName;
        request.fields['chunk_index'] = i.toString();
        request.fields['total_chunks'] = totalChunks.toString();
        request.fields['chunk_data'] = base64Chunk;

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data['success'] != true) {
            throw Exception(
              'Chunk upload failed at index $i: ${data['message']}',
            );
          }

          uploadSuccess = true;
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }

        final progress = ((i + 1) / totalChunks) * 100;
        onProgress(progress);
      }

      return uploadSuccess;
    } catch (error) {
      print('Error uploading file in chunks: $error');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateEventImages({
    required String eventId,
    required List<ImageData> mediaList,
    String mediaGroup = 'gallery',
    int chunkSize = 1024 * 600,
    Function(double progress)? onOverallProgress,
  }) async {
    try {
      if (mediaList.isEmpty) {
        return {'success': true, 'message': 'No files to upload'};
      }

      int totalChunks = 0;
      for (var imageData in mediaList) {
        final fileChunks = (imageData.base64.length / chunkSize).ceil();
        totalChunks += fileChunks;
      }

      int completedChunks = 0;

      final uploadFutures = mediaList.map((imageData) async {
        return await uploadFileInChunks(
          entityId: eventId,
          imageData: imageData,
          chunkSize: chunkSize,
          mediaGroup: mediaGroup,
          uploadType: 'event', // ✅ ADD THIS
          onProgress: (fileProgress) {
            if (onOverallProgress != null) {
              final fileChunks = (imageData.base64.length / chunkSize).ceil();
              final fileChunksCompleted = (fileProgress / 100 * fileChunks)
                  .round();

              final overallProgress =
                  ((completedChunks + fileChunksCompleted) / totalChunks) * 100;
              onOverallProgress(overallProgress.clamp(0, 100));
            }
          },
        );
      }).toList();

      final results = await Future.wait(uploadFutures);

      if (results.contains(false)) {
        throw Exception('Failed to upload all files');
      }

      return {'success': true, 'message': 'All files uploaded successfully'};
    } catch (error) {
      print('Error uploading files to Cloudflare: $error');
      rethrow;
    }
  }

  /// ✅ ADD THIS NEW METHOD
  /// Upload multiple venue images with overall progress tracking
  Future<Map<String, dynamic>> updateVenueImages({
    required String venueId,
    required List<ImageData> mediaList,
    String mediaGroup = 'gallery',
    int chunkSize = 1024 * 600,
    Function(double progress)? onOverallProgress,
  }) async {
    try {
      if (mediaList.isEmpty) {
        return {'success': true, 'message': 'No files to upload'};
      }

      int totalChunks = 0;
      for (var imageData in mediaList) {
        final fileChunks = (imageData.base64.length / chunkSize).ceil();
        totalChunks += fileChunks;
      }

      int completedChunks = 0;

      final uploadFutures = mediaList.map((imageData) async {
        return await uploadFileInChunks(
          entityId: venueId,
          imageData: imageData,
          chunkSize: chunkSize,
          mediaGroup: mediaGroup,
          uploadType: 'venue', // ✅ Use 'venue' type
          onProgress: (fileProgress) {
            if (onOverallProgress != null) {
              final fileChunks = (imageData.base64.length / chunkSize).ceil();
              final fileChunksCompleted = (fileProgress / 100 * fileChunks)
                  .round();

              final overallProgress =
                  ((completedChunks + fileChunksCompleted) / totalChunks) * 100;
              onOverallProgress(overallProgress.clamp(0, 100));
            }
          },
        );
      }).toList();

      final results = await Future.wait(uploadFutures);

      if (results.contains(false)) {
        throw Exception('Failed to upload all files');
      }

      return {'success': true, 'message': 'All files uploaded successfully'};
    } catch (error) {
      print('Error uploading venue files to Cloudflare: $error');
      rethrow;
    }
  }
}
