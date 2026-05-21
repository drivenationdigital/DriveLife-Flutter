import 'dart:async';
import 'dart:ui';
import 'package:drivelife/api/posts_api.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'create_post_screen.dart'; // For MediaItem

class TagEntitiesScreen extends StatefulWidget {
  final List<MediaItem> media;
  final String entityType; // 'users', 'car', 'events'
  final Function(List<TaggedEntity>) onTagsUpdated;
  final List<TaggedEntity> existingTags;

  const TagEntitiesScreen({
    super.key,
    required this.media,
    required this.entityType,
    required this.onTagsUpdated,
    required this.existingTags,
  });

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
  bool _isLoading = false;
  Timer? _debounce;

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
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final results = await PostsAPI.fetchTaggableEntities(
        search: query,
        entityType: widget.entityType,
        taggedEntities: _tags.where((t) => t.index == _currentIndex).toList(),
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  void _addTag(Map<String, dynamic> entity) {
    final alreadyTagged = _tags.any(
      (t) => t.id == entity['entity_id'].toString() && t.index == _currentIndex,
    );

    if (alreadyTagged) {
      HapticFeedback.lightImpact();
      return;
    }

    setState(() {
      _tags.add(
        TaggedEntity(
          index: _currentIndex,
          id: entity['entity_id'].toString(),
          type: _typeForEntity,
          label: entity['name'] ?? entity['vehicle_name'] ?? 'Unknown',
          imageUrl: entity['image']?.toString() != 'search_q'
              ? entity['image']?.toString()
              : null,
        ),
      );
    });
  }

  void _removeTag(TaggedEntity tag) {
    setState(() => _tags.remove(tag));
  }

  String get _typeForEntity {
    switch (widget.entityType) {
      case 'users':
        return 'user';
      case 'car':
        return 'car';
      case 'events':
        return 'event';
      default:
        return widget.entityType;
    }
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
        return 'Tag';
    }
  }

  IconData _iconForType() {
    switch (widget.entityType) {
      case 'users':
        return Icons.person_outline;
      case 'car':
        return Icons.directions_car_outlined;
      case 'events':
        return Icons.calendar_today_outlined;
      default:
        return Icons.tag;
    }
  }

  String _hintForType() {
    switch (widget.entityType) {
      case 'users':
        return 'Search people…';
      case 'car':
        return 'Search vehicles…';
      case 'events':
        return 'Search events…';
      default:
        return 'Search…';
    }
  }

  String _emptyStateLabel() {
    switch (widget.entityType) {
      case 'users':
        return 'Search for someone';
      case 'car':
        return 'Search for a vehicle';
      case 'events':
        return 'Search for an event';
      default:
        return 'Search';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTags = _tags.where((t) => t.index == _currentIndex).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Flexible(
            flex: 0,
            fit: FlexFit
                .loose, // ← uses up to its natural height, less if needed
            child: _buildMediaCarousel(),
          ),
          if (_hasMultipleMedia) _buildPageIndicators(),
          if (currentTags.isNotEmpty) _buildTaggedSection(currentTags),
          _buildSearchField(),
          Expanded(child: _buildResultsArea()),
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
        icon: const Icon(Icons.close, color: Color(0xFF0B0B0B), size: 22),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        _getTitle(),
        style: const TextStyle(
          color: Color(0xFF0B0B0B),
          fontWeight: FontWeight.w800,
          fontSize: 17,
        ),
      ),
      actions: [
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.shade200),
      ),
    );
  }

  Widget _buildMediaCarousel() {
    return SizedBox(
      height: 220,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemCount: widget.media.length,
        itemBuilder: (context, index) {
          final media = widget.media[index];

          return Stack(
            fit: StackFit.expand,
            children: [
              // Blurred background fill
              ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: media.isVideo && media.videoController != null
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: media.videoController!.value.size.width,
                            height: media.videoController!.value.size.height,
                            child: VideoPlayer(media.videoController!),
                          ),
                        )
                      : Image.file(media.file, fit: BoxFit.cover),
                ),
              ),
              // Dark scrim
              Container(color: Colors.black.withOpacity(0.15)),
              // Sharp centered media
              Center(
                child: media.isVideo && media.videoController != null
                    ? AspectRatio(
                        aspectRatio: media.videoController!.value.aspectRatio,
                        child: VideoPlayer(media.videoController!),
                      )
                    : Image.file(media.file, fit: BoxFit.contain),
              ),
            ],
          );
        },
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

  Widget _buildTaggedSection(List<TaggedEntity> currentTags) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFBFBFB),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForType(), size: 12, color: const Color(0xFFC4A062)),
              const SizedBox(width: 6),
              Text(
                'TAGGED · ${currentTags.length}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF8A8A8A),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Horizontal scrolling row — fixed height, no growth
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: currentTags.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _TagPill(
                tag: currentTags[i],
                onRemove: () => _removeTag(currentTags[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _onSearchChanged,
          style: const TextStyle(color: Color(0xFF0B0B0B), fontSize: 14.5),
          decoration: InputDecoration(
            hintText: _hintForType(),
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14.5),
            prefixIcon: Icon(
              Icons.search,
              size: 20,
              color: Colors.grey.shade500,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchResults = []);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            isDense: true,
          ),
        ),
      ),
    );
  }

  Widget _buildResultsArea() {
    if (_searchController.text.isEmpty) {
      return _buildSearchEmptyState();
    }
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFC4A062),
          strokeWidth: 2.5,
        ),
      );
    }
    if (_searchController.text.length < 3) {
      return Center(
        child: Text(
          'Type at least 3 characters',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'No results',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
      );
    }
    return _buildSearchResults();
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
              _iconForType(),
              size: 36,
              color: const Color(0xFFC4A062),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _emptyStateLabel(),
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

  Widget _buildSearchResults() {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.grey.shade100, indent: 72),
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
          onTap: isTagged ? null : () => _addTag(entity),
        );
      },
    );
  }
}

class _TagPill extends StatelessWidget {
  final TaggedEntity tag;
  final VoidCallback onRemove;

  const _TagPill({required this.tag, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final hasImage = tag.imageUrl != null && tag.imageUrl!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFC4A062).withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFC4A062).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFFE5E5E5),
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: hasImage
                ? Image.network(
                    tag.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      _iconForTagType(tag.type),
                      size: 14,
                      color: Colors.grey.shade500,
                    ),
                  )
                : Icon(
                    _iconForTagType(tag.type),
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              tag.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFA7864D),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFFA7864D).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.close,
                size: 11,
                color: Color(0xFFA7864D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForTagType(String type) {
    switch (type) {
      case 'user':
        return Icons.person_outline;
      case 'car':
        return Icons.directions_car_outlined;
      case 'event':
        return Icons.calendar_today_outlined;
      default:
        return Icons.tag;
    }
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
