import 'dart:async';
import 'dart:ui';
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

    print(entity); // Debugging line

   setState(() {
      _tags.add(
        TaggedEntity(
          index: _currentIndex,
          id: entity['entity_id'].toString(),
          type: widget.entityType == 'users' ? 'user' : widget.entityType,
          label: entity['name'] ?? entity['vehicle_name'] ?? 'Unknown',
          imageUrl: entity['image']?.toString() != 'search_q'
              ? entity['image']?.toString()
              : null, // ← new
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
      elevation: 0,
      surfaceTintColor: Colors.white,
      leading: IconButton(
        icon: Icon(
          _isSearching ? Icons.arrow_back : Icons.close,
          color: const Color(0xFF0B0B0B),
          size: 22,
        ),
        onPressed: () {
          if (_isSearching && _isTaggable) {
            setState(_resetSearch); // back-out of search first
          } else {
            Navigator.pop(context);
          }
        },
      ),
      titleSpacing: 0,
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.3),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: _isSearching && _isTaggable
            ? _buildSearchField()
            : Text(
                _getTitle(),
                key: const ValueKey('title'),
                style: const TextStyle(
                  color: Color(0xFF0B0B0B),
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
      ),
      actions: [
        if (!_isSearching)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () {
                widget.onTagsUpdated(_tags);
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFC4A062),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
      ],
      bottom: _isSearching && _isTaggable
          ? PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: Colors.grey.shade200),
            )
          : null,
    );
  }

  Widget _buildSearchField() {
    return Container(
      key: const ValueKey('search'),
      height: 36,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: true,
        onChanged: _onSearchChanged,
        style: const TextStyle(color: Color(0xFF0B0B0B), fontSize: 14),
        decoration: InputDecoration(
          hintText: widget.entityType == 'car'
              ? 'Search vehicles…'
              : 'Search people…',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade500),
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchResults = []);
                  },
                  child: Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          isDense: true,
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
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < widget.media.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _currentIndex == i ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _currentIndex == i
                    ? const Color(0xFFC4A062)
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.white,
        child: _searchController.text.isEmpty
            ? _buildSearchEmptyState()
            : _searchResults.isNotEmpty
            ? _buildSearchResults()
            : _searchController.text.length >= 3
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFC4A062),
                  strokeWidth: 2.5,
                ),
              )
            : _buildHintState(),
      ),
    );
  }

  Widget _buildSearchEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFC4A062).withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.entityType == 'car'
                  ? Icons.directions_car_outlined
                  : Icons.person_outline,
              size: 36,
              color: const Color(0xFFC4A062),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.entityType == 'car'
                ? 'Search for a vehicle'
                : 'Search for someone',
            style: const TextStyle(
              color: Color(0xFF0B0B0B),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Type at least 3 characters',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildHintState() {
    return Center(
      child: Text(
        'Keep typing…',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
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
          hintText: 'Search events',
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
                          imageUrl: entity['image']?.toString() != 'search_q'
                              ? entity['image']?.toString()
                              : null, // ← new
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
                  // Blurred background fill
                _buildBlurredBackground(),

                // Optional dark scrim — keeps tag pins/labels readable against busy
                // backgrounds. Tweak opacity to taste (0.15 - 0.35 range works).
                Container(color: Colors.black.withOpacity(0.20)),

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

  Widget _buildBlurredBackground() {
    if (media.isVideo && media.videoController != null) {
      return ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: media.videoController!.value.size.width,
                height: media.videoController!.value.size.height,
                child: VideoPlayer(media.videoController!),
              ),
            ),
          ),
        ),
      );
    }

    return ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Image.file(
          media.file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
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
        offset: const Offset(-12, -12),
        child: GestureDetector(
          onTap: () => _showTagSheet(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pin dot
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFC4A062),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.add, size: 14, color: Color(0xFFC4A062)),
                ),
              ),
              const SizedBox(height: 6),
              // Label
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.78),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        entityType == 'car'
                            ? Icons.directions_car
                            : Icons.person,
                        color: Colors.white70,
                        size: 11,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          tag.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            height: 1,
                          ),
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
    );
  }

  void _showTagSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFC4A062).withOpacity(0.1),
                backgroundImage:
                    tag.imageUrl != null && tag.imageUrl!.isNotEmpty
                    ? NetworkImage(tag.imageUrl!)
                    : null,
                child: tag.imageUrl == null || tag.imageUrl!.isEmpty
                    ? Icon(
                        entityType == 'car'
                            ? Icons.directions_car
                            : Icons.person,
                        color: const Color(0xFFC4A062),
                      )
                    : null,
              ),
              title: Text(
                tag.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                entityType == 'car' ? 'Vehicle tag' : 'Person tag',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Remove tag',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onRemove(tag);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
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

class _TapInstruction extends StatelessWidget {
  const _TapInstruction();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, color: Colors.white, size: 14),
              SizedBox(width: 6),
              Text(
                'Tap to tag someone',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final imageUrl = entity['image']?.toString();
    final hasImage =
        imageUrl != null && imageUrl.isNotEmpty && imageUrl != 'search_q';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: hasImage
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          entityType == 'car'
                              ? Icons.directions_car
                              : Icons.person,
                          color: Colors.grey.shade500,
                        ),
                      )
                    : Icon(
                        entityType == 'car'
                            ? Icons.directions_car
                            : Icons.person,
                        color: Colors.grey.shade500,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entity['name'] ?? entity['vehicle_name'] ?? '',
                      style: const TextStyle(
                        color: Color(0xFF0B0B0B),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entity['vehicle_name'] != null &&
                        entity['name'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          entity['vehicle_name'],
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isTagged)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 13, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        'Tagged',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC4A062).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.add,
                    color: Color(0xFFC4A062),
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
