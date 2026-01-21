import 'dart:io';
import 'package:drivelife/screens/create_post_screen.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/tagged_entity.dart';

enum UploadStatus { idle, uploading, processing, completed, failed }

class UploadPostData {
  final String id; // unique ID for this upload
  final List<File> mediaFiles;
  final List<bool> isVideoList;
  final String caption;
  final String? linkType;
  final String? linkUrl;
  final List<TaggedEntity> taggedUsers;
  final List<TaggedEntity> taggedVehicles;
  final List<TaggedEntity> taggedEvents;
  final int userId;

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

  Map<String, UploadPostProgress> get uploads => Map.unmodifiable(_uploads);

  bool get hasActiveUploads => _uploads.values.any(
    (upload) =>
        upload.status == UploadStatus.uploading ||
        upload.status == UploadStatus.processing,
  );

  UploadPostProgress? getUpload(String uploadId) => _uploads[uploadId];

  Future<void> startUpload(UploadPostData data) async {
    // Create initial progress
    _uploads[data.id] = UploadPostProgress(
      uploadId: data.id,
      status: UploadStatus.uploading,
      totalItems: data.mediaFiles.length,
      statusMessage: 'Preparing upload...',
    );
    notifyListeners();

    try {
      // Convert files to MediaItem format
      final mediaList = <MediaItem>[];
      for (int i = 0; i < data.mediaFiles.length; i++) {
        final file = data.mediaFiles[i];
        final isVideo = data.isVideoList[i];

        mediaList.add(
          MediaItem(
            file: file,
            isVideo: isVideo,
            height: 0, // You can get actual dimensions if needed
            width: 0,
          ),
        );
      }

      // Upload media files
      final uploadedMedia = await PostsAPI.uploadMediaFiles(
        mediaList: mediaList,
        userId: data.userId,
        onProgress: (current, total, percentage) {
          _uploads[data.id] = _uploads[data.id]!.copyWith(
            progress: percentage,
            currentItem: current + 1,
            totalItems: total,
            statusMessage: 'Uploading ${current + 1}/$total items',
          );
          notifyListeners();
        },
      );

      // Update to processing
      _uploads[data.id] = _uploads[data.id]!.copyWith(
        status: UploadStatus.processing,
        progress: 0.95,
        statusMessage: 'Creating post...',
      );
      notifyListeners();

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

      // Auto-remove failed uploads after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        _uploads.remove(data.id);
        notifyListeners();
      });
    }
  }

  void cancelUpload(String uploadId) {
    _uploads.remove(uploadId);
    notifyListeners();
  }

  void retryUpload(String uploadId) {
    // You can implement retry logic here
    _uploads.remove(uploadId);
    notifyListeners();
  }
}
