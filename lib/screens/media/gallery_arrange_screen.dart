import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/widgets/events/event_community_gallery_tab.dart';
import 'package:flutter/material.dart';

/// Arranging a gallery: drag photos into order, and pick the one that acts as
/// the cover.
///
/// A separate screen rather than a mode inside the gallery view, for two
/// reasons. The gallery view's layout is a cover hero *plus* a grid, and the
/// cover moving mid-drag makes the list jump under your finger. And ordering
/// reads far better one photo per row than in a 3-up grid, where "next" is
/// ambiguous — is it right, or down?
///
/// Addressed by [galleryId] where there is one, so a standalone gallery is
/// arranged exactly like one tagged to an event.
class GalleryArrangeScreen extends StatefulWidget {
  /// The gallery being arranged. Preferred over [entityId] when set.
  final int? galleryId;

  /// Event or venue whose merged pool is being arranged, when there is no
  /// single gallery id.
  final String entityId;

  /// 'event' or 'venue' — only read when going by [entityId].
  final String entityType;

  /// The photos as currently ordered. Copied, so backing out leaves the
  /// caller's list untouched.
  final List<CommunityPhoto> photos;

  /// Accent for the cover badge, matching the host screen.
  final Color primaryColor;

  const GalleryArrangeScreen({
    super.key,
    required this.photos,
    this.galleryId,
    this.entityId = '',
    this.entityType = 'event',
    this.primaryColor = const Color(0xFFC4A062),
  });

  @override
  State<GalleryArrangeScreen> createState() => _GalleryArrangeScreenState();
}

class _GalleryArrangeScreenState extends State<GalleryArrangeScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);

  late List<CommunityPhoto> _photos;

  bool _saving = false;

  /// Whether anything actually stuck, so the caller only reloads when needed.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _photos = List<CommunityPhoto>.from(widget.photos);
  }

  Future<void> _saveOrder(List<CommunityPhoto> previous) async {
    setState(() => _saving = true);

    try {
      await EventsAPI.reorderCommunityGallery(
        galleryId: widget.galleryId,
        eventId: widget.entityId,
        imageIds: _photos.map((p) => p.id).toList(),
        entityType: widget.entityType,
      );

      if (!mounted) return;
      setState(() {
        _saving = false;
        _changed = true;
      });
    } catch (e) {
      if (!mounted) return;

      // Put it back: a drag that silently did not save is worse than one that
      // visibly springs back.
      setState(() {
        _photos
          ..clear()
          ..addAll(previous);
        _saving = false;
      });

      _complain(e);
    }
  }

  Future<void> _setCover(CommunityPhoto photo) async {
    final previous = List<CommunityPhoto>.from(_photos);

    // Optimistic, and exactly one cover: flipped locally so the badge moves
    // immediately rather than after a round trip.
    setState(() {
      for (var i = 0; i < _photos.length; i++) {
        _photos[i] = _photos[i].copyWith(isCover: _photos[i].id == photo.id);
      }
    });

    try {
      await EventsAPI.setCommunityGalleryCover(
        galleryId: widget.galleryId,
        eventId: widget.entityId,
        imageId: photo.id,
        entityType: widget.entityType,
      );

      if (!mounted) return;
      setState(() => _changed = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _photos
          ..clear()
          ..addAll(previous);
      });
      _complain(e);
    }
  }

  void _complain(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$error'.replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Every exit route pops _changed, so the gallery view knows whether it
    // needs to reload.
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
          onPressed: () => Navigator.pop(context, _changed),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Arrange photos',
              style: TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Drag to reorder · tap ☆ to set the cover',
              style: TextStyle(color: _muted, fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context, _changed),
              child: const Text(
                'Done',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: _photos.isEmpty
          ? const Center(
              child: Text(
                'Nothing to arrange yet.',
                style: TextStyle(color: _muted),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: _photos.length,
              onReorder: (oldIndex, newIndex) {
                final previous = List<CommunityPhoto>.from(_photos);

                setState(() {
                  // The drop index is reported before the dragged item is
                  // removed, so anything moving down is off by one.
                  if (newIndex > oldIndex) newIndex -= 1;
                  final moved = _photos.removeAt(oldIndex);
                  _photos.insert(newIndex, moved);
                });

                _saveOrder(previous);
              },
              itemBuilder: (context, index) {
                final photo = _photos[index];
                return _ArrangeTile(
                  key: ValueKey(photo.id),
                  photo: photo,
                  index: index,
                  accent: widget.primaryColor,
                  onSetCover: () => _setCover(photo),
                );
              },
            ),
    );
  }
}

class _ArrangeTile extends StatelessWidget {
  final CommunityPhoto photo;
  final int index;
  final Color accent;
  final VoidCallback onSetCover;

  const _ArrangeTile({
    super.key,
    required this.photo,
    required this.index,
    required this.accent,
    required this.onSetCover,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(
            color: photo.isCover ? accent : Colors.grey.shade300,
            width: photo.isCover ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: photo.thumb,
                width: 54,
                height: 54,
                fit: BoxFit.cover,
                memCacheWidth: 160,
                placeholder: (_, __) => Container(
                  width: 54,
                  height: 54,
                  color: Colors.grey.shade200,
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 54,
                  height: 54,
                  color: Colors.grey.shade200,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${index + 1}. ${photo.uploaderName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (photo.isCover) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.star, size: 13, color: accent),
                        const SizedBox(width: 4),
                        Text(
                          'Gallery cover',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!photo.isCover)
              IconButton(
                icon: const Icon(Icons.star_outline, size: 20),
                tooltip: 'Use as cover',
                onPressed: onSetCover,
              ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.drag_handle, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
