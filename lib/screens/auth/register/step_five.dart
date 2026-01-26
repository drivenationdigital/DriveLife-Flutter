import 'dart:convert';

import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/providers/registration_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class RegisterStepFiveScreen extends StatefulWidget {
  const RegisterStepFiveScreen({Key? key}) : super(key: key);

  @override
  State<RegisterStepFiveScreen> createState() => _RegisterStepFiveScreenState();
}

class _RegisterStepFiveScreenState extends State<RegisterStepFiveScreen> {
  File? _profileImage;
  File? _coverImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(bool isProfile) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final source = await _showImageSourceDialog(themeProvider);
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

  Future<void> _completeRegistration({required bool uploadImages}) async {
    final registrationProvider = Provider.of<RegistrationProvider>(
      context,
      listen: false,
    );

    setState(() => registrationProvider.setLoading(true));

    try {
      // Upload images if user didn't skip
      if (uploadImages) {
        // if no profile or cover image selected, throw error
        if (_profileImage == null && _coverImage == null) {
          throw Exception('Please select at least one image to upload');
        }

        // Upload profile image
        if (_profileImage != null) {
          print('🖼️ Uploading profile image...');
          final base64Image = await _fileToBase64(_profileImage!);

          final result = await ProfileAPI.updateProfileImage(
            base64Image: base64Image,
            userId: registrationProvider.userId!,
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
            userId: registrationProvider.userId!,
          );

          if (result == null || result['success'] != true) {
            throw Exception(
              result?['message'] ?? 'Failed to upload cover image',
            );
          }
          print('✅ Cover image uploaded successfully');
        }
      }

      // Login the user
      print('🔐 Logging in user...');
      final authService = AuthService();

      final success = await authService
          .login(registrationProvider.email, registrationProvider.password)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Login request timed out');
            },
          );

      if (!mounted) return;

      if (!success) {
        throw Exception('Login failed after registration');
      }

      print('✅ Login successful, loading user...');

      // Load user into provider
      await context.read<UserProvider>().loadUser().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⏱️ User load timed out');
        },
      );

      print('✅ User loaded, registration complete');

      if (!mounted) return;

      // Clear registration data
      registrationProvider.reset();

      // Navigate to home
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } catch (e) {
      print('❌ Error completing registration: $e');

      if (!mounted) return;

      String errorMessage = 'Failed to complete registration';
      if (e.toString().contains('timed out')) {
        errorMessage = 'Request timed out. Please try logging in manually.';
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
        registrationProvider.setLoading(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        appBar: AppBar(
          backgroundColor: isDark ? Colors.black : Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false, // Remove back button
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Consumer<RegistrationProvider>(
              builder: (context, registrationProvider, child) {
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 20),
                            Text(
                              'Your Profile',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Set your profile images',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 60),

                            // Profile Image
                            Text(
                              'Profile Image',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: () => _pickImage(true),
                              child: Container(
                                width: double.infinity,
                                height: 160,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.grey[900]
                                      : Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.grey[800]!
                                        : Colors.grey[300]!,
                                    width: 2,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: _profileImage != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.file(
                                          _profileImage!,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.cloud_upload_outlined,
                                            size: 48,
                                            color: isDark
                                                ? Colors.grey[600]
                                                : Colors.grey[400],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Tap to Upload',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: isDark
                                                  ? Colors.grey[500]
                                                  : Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(height: 40),

                            // Cover Image
                            Text(
                              'Cover Image',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: () => _pickImage(false),
                              child: Container(
                                width: double.infinity,
                                height: 160,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.grey[900]
                                      : Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.grey[800]!
                                        : Colors.grey[300]!,
                                    width: 2,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: _coverImage != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.file(
                                          _coverImage!,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.cloud_upload_outlined,
                                            size: 48,
                                            color: isDark
                                                ? Colors.grey[600]
                                                : Colors.grey[400],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Tap to Upload',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: isDark
                                                  ? Colors.grey[500]
                                                  : Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Next Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: registrationProvider.isLoading
                            ? null
                            : () => _completeRegistration(uploadImages: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB8966B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                          disabledBackgroundColor: Colors.grey,
                        ),
                        child: registrationProvider.isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'NEXT',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Skip Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton(
                        onPressed: registrationProvider.isLoading
                            ? null
                            : () => _completeRegistration(uploadImages: false),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isDark
                              ? Colors.grey[900]
                              : Colors.grey[800],
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'SKIP',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ); // WillPopScope closing
  }
}
