import 'dart:io';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/search_view_model.dart';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/tag_entities_screen.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:fluttertagger/fluttertagger.dart';

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

  // Useful getters
  bool get hasValidDimensions => height > 0 && width > 0;
  double get aspectRatio => width > 0 ? height / width : 1.0;

  // Cleanup method for video controller
  void dispose() {
    videoController?.dispose();
  }

  // Copy method for immutability patterns
  MediaItem copyWith({
    File? file,
    bool? isVideo,
    num? height,
    num? width,
    VideoPlayerController? videoController,
  }) {
    return MediaItem(
      file: file ?? this.file,
      isVideo: isVideo ?? this.isVideo,
      height: height ?? this.height,
      width: width ?? this.width,
      videoController: videoController ?? this.videoController,
    );
  }
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  // final TextEditingController _captionController = TextEditingController();
  final TextEditingController _linkUrlController = TextEditingController();
  final FlutterTaggerController _captionController = FlutterTaggerController();
  final ImagePicker _picker = ImagePicker();
  final PageController _pageController = PageController();

  List<TaggedEntity> _taggedUsers = [];
  List<TaggedEntity> _taggedVehicles = [];
  List<TaggedEntity> _taggedEvents = [];

  // In _CreatePostScreenState:
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';

  List<MediaItem> _selectedMedia = [];
  int _currentPage = 0;
  bool _isPosting = false;
  String? _linkType; // 'video' or 'website'

  @override
  void dispose() {
    _captionController.dispose();
    _linkUrlController.dispose();
    _pageController.dispose();

    // Dispose video controllers
    for (var media in _selectedMedia) {
      media.videoController?.dispose();
    }

    super.dispose();
  }

  Future<void> _pickMedia() async {
    try {
      // Show dialog to choose between images and videos
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Media Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Images'),
                onTap: () => Navigator.pop(context, 'images'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Videos'),
                onTap: () => Navigator.pop(context, 'videos'),
              ),
            ],
          ),
        ),
      );

      if (choice == null) return;

      if (choice == 'images') {
        final List<XFile> images = await _picker.pickMultiImage(
          // maxWidth: 1920,
          // maxHeight: 1920,
          // imageQuality: 95,
        );

        if (images.isNotEmpty) {
          final remaining = 10 - _selectedMedia.length;
          final imagesToAdd = images.take(remaining);

          // Get dimensions for each image
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
        // Pick video
        final XFile? video = await _picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 1),
        );

        if (video != null && _selectedMedia.length < 10) {
          final file = File(video.path);
          final controller = VideoPlayerController.file(file);

          // Initialize controller to get dimensions
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

  Future<void> _addMoreMedia() async {
    // Same as _pickMedia but for adding more
    await _pickMedia();
  }

  void _removeMedia(int index) {
    final media = _selectedMedia[index];
    media.videoController?.dispose();

    setState(() {
      _selectedMedia.removeAt(index);

      // REMOVE ALL TAGS FOR THIS IMAGE
      _taggedUsers.removeWhere((tag) => tag.index == index);
      _taggedVehicles.removeWhere((tag) => tag.index == index);
      _taggedEvents.removeWhere((tag) => tag.index == index);

      // UPDATE INDICES FOR REMAINING TAGS (shift down)
      _taggedUsers = _taggedUsers.map((tag) {
        if (tag.index > index) {
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

      _taggedVehicles = _taggedVehicles.map((tag) {
        if (tag.index > index) {
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

      _taggedEvents = _taggedEvents.map((tag) {
        if (tag.index > index) {
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

      // Update carousel page if needed
      if (_currentPage >= _selectedMedia.length && _currentPage > 0) {
        _currentPage = _selectedMedia.length - 1;
        _pageController.jumpToPage(_currentPage);
      }
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _createPost() async {
    if (_selectedMedia.isEmpty) {
      _showMessage('Please select at least one image or video', isError: true);
      return;
    }

    // Validate link if provided
    if (_linkType != null && _linkUrlController.text.trim().isEmpty) {
      _showMessage('Please enter a link URL', isError: true);
      return;
    }

    // Get caption text
    String captionText = _captionController.formattedText;

    // Get all tags
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

    print('Caption: $captionText');
    print(allTags);
    print('Mentioned Users: $mentionedUsers');
    print('Mentioned Hashtags: $mentionedHashtags');

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

      // Upload media files
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

      print('Uploaded media: $uploadedMedia');

      // Create post
      final postResult = await PostsAPI.createPost(
        userId: userId,
        media: uploadedMedia,
        caption: captionText,
        location: null,
        linkType: _linkType,
        linkUrl: _linkUrlController.text.trim().isNotEmpty
            ? _linkUrlController.text.trim()
            : null,
        associationId: null, // You can add this later
        associationType: null, // You can add this later
      );

      if (!mounted) return;

      // Add tags if any
      final allTags = [..._taggedUsers, ..._taggedVehicles, ..._taggedEvents];

      if (allTags.isNotEmpty && postResult['post_id'] != null) {
        setState(() {
          _uploadStatus = 'Adding tags...';
        });

        await PostsAPI.addTagsForPost(
          userId: userId,
          postId: int.parse(postResult['post_id'].toString()),
          tags: allTags,
        );
      }

      if (!mounted) return;

      _showMessage('Post created successfully!');

      // Navigate back
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

  Widget _buildCarousel() {
    if (_selectedMedia.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        // Large Preview Carousel
        SizedBox(
          height: 400,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemCount: _selectedMedia.length,
            itemBuilder: (context, index) {
              final media = _selectedMedia[index];

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Image or Video Preview
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
                              child: CircularProgressIndicator(),
                            ),
                          )
                  else
                    Image.file(media.file, fit: BoxFit.contain),

                  // Play/Pause button for videos
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
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            media.videoController!.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                    ),

                  // Remove button
                  Positioned(
                    top: 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: () => _removeMedia(index),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  // Media type badge
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            media.isVideo ? Icons.videocam : Icons.image,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            media.isVideo ? 'Video' : 'Image',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
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

        // Page Indicators
        if (_selectedMedia.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _selectedMedia.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _selectedMedia.length + 1,
        itemBuilder: (context, index) {
          // Add more button
          if (index == _selectedMedia.length) {
            if (_selectedMedia.length >= 10) {
              return const SizedBox.shrink();
            }
            return GestureDetector(
              onTap: _addMoreMedia,
              child: Container(
                width: 80,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: Colors.grey.shade600, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Add',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
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
            child: Container(
              width: 80,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFAE9159)
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
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
                                          Icons.play_circle_outline,
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
                                      Icons.videocam,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                )
                        : Image.file(media.file, fit: BoxFit.cover),
                  ),

                  // Number badge
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
                        borderRadius: BorderRadius.circular(4),
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
        backgroundColor: theme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Create Post',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isPosting ? null : _createPost,
            child: _isPosting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : Text(
                    'Post',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
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
                // Large Carousel Preview
                _buildCarousel(),

                // Thumbnail Strip
                _buildThumbnails(),

                // Add Media Button (when no media selected)
                if (_selectedMedia.isEmpty && _selectedMedia.length < 10)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: GestureDetector(
                      onTap: _pickMedia,
                      child: Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Add Photos or Videos',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to select up to 10 items',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),
                const Divider(height: 1),

                // Caption Input
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Caption',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
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
                        //characters that can trigger a search and the styles
                        //to be applied to their tagged results in the TextField
                        triggerCharacterAndStyles: {
                          '@': TextStyle(color: theme.primaryColor),
                          '#': TextStyle(color: theme.primaryColor),
                        },
                        //this will cause the onSearch callback to be invoked
                        //immediately a trigger character is detected.
                        //The default behaviour defers the onSearch invocation
                        //until a searchable character has been entered after
                        //the trigger character.
                        triggerStrategy: TriggerStrategy.eager,
                        tagTextFormatter: (id, tag, triggerCharacter) =>
                            '$triggerCharacter$id#$tag#',
                        overlayHeight: 200,
                        overlay: SearchResultOverlay(
                          tagController: _captionController,
                          animation: const AlwaysStoppedAnimation(Offset.zero),
                        ),
                        builder: (context, textFieldKey) {
                          //return a TextField and pass it `textFieldKey`
                          return TextField(
                            key: textFieldKey,
                            controller: _captionController,
                            maxLines: 5,
                            maxLength: 2000,
                            decoration: InputDecoration(
                              hintText: 'Write a caption...',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Add Post Link Section
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add a Post Link',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "If you'd like to link a website/video to your post, add it here",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Link Type Dropdown
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonFormField<String>(
                          value: _linkType,
                          decoration: InputDecoration(
                            hintText: 'Link Type',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: InputBorder.none,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'video',
                              child: Text('Video'),
                            ),
                            DropdownMenuItem(
                              value: 'website',
                              child: Text('Website / Link'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _linkType = value;
                            });
                          },
                        ),
                      ),

                      // Link URL Input (shows when link type is selected)
                      if (_linkType != null) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _linkUrlController,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            hintText: 'Enter link',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFFAE9159),
                              ),
                            ),
                            prefixIcon: Icon(
                              _linkType == 'video'
                                  ? Icons.videocam
                                  : Icons.link,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Additional Options
                ListTile(
                  leading: const Icon(Icons.location_on),
                  title: const Text('Add Location'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _showMessage('Coming soon');
                  },
                ),

                const Divider(height: 1),

                // Replace existing ListTiles with:
                ListTile(
                  leading: const Icon(Icons.people),
                  title: Row(
                    children: [
                      const Text('Tag People'),
                      if (_taggedUsers.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFAE9159),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_taggedUsers.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
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
                          onTagsUpdated: (tags) {
                            // Store tags
                            setState(() {
                              // You'll need to add this variable: List<TaggedEntity> _taggedUsers = [];
                              _taggedUsers = tags;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),

                const Divider(height: 1),

                ListTile(
                  leading: const Icon(Icons.directions_car),
                  title: Row(
                    children: [
                      const Text('Tag Vehicles'),
                      if (_taggedVehicles.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFAE9159),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_taggedVehicles.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
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
                          onTagsUpdated: (tags) {
                            setState(() {
                              _taggedVehicles = tags;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),

                const Divider(height: 1),

                ListTile(
                  leading: const Icon(Icons.event),
                  title: Row(
                    children: [
                      const Text('Tag Events'),
                      if (_taggedEvents.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFAE9159),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_taggedEvents.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
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
                          onTagsUpdated: (tags) {
                            setState(() {
                              _taggedEvents = tags;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),

          // Upload progress overlay
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          value: _uploadProgress,
                          strokeWidth: 6,
                          backgroundColor: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${(_uploadProgress * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _uploadStatus,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: _uploadProgress,
                          backgroundColor: Colors.grey[300],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class UserListView extends StatelessWidget {
  const UserListView({
    Key? key,
    required this.tagController,
    required this.animation,
  }) : super(key: key);

  final FlutterTaggerController tagController;
  final Animation<Offset> animation;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: captionSearchViewModel.users,
      builder: (_, users, __) {
        if (users.isEmpty) {
          return ValueListenableBuilder<bool>(
            valueListenable: captionSearchViewModel.loading,
            builder: (_, loading, __) {
              if (loading) {
                return Container(
                  height: 200,
                  color: theme.backgroundColor,
                  child: Center(
                    child: CircularProgressIndicator(color: theme.primaryColor),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          );
        }

        return Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final profileImage = user['image'];

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundImage:
                      profileImage != null && profileImage != 'search_q'
                      ? NetworkImage(profileImage)
                      : null,
                  backgroundColor: Colors.grey.shade300,
                  child: profileImage == null || profileImage == 'search_q'
                      ? const Icon(Icons.person, size: 16)
                      : null,
                ),
                title: Text(
                  user['name'] ?? 'Unknown',
                  style: const TextStyle(fontSize: 14),
                ),
                onTap: () {
                  // Add the user tag to the caption
                  tagController.addTag(
                    id: user['entity_id'].toString(),
                    name: user['name'] ?? 'Unknown',
                  );
                  // Clear search results after selection
                  captionSearchViewModel.users.value = [];
                  captionSearchViewModel.activeView.value =
                      SearchResultView.none;
                },
              );
            },
          ),
        );
      },
    );
  }
}

class HashtagListView extends StatelessWidget {
  const HashtagListView({
    Key? key,
    required this.tagController,
    required this.animation,
  }) : super(key: key);

  final FlutterTaggerController tagController;
  final Animation<Offset> animation;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return ValueListenableBuilder<List<String>>(
      valueListenable: captionSearchViewModel.hashtags,
      builder: (_, hashtags, __) {
        if (hashtags.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: hashtags.length,
            itemBuilder: (context, index) {
              final hashtag = hashtags[index];

              return ListTile(
                dense: true,
                leading: Icon(Icons.tag, color: theme.primaryColor, size: 20),
                title: Text(
                  hashtag,
                  style: TextStyle(fontSize: 16, color: theme.primaryColor),
                ),
                onTap: () {
                  tagController.addTag(id: hashtag, name: hashtag);
                  captionSearchViewModel.hashtags.value = [];
                  captionSearchViewModel.activeView.value =
                      SearchResultView.none;
                },
              );
            },
          ),
        );
      },
    );
  }
}

class SearchResultOverlay extends StatelessWidget {
  const SearchResultOverlay({
    Key? key,
    required this.tagController,
    required this.animation,
  }) : super(key: key);

  final FlutterTaggerController tagController;
  final Animation<Offset> animation;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SearchResultView>(
      valueListenable: captionSearchViewModel.activeView,
      builder: (_, view, __) {
        if (view == SearchResultView.users) {
          return UserListView(
            tagController: tagController,
            animation: animation,
          );
        }
        if (view == SearchResultView.hashtag) {
          return HashtagListView(
            tagController: tagController,
            animation: animation,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
