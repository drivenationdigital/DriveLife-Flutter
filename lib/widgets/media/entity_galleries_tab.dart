import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/screens/media/gallery_view_screen.dart';
import 'package:drivelife/widgets/media/gallery_card.dart';
import 'package:flutter/material.dart';

/// The Media tab on an event or a venue: the galleries linked to it.
///
/// This replaces the old community-gallery tab, which showed one merged pool
/// of everyone's photos in a 3-up grid. Galleries are their own entity now, so
/// an event's media is a list OF galleries — each with a title, an owner and a
/// cover — and tapping one opens it.
///
/// Two consequences of that worth naming. Opening by `gallery_id` is what lets
/// a gallery's owner curate their own photos from here; the old entity-keyed
/// route resolved permission to the *event* owner instead. And there is no add
/// button: a gallery is created from the media tab, where it can be titled and
/// tagged, rather than dropped into an event unnamed.
class EntityGalleriesTab extends StatefulWidget {
  /// Event or venue id.
  final String entityId;

  /// 'event' or 'venue'.
  final String entityType;

  /// Accent used for the empty-state icon.
  final Color primaryColor;

  const EntityGalleriesTab({
    super.key,
    required this.entityId,
    this.entityType = 'event',
    this.primaryColor = const Color(0xFFC4A062),
  });

  @override
  State<EntityGalleriesTab> createState() => _EntityGalleriesTabState();
}

class _EntityGalleriesTabState extends State<EntityGalleriesTab> {
  static const Color _muted = Color(0xFF8A8A8A);

  final List<Map<String, dynamic>> _galleries = [];

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
      final galleries = await EventsAPI.fetchGalleries(
        entityType: widget.entityType,
        entityId: int.tryParse(widget.entityId) ?? 0,
      );

      if (!mounted) return;

      setState(() {
        _galleries
          ..clear()
          ..addAll(galleries);
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

  Future<void> _open(Map<String, dynamic> gallery) async {
    final title = '${gallery['title'] ?? ''}';

    var changed = false;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryViewScreen(
          galleryId: int.tryParse('${gallery['gallery_id']}'),
          entityTitle: title,
          galleryName: title,
          onChanged: () => changed = true,
        ),
      ),
    );

    // A new cover, a reorder or a delete all change this list, and covers are
    // resolved server-side — so refetch rather than patch.
    if (changed && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
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

    if (_galleries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 36,
                color: widget.primaryColor,
              ),
              const SizedBox(height: 12),
              const Text(
                'No galleries yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                widget.entityType == 'venue'
                    ? 'Galleries tagged to this venue will show up here.'
                    : 'Galleries tagged to this event will show up here.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: _muted),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: widget.primaryColor,
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        // Two-up, matching the profile Galleries tab: a card carries a title,
        // and three across leaves no room to read one.
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.86,
        ),
        itemCount: _galleries.length,
        itemBuilder: (context, index) {
          final gallery = _galleries[index];
          final count = int.tryParse('${gallery['photo_count']}') ?? 0;
          final owner = gallery['owner'];
          final ownerName = owner is Map ? '${owner['name'] ?? ''}' : '';

          return GalleryCard(
            title: '${gallery['title'] ?? ''}',
            // Thumb rather than the full-size cover: these are grid tiles.
            coverUrl: '${gallery['cover_thumb'] ?? gallery['cover'] ?? ''}',
            subtitle: [
              if (ownerName.isNotEmpty) ownerName,
              if (count > 0) '$count photo${count == 1 ? '' : 's'}',
            ].join(' · '),
            onTap: () => _open(gallery),
          );
        },
      ),
    );
  }
}
