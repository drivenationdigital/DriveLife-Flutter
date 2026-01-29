import 'dart:io';
import 'dart:convert';
import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';

class EditProfileImagesScreen extends StatefulWidget {
  const EditProfileImagesScreen({super.key});

  @override
  State<EditProfileImagesScreen> createState() =>
      _EditProfileImagesScreenState();
}

class _EditProfileImagesScreenState extends State<EditProfileImagesScreen> {
  File? _profileImage;
  File? _coverImage;
  String? _currentProfileImageUrl;
  String? _currentCoverImageUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  void _loadImages() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user != null) {
      setState(() {
        _currentProfileImageUrl = user.profileImage;
        _currentCoverImageUrl = user.coverImage;
      });
    }
  }

  Future<void> _pickImage(bool isProfile, ThemeProvider theme) async {
    final source = await _showImageSourceDialog(theme);
    if (source == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );

    if (pickedFile != null) {
      setState(() {
        if (isProfile) {
          _profileImage = File(pickedFile.path);
        } else {
          _coverImage = File(pickedFile.path);
        }
      });
    }
  }

  Future<ImageSource?> _showImageSourceDialog(ThemeProvider theme) async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        title: const Text(
          'Upload Image',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library, color: theme.primaryColor),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt, color: theme.primaryColor),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  /// Convert image file to base64 string
  Future<String> _fileToBase64(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);

      // Get file extension
      final extension = file.path.split('.').last.toLowerCase();

      // Create data URL with proper MIME type
      final mimeType = _getMimeType(extension);
      return 'data:$mimeType;base64,$base64String';
    } catch (e) {
      print('Error converting file to base64: $e');
      rethrow;
    }
  }

  String _getMimeType(String extension) {
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

  Future<void> _saveImages() async {
    if (_profileImage == null && _coverImage == null) {
      _showError('No changes to save');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user == null) {
        throw Exception('User not found');
      }

      final userId = user.id;

      // Upload profile image
      if (_profileImage != null) {
        print('🖼️ Uploading profile image...');

        final base64Image = await _fileToBase64(_profileImage!);

        final result = await ProfileAPI.updateProfileImage(
          base64Image: base64Image,
          userId: userId,
        );

        if (result == null || result['success'] != true) {
          throw Exception(
            result?['message'] ?? 'Failed to upload profile image',
          );
        }

        print('✅ Profile image uploaded successfully');
      }

      // Upload cover image
      if (_coverImage != null) {
        print('🖼️ Uploading cover image...');

        final base64Image = await _fileToBase64(_coverImage!);

        final result = await ProfileAPI.updateCoverImage(
          base64Image: base64Image,
          userId: userId,
        );

        if (result == null || result['success'] != true) {
          throw Exception(result?['message'] ?? 'Failed to upload cover image');
        }

        print('✅ Cover image uploaded successfully');
      }

      // Reload user data to get updated image URLs
      await userProvider.loadUser();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Images updated successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Wait a bit to show the success message
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      print('❌ Error saving images: $e');

      if (!mounted) return;

      String errorMessage = 'Failed to update images';
      if (e.toString().contains('timed out')) {
        errorMessage = 'Upload timed out. Please try again.';
      } else if (e is Exception) {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveImages,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info text
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap on an image to change it. Images will be uploaded when you press Save.',
                    style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Profile Image
          const Text(
            'Profile Image',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          _buildImagePicker(
            isProfile: true,
            currentImage: _profileImage,
            currentUrl: _currentProfileImageUrl,
            theme: theme,
          ),
          const SizedBox(height: 32),

          // Cover Image
          const Text(
            'Cover Image',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          _buildImagePicker(
            isProfile: false,
            currentImage: _coverImage,
            currentUrl: _currentCoverImageUrl,
            theme: theme,
          ),

          const SizedBox(height: 24),

          // Upload progress indicator
          if (_isSaving)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    'Uploading images...',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImagePicker({
    required bool isProfile,
    required File? currentImage,
    required String? currentUrl,
    required ThemeProvider theme,
  }) {
    return GestureDetector(
      onTap: _isSaving ? null : () => _pickImage(isProfile, theme),
      child: Container(
        height: isProfile ? 200 : 200,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Show selected image or current URL
            if (currentImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(currentImage, fit: BoxFit.cover),
              )
            else if (currentUrl != null && currentUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  currentUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => _buildPlaceholder(isProfile),
                ),
              )
            else
              _buildPlaceholder(isProfile),

            // Overlay with camera icon
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black.withOpacity(0.3),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.camera_alt, color: Colors.white, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      currentImage != null || (currentUrl?.isNotEmpty ?? false)
                          ? 'Tap to change'
                          : 'Tap to add',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // "Changed" indicator
            if (currentImage != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Changed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(bool isProfile) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isProfile ? Icons.person : Icons.image,
            size: 60,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 8),
          Text(
            isProfile ? 'No Profile Image' : 'No Cover Image',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
