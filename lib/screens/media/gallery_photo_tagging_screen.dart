import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/models/gallery_tag.dart';
import 'package:drivelife/widgets/media/gallery_tag_picker.dart';
import 'package:flutter/material.dart';

/// Tagging individual photos, after the gallery-wide pass.
///
/// The grid is the whole point: you pick out the two or three photos someone is
/// actually in rather than working through all sixty. Each tile carries a count
/// so it is obvious at a glance what has been done and what has not.
///
/// Gallery-wide tags are shown on every tile as a dimmed baseline — they
/// already apply to every photo, so re-adding one here would be a duplicate the
/// server would reject anyway.
class GalleryPhotoTaggingScreen extends StatefulWidget {
  final int galleryId;

  /// Tags that apply to the whole gallery, from step 2.
  final List<GalleryTag> galleryTags;

  const GalleryPhotoTaggingScreen({
    super.key,
    required this.galleryId,
    this.galleryTags = const [],
  });

  @override
  State<GalleryPhotoTaggingScreen> createState() =>
      _GalleryPhotoTaggingScreenState();
}

class _GalleryPhotoTaggingScreenState extends State<GalleryPhotoTaggingScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFC4A062);

  /// Photos in the gallery: {id, thumb, url}.
  final List<Map<String, dynamic>> _photos = [];

  /// Per-photo tags, keyed by photo row id. Only photos with tags appear.
  final Map<int, List<GalleryTag>> _tags = {};

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Every photo, not just the first page: this screen is for working
      // through the whole gallery.
      final photos = <Map<String, dynamic>>[];
      var page = 1;
      var totalPages = 1;

      while (page <= totalPages && page <= 20) {
        final response = await EventsAPI.fetchCommunityGallery(
          galleryId: widget.galleryId,
          page: page,
          perPage: 100,
        );

        if (response == null || response['success'] != true) break;

        totalPages = int.tryParse('${response['total_pages']}') ?? 1;

        final images = response['images'] as List<dynamic>? ?? const [];
        for (final image in images.whereType<Map>()) {
          photos.add(Map<String, dynamic>.from(image));
        }

        if (images.isEmpty) break;
        page++;
      }

      final existing = await EventsAPI.fetchGalleryTags(
        galleryId: widget.galleryId,
      );

      if (!mounted) return;

      final grouped = <int, List<GalleryTag>>{};
      for (final tag in existing) {
        final mediaId = int.tryParse('${tag['media_id']}') ?? 0;

        // 0 is the gallery-wide set, which this screen shows separately.
        if (mediaId <= 0) continue;

        grouped.putIfAbsent(mediaId, () => []).add(GalleryTag.fromJson(tag));
      }

      setState(() {
        _photos
          ..clear()
          ..addAll(photos);
        _tags
          ..clear()
          ..addAll(grouped);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openPhoto(Map<String, dynamic> photo) async {
    final photoId = int.tryParse('${photo['id']}') ?? 0;
    if (photoId <= 0) return;

    final saved = await showModalBottomSheet<List<GalleryTag>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _PhotoTagSheet(
        galleryId: widget.galleryId,
        photoId: photoId,
        imageUrl: '${photo['thumb'] ?? photo['url'] ?? ''}',
        initialTags: _tags[photoId] ?? const [],
        galleryTags: widget.galleryTags,
      ),
    );

    if (saved == null || !mounted) return;

    setState(() {
      if (saved.isEmpty) {
        _tags.remove(photoId);
      } else {
        _tags[photoId] = saved;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tagged = _tags.values.where((t) => t.isNotEmpty).length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tag photos',
              style: TextStyle(
                color: _ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _loading
                  ? 'Loading…'
                  : tagged == 0
                  ? 'Tap a photo to tag it'
                  : '$tagged of ${_photos.length} tagged',
              style: const TextStyle(color: _muted, fontSize: 13.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Done',
              style: TextStyle(
                color: _ink,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 34, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_photos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No photos to tag.',
            style: TextStyle(color: _muted),
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        final photoId = int.tryParse('${photo['id']}') ?? 0;
        final count = _tags[photoId]?.length ?? 0;

        return GestureDetector(
          onTap: () => _openPhoto(photo),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: '${photo['thumb'] ?? photo['url'] ?? ''}',
                fit: BoxFit.cover,
                memCacheWidth: 400,
                placeholder: (_, __) => Container(color: Colors.grey.shade200),
                errorWidget: (_, __, ___) =>
                    Container(color: Colors.grey.shade200),
              ),

              // A tagged photo is obvious without counting: gold badge, and
              // untagged tiles stay plain rather than carrying a "0".
              if (count > 0)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _gold,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_offer,
                          size: 11,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tagging one photo. Pops the saved list, or null if nothing was saved.
class _PhotoTagSheet extends StatefulWidget {
  final int galleryId;
  final int photoId;
  final String imageUrl;
  final List<GalleryTag> initialTags;
  final List<GalleryTag> galleryTags;

  const _PhotoTagSheet({
    required this.galleryId,
    required this.photoId,
    required this.imageUrl,
    required this.initialTags,
    required this.galleryTags,
  });

  @override
  State<_PhotoTagSheet> createState() => _PhotoTagSheetState();
}

class _PhotoTagSheetState extends State<_PhotoTagSheet> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);

  late List<GalleryTag> _tags = List<GalleryTag>.from(widget.initialTags);

  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      await EventsAPI.saveGalleryTags(
        galleryId: widget.galleryId,
        mediaId: widget.photoId,
        tags: _tags.map((t) => t.toJson()).toList(),
      );

      if (!mounted) return;
      Navigator.pop(context, _tags);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the sheet clear of the keyboard while searching.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: widget.imageUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      memCacheWidth: 140,
                      placeholder: (_, __) => Container(
                        width: 44,
                        height: 44,
                        color: Colors.grey.shade200,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 44,
                        height: 44,
                        color: Colors.grey.shade200,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Tag this photo',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Container(height: 1, color: Colors.grey.shade200),

            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (widget.galleryTags.isNotEmpty) ...[
                    Text(
                      'Already on the whole gallery: '
                      '${widget.galleryTags.map((t) => t.kind == TagKind.member ? '@${t.label}' : t.label).join(', ')}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _muted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  GalleryTagPicker(
                    tags: _tags,
                    onChanged: (tags) => setState(() => _tags = tags),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
