import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/gallery_tag.dart';
import 'package:flutter/material.dart';

/// Search-and-pick for members and vehicles.
///
/// Shared by the gallery-wide step of the upload and by per-photo tagging, so
/// the two behave identically — the only difference is what the caller saves
/// the resulting list against.
///
/// Vehicles are matched by **exact registration** (see get_taggable_vehicles);
/// that is a server constraint, not a choice here, and it is why a plate
/// matching nothing can still be tagged by hand.
class GalleryTagPicker extends StatefulWidget {
  /// Tags chosen so far. The picker does not own them — it reports changes
  /// through [onChanged], so the caller decides when to save.
  final List<GalleryTag> tags;

  final ValueChanged<List<GalleryTag>> onChanged;

  const GalleryTagPicker({
    super.key,
    required this.tags,
    required this.onChanged,
  });

  @override
  State<GalleryTagPicker> createState() => _GalleryTagPickerState();
}

class _GalleryTagPickerState extends State<GalleryTagPicker> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFC4A062);

  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _results = const [];

  TagKind _searching = TagKind.member;

  bool _loading = false;

  /// Debounces typing, so a search does not fire per keystroke.
  Timer? _debounce;

  /// Guards against a slow response for an old query landing after a newer one.
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim();

  String get _plate => _query.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
    setState(() {}); // Repaints the plate offer as they type.
  }

  Future<void> _search() async {
    final query = _query;

    // Below two characters every search is a scan that returns nothing useful.
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }

    final id = ++_requestId;
    setState(() => _loading = true);

    try {
      final results = await PostsAPI.fetchTaggableEntities(
        search: query,
        entityType: _searching == TagKind.member ? 'users' : 'car',
        taggedEntities: const [],
        // Deliberately no exclusion: whoever shot the gallery may well be in
        // it, so tagging yourself here is legitimate.
      );

      if (!mounted || id != _requestId) return;

      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
  }

  void _add(GalleryTag tag) {
    if (widget.tags.any((t) => t.matches(tag))) return;

    widget.onChanged([...widget.tags, tag]);

    setState(() {
      _searchController.clear();
      _results = const [];
    });

    FocusScope.of(context).unfocus();
  }

  void _remove(GalleryTag tag) {
    widget.onChanged(widget.tags.where((t) => !identical(t, tag)).toList());
  }

  void _addFromResult(Map<String, dynamic> result) {
    final entityId = int.tryParse('${result['entity_id']}') ?? 0;
    final name = '${result['name'] ?? ''}';

    if (_searching == TagKind.member) {
      _add(
        GalleryTag(
          kind: TagKind.member,
          label: name,
          subtitle: '${result['display_name'] ?? ''}',
          avatarUrl: '${result['image'] ?? ''}',
          entityId: entityId,
        ),
      );
      return;
    }

    // For a vehicle the API returns the plate as `name` and "make model" as
    // `vehicle_name`.
    _add(
      GalleryTag(
        kind: TagKind.vehicle,
        label: name,
        subtitle: '${result['vehicle_name'] ?? ''}',
        avatarUrl: '${result['image'] ?? ''}',
        entityId: entityId,
        registration: name,
      ),
    );
  }

  /// Whether to offer the typed registration as a tag in its own right.
  ///
  /// Vehicle search is an exact match, so "no results" is the ordinary case for
  /// a car nobody has registered here.
  bool get _canTagPlate {
    if (_searching != TagKind.vehicle) return false;
    if (_plate.length < 4 || _plate.length > 10) return false;

    return !_loading &&
        _results.isEmpty &&
        !widget.tags.any(
          (t) => t.kind == TagKind.vehicle && t.label.toUpperCase() == _plate,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<TagKind>(
          segments: const [
            ButtonSegment(
              value: TagKind.member,
              icon: Icon(Icons.person_outline, size: 18),
              label: Text('People'),
            ),
            ButtonSegment(
              value: TagKind.vehicle,
              icon: Icon(Icons.directions_car_outlined, size: 18),
              label: Text('Vehicles'),
            ),
          ],
          selected: {_searching},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() {
              _searching = selection.first;
              _results = const [];
              _searchController.clear();
            });
          },
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          textCapitalization: _searching == TagKind.vehicle
              ? TextCapitalization.characters
              : TextCapitalization.none,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 20),
            // States the exact-plate rule up front, rather than letting people
            // discover it by getting nothing back for "M3".
            hintText: _searching == TagKind.member
                ? 'Search by username'
                : 'Enter the full registration',
            hintStyle: const TextStyle(color: _muted, fontSize: 15),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _ink, width: 1.5),
            ),
          ),
        ),

        if (_canTagPlate) ...[
          const SizedBox(height: 10),
          _PlateOffer(
            plate: _plate,
            onTag: () => _add(
              GalleryTag(
                kind: TagKind.vehicle,
                label: _plate,
                subtitle: 'Not registered here yet',
                registration: _plate,
              ),
            ),
          ),
        ],

        for (final result in _results) ...[
          const SizedBox(height: 8),
          _ResultRow(
            title: '${result['name'] ?? ''}',
            subtitle: _searching == TagKind.member
                ? '${result['display_name'] ?? ''}'
                : '${result['vehicle_name'] ?? ''}',
            imageUrl: '${result['image'] ?? ''}',
            isVehicle: _searching == TagKind.vehicle,
            onTag: () => _addFromResult(result),
          ),
        ],

        if (widget.tags.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(
            children: [
              const Text(
                'Tagged',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${widget.tags.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A6D2F),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final tag in widget.tags) ...[
            GalleryTagCard(tag: tag, onRemove: () => _remove(tag)),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

/// Offers a typed registration that matched nothing in any garage.
class _PlateOffer extends StatelessWidget {
  final String plate;
  final VoidCallback onTag;

  const _PlateOffer({required this.plate, required this.onTag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const GalleryPlateBadge(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  plate,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'No member has this car registered',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8A8A)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTag,
            child: const Text(
              'Tag',
              style: TextStyle(
                color: Color(0xFFC4A062),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One search result, with a Tag action.
class _ResultRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final bool isVehicle;
  final VoidCallback onTag;

  const _ResultRow({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.isVehicle,
    required this.onTag,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTag,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            GalleryTagAvatar(imageUrl: imageUrl, isVehicle: isVehicle),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isVehicle ? title : '@$title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF8A8A8A),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Text(
              'Tag',
              style: TextStyle(
                color: Color(0xFFC4A062),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A confirmed tag, with a remove control.
class GalleryTagCard extends StatelessWidget {
  final GalleryTag tag;
  final VoidCallback onRemove;

  const GalleryTagCard({
    super.key,
    required this.tag,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isVehicle = tag.kind == TagKind.vehicle;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          GalleryTagAvatar(imageUrl: tag.avatarUrl, isVehicle: isVehicle),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isVehicle ? tag.label : '@${tag.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (tag.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tag.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF8A8A8A),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            tooltip: 'Remove tag',
          ),
        ],
      ),
    );
  }
}

/// Round for a member, square plate badge for a vehicle — the shape alone says
/// which kind a row is, without having to read it.
class GalleryTagAvatar extends StatelessWidget {
  final String imageUrl;
  final bool isVehicle;
  final double size;

  const GalleryTagAvatar({
    super.key,
    required this.imageUrl,
    required this.isVehicle,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return isVehicle
          ? GalleryPlateBadge(size: size)
          : CircleAvatar(
              radius: size / 2,
              backgroundColor: Colors.grey.shade300,
              child: Icon(
                Icons.person,
                size: size * 0.48,
                color: Colors.white,
              ),
            );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(isVehicle ? 8 : size / 2),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: 130,
        placeholder: (_, __) =>
            Container(width: size, height: size, color: Colors.grey.shade200),
        errorWidget: (_, __, ___) => isVehicle
            ? GalleryPlateBadge(size: size)
            : Container(
                width: size,
                height: size,
                color: Colors.grey.shade300,
              ),
      ),
    );
  }
}

class GalleryPlateBadge extends StatelessWidget {
  final double size;

  const GalleryPlateBadge({super.key, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF5C518),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.directions_car,
        size: size * 0.48,
        color: const Color(0xFF0B0B0B),
      ),
    );
  }
}
