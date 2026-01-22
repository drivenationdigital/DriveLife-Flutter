import 'dart:async';
import 'package:drivelife/api/posts_api.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:video_player/video_player.dart';
import 'create_post_screen.dart'; // For MediaItem

class TagEntitiesScreen extends StatefulWidget {
  final List<MediaItem> media;
  final String entityType; // 'users', 'car', 'events'
  final Function(List<TaggedEntity>) onTagsUpdated;
  final List<TaggedEntity> existingTags;

  const TagEntitiesScreen({
    Key? key,
    required this.media,
    required this.entityType,
    required this.onTagsUpdated,
    required this.existingTags,
  }) : super(key: key);

  @override
  State<TagEntitiesScreen> createState() => _TagEntitiesScreenState();
}

class _TagEntitiesScreenState extends State<TagEntitiesScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _searchController = TextEditingController();

  int _currentIndex = 0;
  List<TaggedEntity> _tags = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  // Add to state variables:
  Offset? _tapPosition;

  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose(); // ADD THIS
    _debounce?.cancel();
    super.dispose();
  }

  // Replace _addTag method with this:
  void _addTagAtPosition(Map<String, dynamic> entity) {
    if (_tapPosition == null) return;

    // Check if already tagged
    final alreadyTagged = _tags.any(
      (t) => t.id == entity['entity_id'].toString() && t.index == _currentIndex,
    );

    if (alreadyTagged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already tagged to this image'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _tags.add(
        TaggedEntity(
          index: _currentIndex,
          id: entity['entity_id'].toString(),
          type: widget.entityType == 'users' ? 'user' : widget.entityType,
          label: entity['name'] ?? entity['vehicle_name'] ?? 'Unknown',
          x: _tapPosition!.dx,
          y: _tapPosition!.dy,
        ),
      );

      // Reset search
      _isSearching = false;
      _tapPosition = null;
      _searchController.clear();
      _searchResults = [];
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tagged ${entity['name'] ?? entity['vehicle_name']}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // Add this method for events:
  Widget _buildChipBasedUI(List<TaggedEntity> currentTags) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_getTitle(), style: const TextStyle(color: Colors.black)),
        actions: [
          TextButton(
            onPressed: () {
              widget.onTagsUpdated(_tags);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Image carousel
          SizedBox(
            height: 250,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                  _searchController.clear();
                  _searchResults = [];
                });
              },
              itemCount: widget.media.length,
              itemBuilder: (context, index) {
                final media = widget.media[index];
                return media.isVideo && media.videoController != null
                    ? VideoPlayer(media.videoController!)
                    : Image.file(media.file, fit: BoxFit.contain);
              },
            ),
          ),

          // Page indicators
          if (widget.media.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.media.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentIndex == index
                          ? const Color(0xFFAE9159)
                          : Colors.grey.shade300,
                    ),
                  ),
                ),
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Tagged chips
                  if (currentTags.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.grey.shade50,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tagged (${currentTags.length})',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: currentTags.map((tag) {
                              return Chip(
                                label: Text(tag.label),
                                deleteIcon: const Icon(Icons.close, size: 18),
                                onDeleted: () => _removeTag(tag),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                  ],

                  // Search field
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search events...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),

                  // Search results
                  if (_searchResults.isNotEmpty)
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final entity = _searchResults[index];
                        final isTagged = _tags.any(
                          (t) =>
                              t.id == entity['entity_id'].toString() &&
                              t.index == _currentIndex,
                        );

                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.event)),
                          title: Text(entity['name'] ?? ''),
                          trailing: ElevatedButton(
                            onPressed: isTagged
                                ? null
                                : () {
                                    setState(() {
                                      _tags.add(
                                        TaggedEntity(
                                          index: _currentIndex,
                                          id: entity['entity_id'].toString(),
                                          type: 'event',
                                          label: entity['name'] ?? 'Unknown',
                                        ),
                                      );
                                    });
                                  },
                            child: Text(isTagged ? 'Tagged' : 'Tag'),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Add this new method to build tag markers:
  Widget _buildTagMarker(TaggedEntity tag, BoxConstraints constraints) {
    return Positioned(
      left: tag.x! * constraints.maxWidth,
      top: tag.y! * constraints.maxHeight,
      child: Transform.translate(
        offset: const Offset(-50, -40), // Center the marker
        child: GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.white,
                title: Text(tag.label),
                content: const Text('Remove this tag?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _removeTag(tag);
                    },
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.entityType == 'car'
                          ? Icons.directions_car
                          : Icons.person,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tag.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 2, height: 12, color: Colors.white),
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // In _TagEntitiesScreenState initState:
  @override
  void initState() {
    super.initState();
    _tags = List.from(widget.existingTags); // LOAD EXISTING TAGS
  }

  Future<void> _search(String query) async {
    if (query.length < 3) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    // Don't change _isSearching here to prevent rebuild
    try {
      final results = await PostsAPI.fetchTaggableEntities(
        search: query,
        entityType: widget.entityType,
        taggedEntities: _tags.where((t) => t.index == _currentIndex).toList(),
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
        });
        // Keep focus after results appear
        _searchFocusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _search(query);
    });
  }

  void _removeTag(TaggedEntity tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  String _getTitle() {
    switch (widget.entityType) {
      case 'users':
        return 'Tag People';
      case 'car':
        return 'Tag Vehicles';
      case 'events':
        return 'Tag Events';
      default:
        return 'Tag Entities';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTags = _tags.where((t) => t.index == _currentIndex).toList();
    final isTaggable =
        widget.entityType == 'users' || widget.entityType == 'car';

    // If not taggable (events), use the old chip-based UI
    if (!isTaggable) {
      return _buildChipBasedUI(currentTags);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: _isSearching && isTaggable
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode, // ADD THIS
                autofocus: true,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search ${_getTitle().toLowerCase()}...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _searchController.clear();
                        _searchResults = [];
                        _tapPosition = null;
                      });
                    },
                  ),
                ),
              )
            : Text(_getTitle(), style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () {
              widget.onTagsUpdated(_tags);
              Navigator.pop(context);
            },
            child: const Text(
              'Done',
              style: TextStyle(
                color: Color(0xFFAE9159),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Image Carousel with tap detection
          Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                      _searchController.clear();
                      _searchResults = [];
                      _isSearching = false;
                      _tapPosition = null;
                    });
                  },
                  itemCount: widget.media.length,
                  itemBuilder: (context, index) {
                    final media = widget.media[index];
                    return LayoutBuilder(
                      // WRAP WITH LayoutBuilder
                      builder: (context, constraints) {
                        return GestureDetector(
                          onTapUp: isTaggable
                              ? (details) {
                                  final localPosition = details.localPosition;

                                  setState(() {
                                    _tapPosition = Offset(
                                      localPosition.dx / constraints.maxWidth,
                                      localPosition.dy / constraints.maxHeight,
                                    );
                                    _isSearching = true;
                                  });

                                  // Request focus after a short delay to ensure TextField is built
                                  Future.delayed(
                                    const Duration(milliseconds: 100),
                                    () {
                                      if (mounted) {
                                        _searchFocusNode.requestFocus();
                                      }
                                    },
                                  );
                                }
                              : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Media
                              if (media.isVideo &&
                                  media.videoController != null)
                                Center(
                                  child: AspectRatio(
                                    aspectRatio: media
                                        .videoController!
                                        .value
                                        .aspectRatio,
                                    child: VideoPlayer(media.videoController!),
                                  ),
                                )
                              else
                                Center(
                                  child: Image.file(
                                    media.file,
                                    fit: BoxFit.contain,
                                  ),
                                ),

                              // Existing tags markers
                              ...currentTags.map(
                                (tag) => _buildTagMarker(tag, constraints),
                              ),

                              // New tap position indicator
                              if (_tapPosition != null && isTaggable)
                                Positioned(
                                  left: _tapPosition!.dx * constraints.maxWidth,
                                  top: _tapPosition!.dy * constraints.maxHeight,
                                  child: Transform.translate(
                                    offset: const Offset(-12, -12),
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.add,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),

                              // Tap instruction
                              if (currentTags.isEmpty &&
                                  !_isSearching &&
                                  isTaggable)
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Tap to tag',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Page Indicators
              if (widget.media.length > 1)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.media.length,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentIndex == index
                              ? Colors.white
                              : Colors.white38,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // Search results overlay
          if (_isSearching && _searchResults.isNotEmpty && isTaggable)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 100,
              child: Container(
                color: Colors.black87,
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final entity = _searchResults[index];
                    final isTagged = _tags.any(
                      (t) =>
                          t.id == entity['entity_id'].toString() &&
                          t.index == _currentIndex,
                    );

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            entity['image'] != null &&
                                entity['image'] != 'search_q'
                            ? NetworkImage(entity['image'])
                            : null,
                        backgroundColor: Colors.grey,
                        child:
                            entity['image'] == null ||
                                entity['image'] == 'search_q'
                            ? Icon(
                                widget.entityType == 'car'
                                    ? Icons.directions_car
                                    : Icons.person,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      title: Text(
                        entity['name'] ?? entity['vehicle_name'] ?? '',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle:
                          entity['vehicle_name'] != null &&
                              entity['name'] != null
                          ? Text(
                              entity['vehicle_name'],
                              style: const TextStyle(color: Colors.white70),
                            )
                          : null,
                      trailing: isTagged
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      onTap: isTagged ? null : () => _addTagAtPosition(entity),
                    );
                  },
                ),
              ),
            ),

          // Loading indicator
          if (_isSearching &&
              _searchResults.isEmpty &&
              _searchController.text.length >= 3)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 100,
              child: Container(
                color: Colors.black87,
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFFAE9159)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
