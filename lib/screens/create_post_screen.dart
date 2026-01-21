import 'dart:async';
import 'dart:io';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/search_view_model.dart';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/search_user.dart';
import 'package:drivelife/screens/tag_entities_screen.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:fluttertagger/fluttertagger.dart';
import 'package:video_compress/video_compress.dart';
import 'package:rxdart/rxdart.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class MediaItem {
  final File file;
  final bool isVideo;
  final num height;
  final num width;
  VideoPlayerController? videoController;

  MediaItem({
    required this.file,
    required this.isVideo,
    this.height = 0,
    this.width = 0,
    this.videoController,
  });

  void dispose() {
    videoController?.dispose();
  }
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _linkUrlController = TextEditingController();
  final FlutterTaggerController _captionController = FlutterTaggerController();
  final ImagePicker _picker = ImagePicker();
  final PageController _pageController = PageController();
  Subscription? _compressSubscription;

  List<TaggedEntity> _taggedUsers = [];
  List<TaggedEntity> _taggedVehicles = [];
  List<TaggedEntity> _taggedEvents = [];

  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';

  List<MediaItem> _selectedMedia = [];
  int _currentPage = 0;
  bool _isPosting = false;
  String? _linkType;

  @override
  void initState() {
    super.initState();

    // Update this section 👇
    _compressSubscription = VideoCompress.compressProgress$.subscribe((
      progress,
    ) {
      if (mounted) {
        setState(() {
          _uploadProgress = progress / 100;
          _uploadStatus = 'Compressing video: ${progress.toInt()}%';
        });
      }
    });
  }

  @override
  void dispose() {
    _captionController.dispose();
    _linkUrlController.dispose();
    _pageController.dispose();

    // Add these lines 👇
    _compressSubscription?.unsubscribe();
    _compressSubscription = null;

    VideoCompress.cancelCompression();
    for (var media in _selectedMedia) {
      media.dispose();
    }
    super.dispose();
  }

  Future<File?> _compressVideo(File videoFile) async {
    try {
      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
        _uploadStatus = 'Compressing video...';
      });

      final info = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality
            .Res1280x720Quality, // Change to Medium for better audio
        deleteOrigin: false,
        includeAudio: true,
        // Add these parameters 👇
        frameRate: 60,
        // videoBitrate: 2500000, // 2.5 Mbps
        // audioBitrate: 128000, // 128 kbps - ensures audio quality
      );

      if (info != null && info.file != null) {
        return info.file!;
      }
      return null;
    } catch (e) {
      print('Error compressing video: $e');
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
          _uploadStatus = '';
        });
      }
    }
  }

  Future<void> _pickMedia() async {
    try {
      final choice = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Select Media Type',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              _MediaTypeCard(
                icon: Icons.photo_library_rounded,
                title: 'Images',
                subtitle: 'Select from gallery',
                onTap: () => Navigator.pop(context, 'images'),
              ),
              const SizedBox(height: 12),
              _MediaTypeCard(
                icon: Icons.videocam_rounded,
                title: 'Videos',
                subtitle: 'Will be compressed for faster upload',
                onTap: () => Navigator.pop(context, 'videos'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );

      if (choice == null) return;

      if (choice == 'images') {
        final List<XFile> images = await _picker.pickMultiImage();

        if (images.isNotEmpty) {
          final remaining = 10 - _selectedMedia.length;
          final imagesToAdd = images.take(remaining);

          final List<MediaItem> mediaItems = [];
          for (final image in imagesToAdd) {
            final file = File(image.path);
            final decodedImage = await decodeImageFromList(
              await file.readAsBytes(),
            );

            mediaItems.add(
              MediaItem(
                file: file,
                isVideo: false,
                height: decodedImage.height,
                width: decodedImage.width,
              ),
            );
          }

          setState(() {
            _selectedMedia.addAll(mediaItems);
          });

          if (images.length > remaining) {
            _showMessage('Maximum 10 items allowed');
          }
        }
      } else {
        final XFile? video = await _picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 1),
        );

        if (video != null && _selectedMedia.length < 10) {
          File file = File(video.path);

          // Compress video
          final compressedFile = await _compressVideo(file);
          if (compressedFile != null) {
            file = compressedFile;
          }

          final controller = VideoPlayerController.file(file);
          await controller.initialize();

          final mediaItem = MediaItem(
            file: file,
            isVideo: true,
            height: controller.value.size.height,
            width: controller.value.size.width,
            videoController: controller,
          );

          if (mounted) {
            setState(() {
              _selectedMedia.add(mediaItem);
            });
          }
        } else if (_selectedMedia.length >= 10) {
          _showMessage('Maximum 10 items allowed');
        }
      }
    } catch (e) {
      print('Error picking media: $e');
      _showMessage('Failed to pick media: $e', isError: true);
    }
  }

  void _removeMedia(int index) {
    final media = _selectedMedia[index];
    media.dispose();

    setState(() {
      _selectedMedia.removeAt(index);

      _taggedUsers.removeWhere((tag) => tag.index == index);
      _taggedVehicles.removeWhere((tag) => tag.index == index);
      _taggedEvents.removeWhere((tag) => tag.index == index);

      _taggedUsers = _updateTagIndices(_taggedUsers, index);
      _taggedVehicles = _updateTagIndices(_taggedVehicles, index);
      _taggedEvents = _updateTagIndices(_taggedEvents, index);

      if (_currentPage >= _selectedMedia.length && _currentPage > 0) {
        _currentPage = _selectedMedia.length - 1;
        _pageController.jumpToPage(_currentPage);
      }
    });
  }

  List<TaggedEntity> _updateTagIndices(
    List<TaggedEntity> tags,
    int removedIndex,
  ) {
    return tags.map((tag) {
      if (tag.index > removedIndex) {
        return TaggedEntity(
          index: tag.index - 1,
          id: tag.id,
          type: tag.type,
          label: tag.label,
          x: tag.x,
          y: tag.y,
        );
      }
      return tag;
    }).toList();
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _createPostLegacy() async {
    if (_selectedMedia.isEmpty) {
      _showMessage('Please select at least one image or video', isError: true);
      return;
    }

    if (_linkType != null && _linkUrlController.text.trim().isEmpty) {
      _showMessage('Please enter a link URL', isError: true);
      return;
    }

    String captionText = _captionController.formattedText;
    final allTags = _captionController.tags;

    final mentionedUsers = <Map<String, dynamic>>[];
    final mentionedHashtags = <Map<String, dynamic>>[];

    for (final tag in allTags) {
      if (tag.triggerCharacter == '@') {
        mentionedUsers.add({
          'entity_id': tag.id,
          'entity_type': 'user',
          'text': tag.text,
        });
      } else if (tag.triggerCharacter == '#') {
        mentionedHashtags.add({
          'entity_id': tag.id,
          'entity_type': 'hashtag',
          'text': tag.text,
        });
      }
    }

    setState(() {
      _isPosting = true;
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadStatus = 'Uploading media...';
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user == null) {
        throw Exception('User not found');
      }

      final userId = int.parse(user['id'].toString());

      final uploadedMedia = await PostsAPI.uploadMediaFiles(
        mediaList: _selectedMedia,
        userId: userId,
        onProgress: (current, total, percentage) {
          if (mounted) {
            setState(() {
              _uploadProgress = percentage;
              _uploadStatus = 'Uploading ${current + 1}/$total items';
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _uploadStatus = 'Creating post...';
        _uploadProgress = 0.95;
      });

      final postResult = await PostsAPI.createPost(
        userId: userId,
        media: uploadedMedia,
        caption: captionText,
        location: null,
        linkType: _linkType,
        linkUrl: _linkUrlController.text.trim().isNotEmpty
            ? _linkUrlController.text.trim()
            : null,
        associationId: null,
        associationType: null,
      );

      if (!mounted) return;

      final allEntityTags = [
        ..._taggedUsers,
        ..._taggedVehicles,
        ..._taggedEvents,
      ];

      if (allEntityTags.isNotEmpty && postResult['post_id'] != null) {
        setState(() {
          _uploadStatus = 'Adding tags...';
        });

        await PostsAPI.addTagsForPost(
          userId: userId,
          postId: int.parse(postResult['post_id'].toString()),
          tags: allEntityTags,
        );
      }

      if (!mounted) return;

      _showMessage('Post created successfully!');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to create post: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isPosting = false;
          _isUploading = false;
          _uploadProgress = 0.0;
          _uploadStatus = '';
        });
      }
    }
  }

  // Modify the _createPost method in create_post_screen.dart

  Future<void> _createPost() async {
    if (_selectedMedia.isEmpty) {
      _showMessage('Please select at least one image or video', isError: true);
      return;
    }

    if (_linkType != null && _linkUrlController.text.trim().isEmpty) {
      _showMessage('Please enter a link URL', isError: true);
      return;
    }

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;

    if (user == null) {
      _showMessage('User not found', isError: true);
      return;
    }

    final userId = int.parse(user['id'].toString());

    // Generate unique upload ID
    final uploadId = 'upload_${DateTime.now().millisecondsSinceEpoch}';

    final allTags = _captionController.tags;

    final mentionedUsers = <Map<String, dynamic>>[];
    final mentionedHashtags = <Map<String, dynamic>>[];

    for (final tag in allTags) {
      if (tag.triggerCharacter == '@') {
        mentionedUsers.add({
          'entity_id': tag.id,
          'entity_type': 'user',
          'text': tag.text,
        });
      } else if (tag.triggerCharacter == '#') {
        mentionedHashtags.add({
          'entity_id': tag.id,
          'entity_type': 'hashtag',
          'text': tag.text,
        });
      }
    }

    // Prepare upload data
    final uploadData = UploadPostData(
      id: uploadId,
      mediaFiles: _selectedMedia.map((m) => m.file).toList(),
      isVideoList: _selectedMedia.map((m) => m.isVideo).toList(),
      caption: _captionController.formattedText,
      linkType: _linkType,
      linkUrl: _linkUrlController.text.trim().isNotEmpty
          ? _linkUrlController.text.trim()
          : null,
      taggedUsers: _taggedUsers,
      taggedVehicles: _taggedVehicles,
      taggedEvents: _taggedEvents,
      userId: userId,
      mentionedHashtags: mentionedHashtags,
      mentionedUsers: mentionedUsers,
    );

    // Start background upload
    if (mounted) {
      Provider.of<UploadPostProvider>(
        context,
        listen: false,
      ).startUpload(uploadData);
    }

    // Close screen immediately
    if (mounted) {
      Navigator.pop(context, true);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Uploading post in background...'),
          backgroundColor: const Color(0xFFAE9159),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildCarousel() {
    if (_selectedMedia.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Container(
          height: 400,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: _selectedMedia.length,
            itemBuilder: (context, index) {
              final media = _selectedMedia[index];

              return Stack(
                fit: StackFit.expand,
                children: [
                  if (media.isVideo)
                    media.videoController != null &&
                            media.videoController!.value.isInitialized
                        ? GestureDetector(
                            onTap: () {
                              setState(() {
                                if (media.videoController!.value.isPlaying) {
                                  media.videoController!.pause();
                                } else {
                                  media.videoController!.play();
                                }
                              });
                            },
                            child: AspectRatio(
                              aspectRatio:
                                  media.videoController!.value.aspectRatio,
                              child: VideoPlayer(media.videoController!),
                            ),
                          )
                        : Container(
                            color: Colors.black,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFFAE9159),
                              ),
                            ),
                          )
                  else
                    Image.file(media.file, fit: BoxFit.contain),

                  if (media.isVideo &&
                      media.videoController != null &&
                      media.videoController!.value.isInitialized)
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            if (media.videoController!.value.isPlaying) {
                              media.videoController!.pause();
                            } else {
                              media.videoController!.play();
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            media.videoController!.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ),

                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => _removeMedia(index),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            media.isVideo
                                ? Icons.videocam_rounded
                                : Icons.image_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            media.isVideo ? 'Video' : 'Image',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (_selectedMedia.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _selectedMedia.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _currentPage == index
                        ? const Color(0xFFAE9159)
                        : Colors.grey.shade300,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildThumbnails() {
    if (_selectedMedia.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 100,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _selectedMedia.length + 1,
        itemBuilder: (context, index) {
          if (index == _selectedMedia.length) {
            if (_selectedMedia.length >= 10) return const SizedBox.shrink();

            return GestureDetector(
              onTap: _pickMedia,
              child: Container(
                width: 80,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFAE9159).withOpacity(0.1),
                      const Color(0xFFAE9159).withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFAE9159).withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, color: Color(0xFFAE9159), size: 32),
                    SizedBox(height: 4),
                    Text(
                      'Add More',
                      style: TextStyle(
                        color: Color(0xFFAE9159),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final media = _selectedMedia[index];
          final isSelected = _currentPage == index;

          return GestureDetector(
            onTap: () {
              _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 80,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFAE9159)
                      : Colors.transparent,
                  width: 3,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFFAE9159).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: media.isVideo
                        ? media.videoController != null &&
                                  media.videoController!.value.isInitialized
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    VideoPlayer(media.videoController!),
                                    Container(
                                      color: Colors.black.withOpacity(0.3),
                                      child: const Center(
                                        child: Icon(
                                          Icons.play_circle_outline_rounded,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Container(
                                  color: Colors.black,
                                  child: const Center(
                                    child: Icon(
                                      Icons.videocam_rounded,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                )
                        : Image.file(media.file, fit: BoxFit.cover),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Create Post',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isPosting ? null : _createPost,
              style: TextButton.styleFrom(
                backgroundColor: _isPosting
                    ? Colors.grey.shade300
                    : const Color(0xFFAE9159),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: _isPosting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Post',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                _buildCarousel(),
                _buildThumbnails(),

                if (_selectedMedia.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: GestureDetector(
                      onTap: _pickMedia,
                      child: Container(
                        width: double.infinity,
                        height: 220,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.primaryColor.withOpacity(0.05),
                              theme.primaryColor.withOpacity(0.02),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.primaryColor.withOpacity(0.2),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.add_photo_alternate_rounded,
                                size: 48,
                                color: theme.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Add Photos or Videos',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to select up to 10 items',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Videos will be compressed automatically',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Caption',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FlutterTagger(
                        controller: _captionController,
                        onSearch: (query, triggerCharacter) {
                          if (triggerCharacter == "@") {
                            captionSearchViewModel.searchUser(query);
                          }
                          if (triggerCharacter == "#") {
                            captionSearchViewModel.searchHashtag(query);
                          }
                        },
                        triggerCharacterAndStyles: {
                          '@': TextStyle(
                            color: theme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                          '#': TextStyle(
                            color: theme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        },
                        triggerStrategy: TriggerStrategy.eager,
                        tagTextFormatter: (id, tag, triggerCharacter) =>
                            '$triggerCharacter$id#$tag#',
                        overlayHeight: 200,
                        overlay: SearchResultOverlay(
                          tagController: _captionController,
                          animation: const AlwaysStoppedAnimation(Offset.zero),
                        ),
                        builder: (context, textFieldKey) {
                          return TextField(
                            key: textFieldKey,
                            controller: _captionController,
                            maxLines: 5,
                            maxLength: 2000,
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Write a caption...',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFAE9159),
                                  width: 2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.all(16),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  height: 1,
                  color: Colors.grey.shade200,
                ),
                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add a Link (Optional)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Attach a website or video link to your post',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: DropdownButtonFormField<String>(
                          value: _linkType,
                          decoration: const InputDecoration(
                            hintText: 'Select link type',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: InputBorder.none,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'video',
                              child: Row(
                                children: [
                                  Icon(Icons.videocam_rounded, size: 20),
                                  SizedBox(width: 12),
                                  Text('Video'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'website',
                              child: Row(
                                children: [
                                  Icon(Icons.link_rounded, size: 20),
                                  SizedBox(width: 12),
                                  Text('Website / Link'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _linkType = value),
                        ),
                      ),

                      if (_linkType != null) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _linkUrlController,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            hintText: 'Enter URL',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Color(0xFFAE9159),
                                width: 2,
                              ),
                            ),
                            prefixIcon: Icon(
                              _linkType == 'video'
                                  ? Icons.videocam_rounded
                                  : Icons.link_rounded,
                              color: const Color(0xFFAE9159),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                _OptionTile(
                  icon: Icons.people_rounded,
                  title: 'Tag People',
                  count: _taggedUsers.length,
                  onTap: () async {
                    if (_selectedMedia.isEmpty) {
                      _showMessage('Please add media first', isError: true);
                      return;
                    }

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TagEntitiesScreen(
                          media: _selectedMedia,
                          entityType: 'users',
                          existingTags: _taggedUsers,
                          onTagsUpdated: (tags) =>
                              setState(() => _taggedUsers = tags),
                        ),
                      ),
                    );
                  },
                ),

                _OptionTile(
                  icon: Icons.directions_car_rounded,
                  title: 'Tag Vehicles',
                  count: _taggedVehicles.length,
                  onTap: () async {
                    if (_selectedMedia.isEmpty) {
                      _showMessage('Please add media first', isError: true);
                      return;
                    }

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TagEntitiesScreen(
                          media: _selectedMedia,
                          entityType: 'car',
                          existingTags: _taggedVehicles,
                          onTagsUpdated: (tags) =>
                              setState(() => _taggedVehicles = tags),
                        ),
                      ),
                    );
                  },
                ),

                _OptionTile(
                  icon: Icons.event_rounded,
                  title: 'Tag Events',
                  count: _taggedEvents.length,
                  onTap: () async {
                    if (_selectedMedia.isEmpty) {
                      _showMessage('Please add media first', isError: true);
                      return;
                    }

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TagEntitiesScreen(
                          media: _selectedMedia,
                          entityType: 'events',
                          existingTags: _taggedEvents,
                          onTagsUpdated: (tags) =>
                              setState(() => _taggedEvents = tags),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 80),
              ],
            ),
          ),

          if (_isUploading)
            Container(
              color: Colors.black87,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(32),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(
                          value: _uploadProgress,
                          strokeWidth: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFAE9159),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '${(_uploadProgress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _uploadStatus,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _uploadProgress,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFAE9159),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MediaTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFAE9159).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFFAE9159)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFAE9159).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFFAE9159), size: 22),
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            if (count > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFAE9159),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
