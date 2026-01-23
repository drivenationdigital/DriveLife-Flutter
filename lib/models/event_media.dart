import 'dart:io';

class ImageData {
  final File? file; // Make nullable for remote images
  final String base64;
  final String mimeType;
  final String extension;
  bool isUploaded;
  final String? remoteUrl; // Add for uploaded images
  final String? remoteId; // Add for deleting images

  ImageData({
    this.file,
    required this.base64,
    required this.mimeType,
    required this.extension,
    this.isUploaded = false,
    this.remoteUrl,
    this.remoteId,
  });

  // Factory for creating from remote data
  factory ImageData.fromRemote({required String url, required String id}) {
    return ImageData(
      file: null,
      base64: '', // Empty for remote images
      mimeType: 'image/jpeg',
      extension: '.jpg',
      isUploaded: true,
      remoteUrl: url,
      remoteId: id,
    );
  }

  bool get isRemote => remoteUrl != null;
}
