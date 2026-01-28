import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/search_view_model.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/search_user.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertagger/fluttertagger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

class EditPostScreen extends StatefulWidget {
  final Map<String, dynamic> post;

  const EditPostScreen({super.key, required this.post});

  @override
  State<EditPostScreen> createState() => _EditPostScreenState();
}

class MediaDisplayItem {
  final String url;
  final bool isVideo;
  final String? width;
  final String? height;
  VideoPlayerController? videoController;

  MediaDisplayItem({
    required this.url,
    required this.isVideo,
    this.width,
    this.height,
    this.videoController,
  });

  void dispose() {
    videoController?.dispose();
  }
}

class _EditPostScreenState extends State<EditPostScreen> {
  final TextEditingController _linkUrlController = TextEditingController();
  final FlutterTaggerController _captionController = FlutterTaggerController();
  final PageController _pageController = PageController();

  List<MediaDisplayItem> _mediaItems = [];
  int _currentPage = 0;
  bool _isSaving = false;
  String? _linkType;

  @override
  void initState() {
    super.initState();
    _loadPostData();
  }

  void _loadPostData() {
    // Load caption
    final caption = widget.post['caption']?.toString() ?? '';
    _captionController.text = caption;

    // Load link data
    final linkType = widget.post['asc_link_type'];
    _linkType = (linkType == null || linkType == '')
        ? null
        : linkType.toString();
    _linkUrlController.text = widget.post['asc_link']?.toString() ?? '';

    // Load media
    final mediaList = widget.post['media'] as List<dynamic>? ?? [];
    _mediaItems = mediaList.map((media) {
      final isVideo = media['media_type'] == 'video';
      final url = media['media_url']?.toString() ?? '';

      final item = MediaDisplayItem(
        url: url,
        isVideo: isVideo,
        width: media['media_width']?.toString(),
        height: media['media_height']?.toString(),
      );

      // Initialize video controller if it's a video
      if (isVideo && url.isNotEmpty) {
        item.videoController = VideoPlayerController.networkUrl(Uri.parse(url))
          ..initialize().then((_) {
            if (mounted) setState(() {});
          });
      }

      return item;
    }).toList();

    setState(() {});
  }

  @override
  void dispose() {
    _captionController.dispose();
    _linkUrlController.dispose();
    _pageController.dispose();
    for (var media in _mediaItems) {
      media.dispose();
    }
    super.dispose();
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

  Future<void> _savePost() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;

    if (user == null) {
      _showMessage('User not found', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = int.parse(user['id'].toString());
      final postId = widget.post['id'].toString();

      final Map<String, dynamic> data = {
        'post_id': postId,
        'caption': _captionController.formattedText,
      };

      // Add link data if link type is selected
      if (_linkType != null && _linkType!.isNotEmpty) {
        data['asc_link_type'] = _linkType!;
        data['asc_link'] = _linkUrlController.text.trim();
      } else {
        // Clear link data if no link type selected
        data['asc_link_type'] = null;
        data['asc_link'] = null;
      }

      final response = await PostsAPI.updatePost(userId: userId, data: data);

      if (mounted) {
        if (response != null && response['success'] == true) {
          // _showMessage('Post updated successfully');
          setState(() => _isSaving = false);
          Navigator.pop(context, true);
        } else {
          _showMessage(
            response?['message'] ?? 'Failed to update post',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Failed to update post: $e', isError: true);
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildCarousel() {
    if (_mediaItems.isEmpty) return const SizedBox.shrink();

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
            itemCount: _mediaItems.length,
            itemBuilder: (context, index) {
              final media = _mediaItems[index];

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
                    CachedNetworkImage(
                      imageUrl: media.url,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFAE9159),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.error, color: Colors.red),
                      ),
                    ),

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
        if (_mediaItems.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _mediaItems.length,
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
    if (_mediaItems.isEmpty || _mediaItems.length <= 1) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 100,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _mediaItems.length,
        itemBuilder: (context, index) {
          final media = _mediaItems[index];
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
                        : CachedNetworkImage(
                            imageUrl: media.url,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: Colors.grey.shade200),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.error, size: 20),
                            ),
                          ),
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
          'Edit Post',
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
              onPressed: _isSaving ? null : _savePost,
              style: TextButton.styleFrom(
                backgroundColor: _isSaving
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
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildCarousel(),
            _buildThumbnails(),
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
                            borderSide: BorderSide(color: Colors.grey.shade200),
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
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
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
                      onChanged: (value) => setState(() => _linkType = value),
                    ),
                  ),

                  if (_linkType != null && _linkType!.isNotEmpty) ...[
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
                          borderSide: BorderSide(color: Colors.grey.shade200),
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

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
