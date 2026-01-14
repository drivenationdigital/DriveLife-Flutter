import 'dart:io';
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
  final ImagePicker _picker = ImagePicker();
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
        _currentProfileImageUrl = user['profile_image'];
        _currentCoverImageUrl = user['cover_image'];
      });
    }
  }

  Future<void> _pickImage(bool isProfile) async {
    try {
      final source = await _showImageSourceDialog();
      if (source == null) return;

      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          if (isProfile) {
            _profileImage = File(image.path);
          } else {
            _coverImage = File(image.path);
          }
        });
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Select Image Source',
          style: TextStyle(color: Colors.black),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveImages() async {
    if (_profileImage == null && _coverImage == null) {
      _showError('No changes to save');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // TODO: Upload images to server and update user profile
      // Example:
      // if (_profileImage != null) {
      //   await uploadProfileImage(_profileImage!);
      // }
      // if (_coverImage != null) {
      //   await uploadCoverImage(_coverImage!);
      // }

      await Future.delayed(const Duration(seconds: 2)); // Simulate upload

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Images updated successfully'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update images: $e'),
          backgroundColor: Colors.red,
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
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker({
    required bool isProfile,
    required File? currentImage,
    required String? currentUrl,
  }) {
    return GestureDetector(
      onTap: () => _pickImage(isProfile),
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
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 40,
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
