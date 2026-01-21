import 'dart:io';
import 'package:drivelife/screens/create_post_screen.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:video_player/video_player.dart';

enum UploadStatus { idle, uploading, processing, completed, failed }

class UploadPostData {
  final String id;
  final List<File> mediaFiles;
  final List<bool> isVideoList;
  final String caption;
  final String? linkType;
  final String? linkUrl;
  final List<TaggedEntity> taggedUsers;
  final List<TaggedEntity> taggedVehicles;
  final List<TaggedEntity> taggedEvents;
  final int userId;
  final List<Map<String, dynamic>> mentionedUsers;
  final List<Map<String, dynamic>> mentionedHashtags;

  UploadPostData({
    required this.id,
    required this.mediaFiles,
    required this.isVideoList,
    required this.caption,
    this.linkType,
    this.linkUrl,
    required this.taggedUsers,
    required this.taggedVehicles,
    required this.taggedEvents,
    required this.userId,
    this.mentionedUsers = const [],
    this.mentionedHashtags = const [],
  });
}

class UploadPostProgress {
  final String uploadId;
  final UploadStatus status;
  final double progress;
  final String statusMessage;
  final int currentItem;
  final int totalItems;
  final String? error;
  final Map<String, dynamic>? result;

  UploadPostProgress({
    required this.uploadId,
    required this.status,
    this.progress = 0.0,
    this.statusMessage = '',
    this.currentItem = 0,
    this.totalItems = 0,
    this.error,
    this.result,
  });

  UploadPostProgress copyWith({
    UploadStatus? status,
    double? progress,
    String? statusMessage,
    int? currentItem,
    int? totalItems,
    String? error,
    Map<String, dynamic>? result,
  }) {
    return UploadPostProgress(
      uploadId: uploadId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      currentItem: currentItem ?? this.currentItem,
      totalItems: totalItems ?? this.totalItems,
      error: error ?? this.error,
      result: result ?? this.result,
    );
  }
}

class UploadPostProvider with ChangeNotifier {
  final Map<String, UploadPostProgress> _uploads = {};
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Map<String, UploadPostProgress> get uploads => Map.unmodifiable(_uploads);

  bool get hasActiveUploads => _uploads.values.any(
    (upload) =>
        upload.status == UploadStatus.uploading ||
        upload.status == UploadStatus.processing,
  );

  UploadPostProgress? getUpload(String uploadId) => _uploads[uploadId];

  // Initialize notifications
  Future<void> initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(initSettings);
  }

  // Show progress notification
  Future<void> _showProgressNotification(
    String uploadId,
    int progress,
    String message,
  ) async {
    final androidDetails = AndroidNotificationDetails(
      'upload_channel',
      'Upload Progress',
      channelDescription: 'Shows upload progress for posts',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      ongoing: true,
      autoCancel: false,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      uploadId.hashCode,
      'Uploading Post',
      message,
      details,
    );
  }

  // Show completion notification
  Future<void> _showCompletionNotification(
    String uploadId,
    bool success,
    String message,
    String? postId,
  ) async {
    final androidDetails = AndroidNotificationDetails(
      'upload_complete_channel',
      'Upload Complete',
      channelDescription: 'Notifies when upload is complete',
      importance: Importance.high,
      priority: Priority.high,
      showProgress: false,
      ongoing: false,
      autoCancel: true,
      actions: postId != null
          ? [
              AndroidNotificationAction(
                'view_post',
                'View Post',
                showsUserInterface: true,
              ),
            ]
          : [],
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'post_complete', // Add this for iOS actions
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Pass postId in payload so we can navigate to it 👇
    await _notificationsPlugin.show(
      uploadId.hashCode,
      success ? '✅ Upload Complete' : '❌ Upload Failed',
      message,
      details,
      payload: postId != null ? 'post:$postId' : null,
    );
  }

  // Cancel notification
  Future<void> _cancelNotification(String uploadId) async {
    await _notificationsPlugin.cancel(uploadId.hashCode);
  }

  // Get dimensions for media
  Future<Map<String, int>> _getMediaDimensions(File file, bool isVideo) async {
    if (isVideo) {
      try {
        final controller = VideoPlayerController.file(file);
        await controller.initialize();
        final width = controller.value.size.width.toInt();
        final height = controller.value.size.height.toInt();
        controller.dispose();
        return {'width': width, 'height': height};
      } catch (e) {
        print('Error getting video dimensions: $e');
        return {'width': 1920, 'height': 1080}; // Default
      }
    } else {
      try {
        final bytes = await file.readAsBytes();
        final image = await decodeImageFromList(bytes);
        return {'width': image.width, 'height': image.height};
      } catch (e) {
        print('Error getting image dimensions: $e');
        return {'width': 1080, 'height': 1080}; // Default
      }
    }
  }

  Future<void> startUpload(UploadPostData data) async {
    // Initialize notifications
    await initializeNotifications();

    // Create initial progress
    _uploads[data.id] = UploadPostProgress(
      uploadId: data.id,
      status: UploadStatus.uploading,
      totalItems: data.mediaFiles.length,
      statusMessage: 'Preparing upload...',
    );
    notifyListeners();

    // Show initial notification
    await _showProgressNotification(data.id, 0, 'Preparing upload...');

    try {
      // Convert files to MediaItem format with dimensions
      final mediaList = <MediaItem>[];
      for (int i = 0; i < data.mediaFiles.length; i++) {
        final file = data.mediaFiles[i];
        final isVideo = data.isVideoList[i];

        // Get actual dimensions
        final dimensions = await _getMediaDimensions(file, isVideo);

        mediaList.add(
          MediaItem(
            file: file,
            isVideo: isVideo,
            height: dimensions['height'] ?? 0,
            width: dimensions['width'] ?? 0,
          ),
        );
      }

      // Upload media files
      final uploadedMedia = await PostsAPI.uploadMediaFiles(
        mediaList: mediaList,
        userId: data.userId,
        onProgress: (current, total, percentage) {
          final progress = (percentage * 100).toInt();
          final message = 'Uploading ${current + 1}/$total items';

          _uploads[data.id] = _uploads[data.id]!.copyWith(
            progress: percentage,
            currentItem: current + 1,
            totalItems: total,
            statusMessage: message,
          );
          notifyListeners();

          // Update notification
          _showProgressNotification(data.id, progress, message);
        },
      );

      // Update to processing
      _uploads[data.id] = _uploads[data.id]!.copyWith(
        status: UploadStatus.processing,
        progress: 0.95,
        statusMessage: 'Creating post...',
      );
      notifyListeners();

      await _showProgressNotification(data.id, 95, 'Creating post...');

      // Create post
      final postResult = await PostsAPI.createPost(
        userId: data.userId,
        media: uploadedMedia,
        caption: data.caption,
        location: null,
        linkType: data.linkType,
        linkUrl: data.linkUrl,
        associationId: null,
        associationType: null,
        mentionedUsers: data.mentionedUsers,
        mentionedHashtags: data.mentionedHashtags,
      );

      // Add tags if any
      final allTags = [
        ...data.taggedUsers,
        ...data.taggedVehicles,
        ...data.taggedEvents,
      ];

      if (allTags.isNotEmpty && postResult['post_id'] != null) {
        _uploads[data.id] = _uploads[data.id]!.copyWith(
          statusMessage: 'Adding tags...',
        );
        notifyListeners();

        await PostsAPI.addTagsForPost(
          userId: data.userId,
          postId: int.parse(postResult['post_id'].toString()),
          tags: allTags,
        );
      }

      // Mark as completed
      _uploads[data.id] = _uploads[data.id]!.copyWith(
        status: UploadStatus.completed,
        progress: 1.0,
        statusMessage: 'Post created successfully!',
        result: postResult,
      );
      notifyListeners();

      // Show completion notification
      await _cancelNotification(data.id);
      await _showCompletionNotification(
        data.id,
        true,
        'Your post has been published successfully!',
        postResult['post_id']?.toString(),
      );

      // Auto-remove after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        _uploads.remove(data.id);
        notifyListeners();
      });
    } catch (e) {
      _uploads[data.id] = _uploads[data.id]!.copyWith(
        status: UploadStatus.failed,
        error: e.toString(),
        statusMessage: 'Failed to create post',
      );
      notifyListeners();

      // Show error notification
      await _cancelNotification(data.id);
      await _showCompletionNotification(
        data.id,
        false,
        'Failed to upload post: ${e.toString()}',
        null,
      );

      // Auto-remove failed uploads after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        _uploads.remove(data.id);
        notifyListeners();
      });
    }
  }

  void cancelUpload(String uploadId) {
    _cancelNotification(uploadId);
    _uploads.remove(uploadId);
    notifyListeners();
  }

  void retryUpload(String uploadId) {
    _cancelNotification(uploadId);
    _uploads.remove(uploadId);
    notifyListeners();
  }
}
