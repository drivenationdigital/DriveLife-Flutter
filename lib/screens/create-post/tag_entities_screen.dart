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
  final FocusNode _searchFocusNode = FocusNode();

  int _currentIndex = 0;
  List<TaggedEntity> _tags = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;
  Offset? _tapPosition;

  // Cache computed values
  bool get _isTaggable =>
      widget.entityType == 'users' || widget.entityType == 'car';
  bool get _hasMultipleMedia => widget.media.length > 1;

  @override
  void initState() {
    super.initState();
    _tags = List.from(widget.existingTags);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.length < 3) {
      setState(() => _searchResults = []);
      return;
    }

    try {
      final results = await PostsAPI.fetchTaggableEntities(
        search: query,
        entityType: widget.entityType,
        taggedEntities: _tags.where((t) => t.index == _currentIndex).toList(),
      );

      if (mounted) {
        setState(() => _searchResults = results);
        _searchFocusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) setState(() {});
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(query));
  }

  void _addTagAtPosition(Map<String, dynamic> entity) {
    if (_tapPosition == null) return;

    final alreadyTagged = _tags.any(
      (t) => t.id == entity['entity_id'].toString() && t.index == _currentIndex,
    );

    if (alreadyTagged) {
      _showSnackBar('Already tagged to this image', isError: true);
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
      _resetSearch();
    });

    _showSnackBar('Tagged ${entity['name'] ?? entity['vehicle_name']}');
  }

  void _removeTag(TaggedEntity tag) {
    setState(() => _tags.remove(tag));
  }

  void _resetSearch() {
    _isSearching = false;
    _tapPosition = null;
    _searchController.clear();
    _searchResults = [];
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
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
    return _isTaggable ? _buildTaggableUI() : _buildChipBasedUI();
  }

  // Taggable UI (Users & Cars) - Light Theme
  Widget _buildTaggableUI() {
    final currentTags = _tags.where((t) => t.index == _currentIndex).toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(child: _buildMediaCarousel(currentTags)),
              if (_hasMultipleMedia) _buildPageIndicators(),
            ],
          ),
          if (_isSearching) _buildSearchOverlay(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.black87),
        onPressed: () => Navigator.pop(context),
      ),
      title: _isSearching && _isTaggable
          ? _buildSearchField()
          : Text(
              _getTitle(),
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
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
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: true,
      onChanged: _onSearchChanged,
      style: const TextStyle(color: Colors.black87),
      decoration: InputDecoration(
        hintText: 'Search ${_getTitle().toLowerCase()}...',
        hintStyle: TextStyle(color: Colors.grey.shade400),
        border: InputBorder.none,
        suffixIcon: IconButton(
          icon: const Icon(Icons.close, color: Colors.black54),
          onPressed: () => setState(_resetSearch),
        ),
      ),
    );
  }

  Widget _buildMediaCarousel(List<TaggedEntity> currentTags) {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
          _resetSearch();
        });
      },
      itemCount: widget.media.length,
      itemBuilder: (context, index) => _MediaItem(
        media: widget.media[index],
        currentTags: currentTags,
        isTaggable: _isTaggable,
        tapPosition: _tapPosition,
        isSearching: _isSearching,
        entityType: widget.entityType,
        onTap: (position) {
          setState(() {
            _tapPosition = position;
            _isSearching = true;
          });
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) _searchFocusNode.requestFocus();
          });
        },
        onRemoveTag: _removeTag,
      ),
    );
  }

  Widget _buildPageIndicators() {
    return Padding(
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
                  ? const Color(0xFFAE9159)
                  : Colors.grey.shade300,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: 100,
      child: Container(
        color: Colors.white.withOpacity(0.98),
        child: _searchResults.isNotEmpty
            ? _buildSearchResults()
            : _searchController.text.length >= 3
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFAE9159)),
              )
            : const SizedBox(),
      ),
    );
  }

  Widget _buildSearchResults() {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entity = _searchResults[index];
        final isTagged = _tags.any(
          (t) =>
              t.id == entity['entity_id'].toString() &&
              t.index == _currentIndex,
        );

        return _SearchResultTile(
          entity: entity,
          entityType: widget.entityType,
          isTagged: isTagged,
          onTap: isTagged ? null : () => _addTagAtPosition(entity),
        );
      },
    );
  }

  // Chip-based UI (Events) - Light Theme
  Widget _buildChipBasedUI() {
    final currentTags = _tags.where((t) => t.index == _currentIndex).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildChipMediaCarousel(),
          if (_hasMultipleMedia) _buildPageIndicators(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (currentTags.isNotEmpty) _buildTaggedChips(currentTags),
                  _buildEventSearchField(),
                  if (_searchResults.isNotEmpty) _buildEventResults(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipMediaCarousel() {
    return SizedBox(
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
    );
  }

  Widget _buildTaggedChips(List<TaggedEntity> currentTags) {
    return Container(
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
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: currentTags
                .map(
                  (tag) => Chip(
                    label: Text(tag.label),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () => _removeTag(tag),
                    backgroundColor: Colors.white,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEventSearchField() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search events...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildEventResults() {
    return ListView.builder(
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
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFAE9159).withOpacity(0.1),
            child: const Icon(Icons.event, color: Color(0xFFAE9159)),
          ),
          title: Text(
            entity['name'] ?? '',
            style: const TextStyle(color: Colors.black87),
          ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: isTagged
                  ? Colors.grey.shade300
                  : const Color(0xFFAE9159),
              foregroundColor: isTagged ? Colors.grey.shade600 : Colors.white,
            ),
            child: Text(isTagged ? 'Tagged' : 'Tag'),
          ),
        );
      },
    );
  }
}

// Extracted Media Item Widget for better performance
class _MediaItem extends StatelessWidget {
  final MediaItem media;
  final List<TaggedEntity> currentTags;
  final bool isTaggable;
  final Offset? tapPosition;
  final bool isSearching;
  final String entityType;
  final Function(Offset) onTap;
  final Function(TaggedEntity) onRemoveTag;

  const _MediaItem({
    required this.media,
    required this.currentTags,
    required this.isTaggable,
    required this.tapPosition,
    required this.isSearching,
    required this.entityType,
    required this.onTap,
    required this.onRemoveTag,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapUp: isTaggable
              ? (details) {
                  final localPosition = details.localPosition;
                  onTap(
                    Offset(
                      localPosition.dx / constraints.maxWidth,
                      localPosition.dy / constraints.maxHeight,
                    ),
                  );
                }
              : null,
          child: Container(
            color: Colors.white,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildMedia(),
                ...currentTags.map(
                  (tag) => _TagMarker(
                    tag: tag,
                    entityType: entityType,
                    constraints: constraints,
                    onRemove: onRemoveTag,
                  ),
                ),
                if (tapPosition != null && isTaggable)
                  _TapIndicator(
                    position: tapPosition!,
                    constraints: constraints,
                  ),
                if (currentTags.isEmpty && !isSearching && isTaggable)
                  const _TapInstruction(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMedia() {
    if (media.isVideo && media.videoController != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: media.videoController!.value.aspectRatio,
          child: VideoPlayer(media.videoController!),
        ),
      );
    }
    return Center(child: Image.file(media.file, fit: BoxFit.contain));
  }
}

// Extracted Tag Marker Widget
class _TagMarker extends StatelessWidget {
  final TaggedEntity tag;
  final String entityType;
  final BoxConstraints constraints;
  final Function(TaggedEntity) onRemove;

  const _TagMarker({
    required this.tag,
    required this.entityType,
    required this.constraints,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: tag.x! * constraints.maxWidth,
      top: tag.y! * constraints.maxHeight,
      child: Transform.translate(
        offset: const Offset(-50, -40),
        child: GestureDetector(
          onTap: () => _showRemoveDialog(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFAE9159),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      entityType == 'car' ? Icons.directions_car : Icons.person,
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
              Container(width: 2, height: 12, color: const Color(0xFFAE9159)),
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Color(0xFFAE9159),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRemoveDialog(BuildContext context) {
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
              onRemove(tag);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// Tap Position Indicator
class _TapIndicator extends StatelessWidget {
  final Offset position;
  final BoxConstraints constraints;

  const _TapIndicator({required this.position, required this.constraints});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx * constraints.maxWidth,
      top: position.dy * constraints.maxHeight,
      child: Transform.translate(
        offset: const Offset(-12, -12),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFAE9159).withOpacity(0.2),
            border: Border.all(color: const Color(0xFFAE9159), width: 2),
          ),
          child: const Icon(Icons.add, color: Color(0xFFAE9159), size: 16),
        ),
      ),
    );
  }
}

// Tap Instruction Widget
class _TapInstruction extends StatelessWidget {
  const _TapInstruction();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Tap to tag',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }
}

// Search Result Tile Widget
class _SearchResultTile extends StatelessWidget {
  final Map<String, dynamic> entity;
  final String entityType;
  final bool isTagged;
  final VoidCallback? onTap;

  const _SearchResultTile({
    required this.entity,
    required this.entityType,
    required this.isTagged,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage:
            entity['image'] != null && entity['image'] != 'search_q'
            ? NetworkImage(entity['image'])
            : null,
        backgroundColor: Colors.grey.shade200,
        child: entity['image'] == null || entity['image'] == 'search_q'
            ? Icon(
                entityType == 'car' ? Icons.directions_car : Icons.person,
                color: Colors.grey.shade600,
              )
            : null,
      ),
      title: Text(
        entity['name'] ?? entity['vehicle_name'] ?? '',
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: entity['vehicle_name'] != null && entity['name'] != null
          ? Text(
              entity['vehicle_name'],
              style: TextStyle(color: Colors.grey.shade600),
            )
          : null,
      trailing: isTagged
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.add_circle_outline, color: Color(0xFFAE9159)),
      onTap: onTap,
    );
  }
}
