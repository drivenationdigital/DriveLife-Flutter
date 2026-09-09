import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/screens/media/gallery_view_screen.dart';
import 'package:flutter/material.dart';

/// One gallery photo somebody is tagged in, as a grid tile.
///
/// Built to sit in the SAME grid as tagged posts rather than a section of its
/// own: being tagged is one idea, and splitting it under two headings made a
/// photo of you look like a different kind of thing from a post of you. The
/// small gallery mark is what says where it came from.
///
/// Tapping opens the photo with its gallery behind it, so the rest of the set
/// is one back-press away.
class TaggedPhotoTile extends StatelessWidget {
  /// One row from `EventsAPI.fetchTaggedPhotos`.
  final Map<String, dynamic> photo;

  /// Whether to show the registration that put this photo here.
  ///
  /// On a profile it tells "you are in this photo" from "your car is". On a
  /// vehicle's own Tags tab every photo is that vehicle's, so a plate on all
  /// of them says nothing and just covers the picture.
  final bool markVehicleTags;

  const TaggedPhotoTile({
    super.key,
    required this.photo,
    this.markVehicleTags = true,
  });

  @override
  Widget build(BuildContext context) {
    final galleryId = int.tryParse('${photo['gallery_id']}') ?? 0;
    final photoId = int.tryParse('${photo['id']}') ?? 0;
    final title = '${photo['gallery_title'] ?? ''}';
    final thumb = '${photo['thumb'] ?? photo['url'] ?? ''}';

    // 'car' or 'both' means one of your vehicles is why this photo is here.
    final via = '${photo['via'] ?? 'user'}';
    final registration = '${photo['registration'] ?? ''}'.trim();
    final plate = (!markVehicleTags || via == 'user') ? '' : registration;

    final placeholder = ColoredBox(color: Colors.grey.shade300);

    return GestureDetector(
      // A photo with no gallery behind it has nowhere to go, so it is shown
      // but not tappable rather than opening an empty screen.
      onTap: galleryId <= 0
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GalleryViewScreen(
                  galleryId: galleryId,
                  entityTitle: title,
                  galleryName: title,
                  initialPhotoId: photoId > 0 ? photoId : null,
                ),
              ),
            ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumb.isEmpty)
            placeholder
          else
            CachedNetworkImage(
              imageUrl: thumb,
              fit: BoxFit.cover,
              // A third of the screen wide at most, so a full-size decode
              // behind a thumbnail is wasted memory in a long tab.
              memCacheWidth: 400,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),

          // Bottom left, mirroring the multi-image mark posts carry top right,
          // so the two kinds of tile are told apart at a glance without either
          // looking like the odd one out.
          const Positioned(left: 4, bottom: 4, child: _GalleryMark()),

          if (plate.isNotEmpty)
            Positioned(right: 4, bottom: 4, child: _PlateTag(plate: plate)),
        ],
      ),
    );
  }
}

/// The mark that says a tile is a gallery photo rather than a post.
class _GalleryMark extends StatelessWidget {
  const _GalleryMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(
        Icons.photo_library_outlined,
        color: Colors.white,
        size: 14,
      ),
    );
  }
}

/// The registration over a thumbnail, saying this photo is here because of a
/// vehicle rather than because you are in it.
class _PlateTag extends StatelessWidget {
  final String plate;

  const _PlateTag({required this.plate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        // Solid rather than translucent: it sits over a photograph, and a
        // washed-out plate on a bright shot is unreadable.
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        plate,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 9,
          height: 1.3,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: Colors.white,
        ),
      ),
    );
  }
}
