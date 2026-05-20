import 'dart:async';
import 'dart:io';
import 'package:drivelife/models/search_view_model.dart';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/search_user.dart';
import 'package:drivelife/screens/create-post/tag_entities_screen.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:fluttertagger/fluttertagger.dart';
import 'package:video_compress/video_compress.dart';
import 'package:google_places_flutter/google_places_flutter.dart';

enum MediaPickerMode { images, videos, ask }

class MediaItem {
  final File file;
  final bool isVideo;
  final num height;
  final num width;
  final Duration? duration;
  VideoPlayerController? videoController;

  MediaItem({
    required this.file,
    required this.isVideo,
    this.height = 0,
    this.width = 0,
    this.duration,
    this.videoController,
  });

  void dispose() {
    videoController?.dispose();
  }
}

class CreatePostScreen extends StatefulWidget {
  final String? associationId;
  final String? associationType;
  final String? associationLabel;

  const CreatePostScreen({
    super.key,
    this.associationId,
    this.associationType,
    this.associationLabel,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
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
  Map<String, dynamic>? _associatedEntity;

  String? _activeHashtagQuery;
  bool _processingTag = false;

  // Tagged location
  String? _taggedLocationName;
  double? _taggedLat;
  double? _taggedLng;

  // Controller for the location sheet (lives across opens)
  final TextEditingController _locationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _captionController.addListener(_autoFormatHashtags);

    print(
      'CreatePostScreen initialized with association: '
      'id=${widget.associationId}, '
      'type=${widget.associationType}, '
      'label=${widget.associationLabel}',
    );

    // Set the associated entity from constructor params
    if (widget.associationId != null && widget.associationType != null) {
      _associatedEntity = {
        'id': widget.associationId,
        'type': widget.associationType,
        'label': widget.associationLabel,
      };
    }

    // Update this section 👇
    _compressSubscription = VideoCompress.compressProgress$.subscribe((
      progress,
    ) {
      if (mounted) {
        setState(() {
          _uploadProgress = progress / 100;
          _uploadStatus = 'Loading video: ${progress.toInt()}%';
        });
      }
    });
  }

  @override
  void dispose() {
    _captionController.removeListener(_autoFormatHashtags);
    _captionController.dispose();
    _linkUrlController.dispose();
    _pageController.dispose();
    _locationController.dispose();

    // Add these lines 👇
    _compressSubscription?.unsubscribe();
    _compressSubscription = null;

    VideoCompress.cancelCompression();
    for (var media in _selectedMedia) {
      media.dispose();
    }
    super.dispose();
  }

  /// True when this post is being created on behalf of an entity
  /// (club or venue). Entity posts have looser requirements:
  /// media is optional, and per-media tagging (people/vehicles/events)
  /// is hidden.
  bool get _isEntityPost =>
      _associatedEntity != null &&
      (_associatedEntity!['type'] == 'club' ||
          _associatedEntity!['type'] == 'venue');

  void _autoFormatHashtags() {
    if (_processingTag) return; // block re-entry from addTag's own text update

    final text = _captionController.text;
    final cursor = _captionController.selection.baseOffset;
    if (cursor <= 0) return;

    // Only fire on space
    if (text[cursor - 1] != ' ') return;

    // Must have an active hashtag query tracked via onSearch
    if (_activeHashtagQuery == null || _activeHashtagQuery!.isEmpty) return;

    // Confirm the raw #query is actually right before the space
    final beforeCursor = text.substring(0, cursor - 1);
    if (!beforeCursor.endsWith('#$_activeHashtagQuery')) return;

    final hashtag = _activeHashtagQuery!;
    _activeHashtagQuery = null; // clear before addTag fires onSearch again

    _processingTag = true;
    _captionController.addTag(id: hashtag, name: hashtag);

    // Release guard after this frame so normal typing resumes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _processingTag = false;
    });
  }

  Future<File?> _compressVideo(File videoFile) async {
    try {
      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
        _uploadStatus = 'Loading video...';
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

  Future<void> _pickMedia(MediaPickerMode mode) async {
    String? choice;

    try {
      switch (mode) {
        case MediaPickerMode.images:
          choice = 'images';
          break;
        case MediaPickerMode.videos:
          choice = 'videos';
          break;
        case MediaPickerMode.ask:
          choice = await showModalBottomSheet<String>(
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
                    subtitle: 'Select from gallery (max 1 min)',
                    onTap: () => Navigator.pop(context, 'videos'),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
          break;
      }

      if (choice == null) return;

      if (choice == 'images') {
        final List<XFile> images = await _picker.pickMultiImage(
          imageQuality: 88, // high quality, minimal visual difference
          maxWidth: 2160, // cap at 4K width
          maxHeight: 2160,
          limit: 10 - _selectedMedia.length, // limit to remaining slots
        );

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
          maxDuration: const Duration(seconds: 60),
        );

        if (video != null && _selectedMedia.length < 10) {
          File file = File(video.path);

          // check if video is longer than 1 min
          final info = await VideoCompress.getMediaInfo(file.path);
          if (info.duration != null && (info.duration! / 1000).round() > 60) {
            _showMessage(
              'Please select a video shorter than 1 minute (${(info.duration! / 1000).round()} seconds)',
            );
            return;
          }

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
            duration: controller.value.duration,
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
          imageUrl: tag.imageUrl,
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

  Future<void> _createPost() async {
    if (_selectedMedia.isEmpty && !_isEntityPost) {
      _showMessage('Please select at least one image or video', isError: true);
      return;
    }

    // For club posts with no media, require at least a caption
    if (_isEntityPost &&
        _selectedMedia.isEmpty &&
        _captionController.text.trim().isEmpty) {
      _showMessage('Please add a caption or media', isError: true);
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

    final userId = int.parse(user.id.toString());

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
      location: _taggedLocationName != null
          ? {
              'name': _taggedLocationName!,
              'lat': _taggedLat,
              'lng': _taggedLng,
            }
          : null,
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
      association: _associatedEntity != null
          ? {'id': _associatedEntity!['id'], 'type': _associatedEntity!['type']}
          : null,
    );

    // Start background upload
    if (mounted) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      Provider.of<UploadPostProvider>(
        context,
        listen: false,
      ).startUpload(uploadData, userProvider);
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

  void _openMediaPreview({required int initialIndex}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: animation,
            child: _MediaPreviewScreen(
              media: _selectedMedia,
              initialIndex: initialIndex,
              onRemoveAt: (i) {
                _removeMedia(i);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMediaStrip(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Heading row — only shown when media exists
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'MEDIA',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A8A8A),
                    letterSpacing: 0.5,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8A8A8A),
                    ),
                    children: [
                      TextSpan(
                        text: '${_selectedMedia.length}',
                        style: const TextStyle(color: Color(0xFF0B0B0B)),
                      ),
                      const TextSpan(text: ' / 10'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Horizontal scroll of tiles
          SizedBox(
            height: 140,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (int i = 0; i < _selectedMedia.length; i++) ...[
                  GestureDetector(
                    onTap: () => _openMediaPreview(initialIndex: i),
                    child: _MediaTile(
                      item: _selectedMedia[i],
                      onRemove: () => _removeMedia(i),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],

                // "Add" tile — only show if under the cap
                if (_selectedMedia.length < 10)
                  _MediaAddTile(onTap: () => _pickMedia(MediaPickerMode.ask)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeopleTagsRow() {
    if (_taggedUsers.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'WITH',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF8A8A8A),
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final user in _taggedUsers) ...[
                  _PeopleTagChip(
                    name: user.label,
                    avatarUrl: user.imageUrl,
                    onRemove: () => setState(() => _taggedUsers.remove(user)),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextTagsRow() {
    final chips = <_TagChipData>[];

    // Location
    if (_taggedLocationName != null && _taggedLocationName!.isNotEmpty) {
      chips.add(
        _TagChipData(
          icon: Icons.location_on_outlined,
          label: _taggedLocationName!,
          onRemove: () => setState(() {
            _taggedLocationName = null;
            _taggedLat = null;
            _taggedLng = null;
            _locationController.clear();
          }),
        ),
      );
    }

    // Tagged event(s)
    for (final event in _taggedEvents) {
      chips.add(
        _TagChipData(
          icon: Icons.calendar_today_outlined,
          label: event.label,
          onRemove: () => setState(() => _taggedEvents.remove(event)),
        ),
      );
    }

    // Tagged car(s)
    for (final car in _taggedVehicles) {
      chips.add(
        _TagChipData(
          icon: Icons.directions_car_outlined,
          label: car.label,
          onRemove: () => setState(() => _taggedVehicles.remove(car)),
        ),
      );
    }

    // Link
    if (_linkUrlController.text.trim().isNotEmpty) {
      chips.add(
        _TagChipData(
          icon: Icons.link,
          label: _linkType == 'video' ? 'Video link' : 'Website link',
          onRemove: () => setState(() {
            _linkUrlController.clear();
            _linkType = null;
          }),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'TAGS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF8A8A8A),
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final chip in chips) ...[
                  _ContextTagChip(data: chip),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomToolbar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF5F5F5), width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ToolButton(
                icon: Icons.image_outlined,
                label: 'Photo',
                onTap: () => _pickMedia(MediaPickerMode.images),
              ),
              _ToolButton(
                icon: Icons.videocam_outlined,
                label: 'Video',
                onTap: () => _pickMedia(
                  MediaPickerMode.videos,
                ), // same picker handles both
              ),
              _ToolButton(
                icon: Icons.location_on_outlined,
                label: 'Location',
                onTap: _openLocationSheet,
              ),
              if (!_isEntityPost) ...[
                _ToolButton(
                  icon: Icons.calendar_today_outlined,
                  label: 'Event',
                  onTap: () => _handleTagEntity('events'),
                ),
                _ToolButton(
                  icon: Icons.directions_car_outlined,
                  label: 'Car',
                  onTap: () => _handleTagEntity('car'),
                ),
                _ToolButton(
                  icon: Icons.person_outline,
                  label: 'People',
                  onTap: () => _handleTagEntity('users'),
                ),
              ],
              _ToolButton(
                icon: Icons.link,
                label: 'Link',
                onTap: _openLinkSheet,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openLocationSheet() {
    // Pre-fill with existing tagged location, if any
    _locationController.text = _taggedLocationName ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LocationPickerSheet(
        controller: _locationController,
        currentLat: _taggedLat,
        currentLng: _taggedLng,
        onSave: (name, lat, lng) {
          setState(() {
            _taggedLocationName = name;
            _taggedLat = lat;
            _taggedLng = lng;
          });
        },
        onClear: () {
          setState(() {
            _taggedLocationName = null;
            _taggedLat = null;
            _taggedLng = null;
          });
          _locationController.clear();
        },
      ),
    );
  }

  void _handleTagEntity(String entityType) async {
    if (_selectedMedia.isEmpty) {
      _showMessage('Please add media first', isError: true);
      return;
    }

    final tags = entityType == 'users'
        ? _taggedUsers
        : entityType == 'car'
        ? _taggedVehicles
        : _taggedEvents;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TagEntitiesScreen(
          media: _selectedMedia,
          entityType: entityType,
          existingTags: tags,
          onTagsUpdated: (updated) {
            setState(() {
              if (entityType == 'users') {
                _taggedUsers = updated;
              } else if (entityType == 'car') {
                _taggedVehicles = updated;
              } else {
                _taggedEvents = updated;
              }
            });
          },
        ),
      ),
    );
  }

  void _openLinkSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LinkSheet(
        initialType: _linkType ?? 'video',
        initialUrl: _linkUrlController.text,
        onSave: (type, url) {
          setState(() {
            _linkType = type;
            _linkUrlController.text = url;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SafeArea(
          bottom: false,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFF5F5F5), width: 1),
              ),
            ),
            child: Row(
              children: [
                // Cancel — text button left
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    foregroundColor: const Color(0xFF0B0B0B),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),

                // Title — centered via Expanded + center alignment
                Expanded(
                  child: Center(
                    child: Text(
                      _isEntityPost ? 'New post' : 'New post',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B0B0B),
                      ),
                    ),
                  ),
                ),

                // Post — gold pill right
                GestureDetector(
                  onTap: _isPosting ? null : _createPost,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _isPosting
                          ? Colors.grey.shade300
                          : const Color(0xFFC4A062),
                      borderRadius: BorderRadius.circular(999),
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
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isEntityPost) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBF7EE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFC4A062).withOpacity(0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Logo placeholder — replace with real club/venue logo if available
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B0B0B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: _associatedEntity?['logo'] != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      _associatedEntity!['logo'],
                                      fit: BoxFit.cover,
                                      width: 32,
                                      height: 32,
                                      errorBuilder: (_, __, ___) => const Text(
                                        '⫽',
                                        style: TextStyle(
                                          color: Color(0xFFC4A062),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  )
                                : const Text(
                                    '⫽',
                                    style: TextStyle(
                                      color: Color(0xFFC4A062),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 10),

                          // Label
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'POSTING TO',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFC4A062),
                                    letterSpacing: 0.5,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _associatedEntity?['label'] ?? 'Club',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0B0B0B),
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                    // Verified badge if applicable
                                    if (_associatedEntity?['verified'] ==
                                        true) ...[
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.verified,
                                        size: 14.5,
                                        color: Color(0xFFC4A062),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                Padding(
                  padding: const EdgeInsets.all(0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ValueListenableBuilder<SearchResultView>(
                        valueListenable: captionSearchViewModel.activeView,
                        builder: (_, view, __) {
                          return FlutterTagger(
                            controller: _captionController,
                            searchRegex: RegExp(r'\w+'),
                            triggerCharactersRegex: RegExp(r'[@#]'),
                            onSearch: (query, triggerCharacter) {
                              if (triggerCharacter == "@") {
                                captionSearchViewModel.searchUser(query);
                              }
                              if (triggerCharacter == "#") {
                                _activeHashtagQuery = query; // track it
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
                            // overlayHeight: 200,
                            overlayHeight: view == SearchResultView.hashtag
                                ? 52.0
                                : 200.0, // 👈
                            overlay: SearchResultOverlay(
                              tagController: _captionController,
                              animation: const AlwaysStoppedAnimation(
                                Offset.zero,
                              ),
                            ),
                            builder: (context, textFieldKey) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                child: TextField(
                                  key: textFieldKey,
                                  controller: _captionController,
                                  // focusNode: _captionFocus,
                                  maxLines: null,
                                  minLines: 5,
                                  maxLength: 2000,
                                  keyboardType: TextInputType.multiline,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    color: Color(0xFF0B0B0B),
                                    height: 1.45,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: "What's on your mind?",
                                    hintStyle: TextStyle(
                                      color: Color(0xFFB5B5B5),
                                      fontSize: 17,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 4,
                                    ),
                                    counterText:
                                        '', // hide the "0/2000" counter
                                    isCollapsed: true,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),

                _buildMediaStrip(theme),

                // Tags row — context tags (location, event, car, link)
                _buildContextTagsRow(),

                // With row — tagged people
                _buildPeopleTagsRow(),
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

          // Positioned(
          //   left: 0,
          //   right: 0,
          //   bottom: 0,
          //   child: _buildBottomToolbar(),
          // ),
        ],
      ),
      bottomNavigationBar: _buildBottomToolbar(),
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

class _MediaTile extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onRemove;

  const _MediaTile({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: const Color(0xFFEFEFEF),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: item.isVideo
              ? _VideoThumbnail(item: item)
              : Image.file(item.file, fit: BoxFit.cover),
        ),

        // Remove button
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),

        // Video play indicator (bottom-left)
        // Video play indicator (bottom-left) — now with duration
        if (item.isVideo)
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow, size: 11, color: Colors.white),
                  if (item.duration != null) ...[
                    const SizedBox(width: 3),
                    Text(
                      _formatDuration(item.duration!),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _MediaAddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _MediaAddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD6D6D6), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 26, color: Colors.grey.shade500),
            const SizedBox(height: 6),
            Text(
              'Add',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoThumbnail extends StatelessWidget {
  final MediaItem item;
  const _VideoThumbnail({required this.item});

  @override
  Widget build(BuildContext context) {
    // If you have a video frame loaded, you could try painting that.
    // For now, show a dark placeholder — the play icon and badge make the
    // type obvious.
    return Container(
      color: Colors.grey.shade800,
      alignment: Alignment.center,
      child: const Icon(Icons.videocam, color: Colors.white54, size: 28),
    );
  }
}

class _TagChipData {
  final IconData icon;
  final String label;
  final VoidCallback onRemove;

  _TagChipData({
    required this.icon,
    required this.label,
    required this.onRemove,
  });
}

class _ContextTagChip extends StatelessWidget {
  final _TagChipData data;
  const _ContextTagChip({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFC4A062).withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 12, color: const Color(0xFFA7864D)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              data.label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFFA7864D),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: data.onRemove,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: const Color(0xFFA7864D).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.close,
                size: 10,
                color: Color(0xFFA7864D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeopleTagChip extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final VoidCallback onRemove;

  const _PeopleTagChip({
    required this.name,
    required this.avatarUrl,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Color(0xFFE5E5E5),
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: avatarUrl != null && avatarUrl!.isNotEmpty
                ? Image.network(
                    avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.person, size: 14, color: Colors.white),
                  )
                : const Icon(Icons.person, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFF0B0B0B),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.close,
                size: 10,
                color: Color(0xFF5A5A5A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(icon, size: 24, color: const Color(0xFF0B0B0B)),
        ),
      ),
    );
  }
}

class _LinkSheet extends StatefulWidget {
  final String initialType;
  final String initialUrl;
  final void Function(String type, String url) onSave;

  const _LinkSheet({
    required this.initialType,
    required this.initialUrl,
    required this.onSave,
  });

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  late String _type;
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _urlController = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Header with title + close
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add link',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B0B0B),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFEFEF),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Color(0xFF0B0B0B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Type segmented control
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TYPE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A8A8A),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      _segButton(
                        label: 'Video link',
                        active: _type == 'video',
                        onTap: () => setState(() => _type = 'video'),
                      ),
                      _segButton(
                        label: 'Website',
                        active: _type == 'website',
                        onTap: () => setState(() => _type = 'website'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // URL input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'URL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A8A8A),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: _type == 'video'
                        ? 'https://youtu.be/…'
                        : 'https://example.com',
                    hintStyle: const TextStyle(color: Color(0xFFB5B5B5)),
                    filled: true,
                    fillColor: const Color(0xFFF4F4F4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFFC4A062),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _type == 'video'
                      ? 'Paste a YouTube, Vimeo or other video link. We\'ll show a play preview in your post.'
                      : 'Paste any web URL. The link will appear as a tap target on your post.',
                  style: const TextStyle(
                    color: Color(0xFF8A8A8A),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFEFEF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0B0B0B),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      widget.onSave(_type, _urlController.text.trim());
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC4A062),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Add',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _segButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFF0B0B0B) : const Color(0xFF8A8A8A),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaPreviewScreen extends StatefulWidget {
  final List<MediaItem> media;
  final int initialIndex;
  final void Function(int index) onRemoveAt;

  const _MediaPreviewScreen({
    required this.media,
    required this.initialIndex,
    required this.onRemoveAt,
  });

  @override
  State<_MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<_MediaPreviewScreen> {
  late PageController _pageController;
  late int _currentIndex;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _confirmRemove() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove media?'),
        content: const Text('This will remove the item from your post.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final removedIndex = _currentIndex;
              widget.onRemoveAt(removedIndex);

              // If that was the last item, close the preview entirely
              if (widget.media.length <= 1) {
                _close();
                return;
              }

              // Otherwise, slide to a neighbouring item
              setState(() {
                _currentIndex = removedIndex.clamp(0, widget.media.length - 2);
              });
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Compute fade for drag-to-dismiss
    final dragProgress = (_dragOffset.abs() / 200).clamp(0.0, 1.0);
    final backgroundOpacity = 1.0 - dragProgress;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Black background that fades on drag
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(backgroundOpacity),
            ),
          ),

          // Drag-to-dismiss wrapper
          GestureDetector(
            onVerticalDragUpdate: (d) {
              setState(() => _dragOffset += d.delta.dy);
            },
            onVerticalDragEnd: (_) {
              if (_dragOffset.abs() > 120) {
                _close();
              } else {
                setState(() => _dragOffset = 0);
              }
            },
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.media.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (_, i) {
                  final item = widget.media[i];
                  return Center(
                    child: item.isVideo
                        ? _VideoPreview(item: item)
                        : InteractiveViewer(
                            minScale: 1,
                            maxScale: 4,
                            child: Image.file(item.file, fit: BoxFit.contain),
                          ),
                  );
                },
              ),
            ),
          ),

          // Top bar — close + counter + remove
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    _CircleButton(icon: Icons.close, onTap: _close),
                    Expanded(
                      child: Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: backgroundOpacity,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${_currentIndex + 1} of ${widget.media.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _CircleButton(
                      icon: Icons.delete_outline,
                      onTap: _confirmRemove,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Page indicator dots (bottom) — only for multi-item
          if (widget.media.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: backgroundOpacity,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < widget.media.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _currentIndex ? 8 : 6,
                            height: i == _currentIndex ? 8 : 6,
                            decoration: BoxDecoration(
                              color: i == _currentIndex
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
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

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final MediaItem item;
  const _VideoPreview({required this.item});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    // Auto-play and loop
    widget.item.videoController?.play();
    widget.item.videoController?.setLooping(true);
  }

  @override
  void dispose() {
    // Pause when leaving preview; don't dispose — the MediaItem owns it
    widget.item.videoController?.pause();
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = widget.item.videoController;
    if (controller == null) return;

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.item.videoController;

    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return GestureDetector(
      onTap: _togglePlayPause,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
          // Play/pause overlay icon (fades in when paused)
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, value, __) {
              if (value.isPlaying) return const SizedBox.shrink();
              return Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LocationPickerSheet extends StatefulWidget {
  final TextEditingController controller;
  final double? currentLat;
  final double? currentLng;
  final void Function(String name, double lat, double lng) onSave;
  final VoidCallback onClear;

  const _LocationPickerSheet({
    required this.controller,
    required this.currentLat,
    required this.currentLng,
    required this.onSave,
    required this.onClear,
  });

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  String? _pendingName;
  double? _pendingLat;
  double? _pendingLng;

  @override
  void initState() {
    super.initState();
    // If there's an existing tag, seed the pending state with it
    if (widget.currentLat != null && widget.currentLng != null) {
      _pendingName = widget.controller.text;
      _pendingLat = widget.currentLat;
      _pendingLng = widget.currentLng;
    }
  }

  bool get _canSave =>
      _pendingName != null && _pendingLat != null && _pendingLng != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add location',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B0B0B),
                    ),
                  ),
                ),
                if (widget.currentLat != null)
                  GestureDetector(
                    onTap: () {
                      widget.onClear();
                      Navigator.pop(context);
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        'Remove',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFEFEF),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Color(0xFF0B0B0B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Google Places input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GooglePlaceAutoCompleteTextField(
              textEditingController: widget.controller,
              googleAPIKey: "AIzaSyDqDMSFVfl-tOgqaj4ZqA5I3HnobrIK6jg",
              inputDecoration: InputDecoration(
                hintText: 'Search for a place',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: Icon(
                  Icons.location_on_outlined,
                  color: Colors.grey.shade500,
                  size: 20,
                ),
                filled: true,
                fillColor: const Color(0xFFF4F4F4),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFC4A062),
                    width: 1.5,
                  ),
                ),
              ),
              debounceTime: 400,
              countries: const ["gb", "us"],
              isLatLngRequired: true,
              getPlaceDetailWithLatLng: (prediction) {
                setState(() {
                  _pendingName = prediction.description ?? '';
                  _pendingLat = double.tryParse(prediction.lat ?? '');
                  _pendingLng = double.tryParse(prediction.lng ?? '');
                });
              },
              itemClick: (prediction) {
                widget.controller.text = prediction.description ?? '';
                widget.controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: prediction.description?.length ?? 0),
                );
                FocusScope.of(context).unfocus();
              },
              seperatedBuilder: const Divider(height: 1),
              containerHorizontalPadding: 0,
              itemBuilder: (context, index, prediction) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        color: Colors.grey.shade500,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          prediction.description ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF0B0B0B),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
              isCrossBtnShown: false,
            ),
          ),

          const SizedBox(height: 16),

          // Save button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: GestureDetector(
              onTap: _canSave
                  ? () {
                      widget.onSave(_pendingName!, _pendingLat!, _pendingLng!);
                      Navigator.pop(context);
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _canSave
                      ? const Color(0xFFC4A062)
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Save location',
                  style: TextStyle(
                    color: _canSave ? Colors.white : Colors.grey.shade500,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
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
