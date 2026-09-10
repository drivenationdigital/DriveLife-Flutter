import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/widgets/media/gallery_tag_picker.dart';
import 'package:flutter/material.dart';

/// One plate the scan read, in the "Auto-detected" list.
///
/// Shared by the gallery and post tagging screens, which had a copy each and
/// had already drifted apart. The two flows tag the same things off the same
/// kind of evidence, so a detected car should not look like two different
/// findings depending on which screen you reached it from.
///
/// The picture follows what we know:
///
///  * a plate we can put a **person** to shows their face, because at that
///    point the row is about them — a gold car badge over somebody we can name
///    is the least useful image available;
///  * a plate matched to a garage with no owner picture shows the car;
///  * a plate matching nothing shows the badge, which is honest: a
///    registration is the whole of what was read.
class DetectedVehicleRow extends StatelessWidget {
  static const Color _muted = Color(0xFF8A8A8A);

  /// One suggestion as the scan endpoints return it.
  final Map<String, dynamic> suggestion;

  final VoidCallback onRemove;

  /// What removing it means here — "Not in these photos" for a gallery, "Not
  /// in this post" for a post.
  final String removeTooltip;

  const DetectedVehicleRow({
    super.key,
    required this.suggestion,
    required this.onRemove,
    this.removeTooltip = 'Not in these photos',
  });

  @override
  Widget build(BuildContext context) {
    final plate = '${suggestion['registration'] ?? ''}';
    final vehicleImage = '${suggestion['image'] ?? ''}';
    final count = int.tryParse('${suggestion['photo_count']}') ?? 0;

    final owner = suggestion['owner'];
    final ownerMap = owner is Map ? Map<String, dynamic>.from(owner) : null;
    final ownerHandle = '${ownerMap?['label'] ?? ''}';
    final ownerImage = '${ownerMap?['image'] ?? ''}';

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          _Thumb(
            ownerImage: ownerImage,
            ownerHandle: ownerHandle,
            vehicleImage: vehicleImage,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        plate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 7),
                      Text(
                        '$count photo${count == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 11.5, color: _muted),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${suggestion['subtitle'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: _muted),
                ),
                // Its own line, not appended to the model: a long model name
                // and a long handle together would ellipsis away exactly the
                // part that says whose car it is.
                if (ownerHandle.isNotEmpty)
                  Text(
                    'Owned by @$ownerHandle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: _muted),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            tooltip: removeTooltip,
          ),
        ],
      ),
    );
  }
}

/// The picture for one detected plate.
class _Thumb extends StatelessWidget {
  static const double _size = 40;

  final String ownerImage;
  final String ownerHandle;
  final String vehicleImage;

  const _Thumb({
    required this.ownerImage,
    required this.ownerHandle,
    required this.vehicleImage,
  });

  @override
  Widget build(BuildContext context) {
    // A person we have identified, with a picture: round, like every other
    // person in the app.
    if (ownerImage.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: ownerImage,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          memCacheWidth: 120,
          placeholder: (_, __) => _Initial(handle: ownerHandle),
          errorWidget: (_, __, ___) => _Initial(handle: ownerHandle),
        ),
      );
    }

    // Identified, but no picture of their own. Their initial still says a
    // person is behind this plate, which the car badge does not.
    if (ownerHandle.isNotEmpty) return _Initial(handle: ownerHandle);

    if (vehicleImage.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: vehicleImage,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          memCacheWidth: 120,
          placeholder: (_, __) => const GalleryPlateBadge(size: _size),
          errorWidget: (_, __, ___) => const GalleryPlateBadge(size: _size),
        ),
      );
    }

    return const GalleryPlateBadge(size: _size);
  }
}

/// A named person with no photo.
class _Initial extends StatelessWidget {
  static const Color _gold = Color(0xFFC4A062);

  final String handle;

  const _Initial({required this.handle});

  @override
  Widget build(BuildContext context) {
    final letter = handle.isEmpty ? '?' : handle.substring(0, 1).toUpperCase();

    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF8A6D2F),
        ),
      ),
    );
  }
}
