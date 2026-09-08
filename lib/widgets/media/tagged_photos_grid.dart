import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/screens/media/gallery_view_screen.dart';
import 'package:flutter/material.dart';

/// The individual gallery photos a person or vehicle is tagged in.
///
/// A sliver, so it drops straight into the Tagged tab's scroll view on both
/// the profile and the vehicle screen.
///
/// Photos rather than gallery cards: being in 2 photos of a 200-photo meet
/// gallery is a tag on 2 photos, and a card for the whole gallery claimed far
/// more than the tag said. Tapping one opens its gallery with that photo on
/// top, so the surrounding set is still one back-press away.
class TaggedPhotosGrid extends StatelessWidget {
  /// Rows from `EventsAPI.fetchTaggedPhotos`.
  final List<Map<String, dynamic>> photos;

  /// Whether to badge the photos that are here because of a vehicle.
  ///
  /// On a profile this tells the two kinds apart. On a vehicle's own Tags tab
  /// every photo is there for that vehicle, so a plate on all of them says
  /// nothing and just covers the pictures.
  final bool markVehicleTags;

  const TaggedPhotosGrid({
    super.key,
    required this.photos,
    this.markVehicleTags = true,
  });

  @override
  Widget build(BuildContext context) {
    return SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];

        final galleryId = int.tryParse('${photo['gallery_id']}') ?? 0;
        final photoId = int.tryParse('${photo['id']}') ?? 0;
        final title = '${photo['gallery_title'] ?? ''}';
        final thumb = '${photo['thumb'] ?? photo['url'] ?? ''}';

        // 'car' or 'both' means one of your vehicles is why this photo is
        // here. Worth marking: a vehicle tag also appears on that vehicle's
        // own Tags tab, and mixed in unmarked it reads as you being in the
        // photo yourself.
        final via = '${photo['via'] ?? 'user'}';
        final registration = '${photo['registration'] ?? ''}'.trim();

        return _TaggedPhotoTile(
          thumb: thumb,
          plate: (!markVehicleTags || via == 'user') ? '' : registration,
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
        );
      },
    );
  }
}

class _TaggedPhotoTile extends StatelessWidget {
  final String thumb;

  /// The registration that put this photo here, or empty when it was you.
  final String plate;

  final VoidCallback? onTap;

  const _TaggedPhotoTile({
    required this.thumb,
    required this.plate,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: Colors.grey.shade200);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
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

            if (plate.isNotEmpty)
              Positioned(
                left: 4,
                bottom: 4,
                right: 4,
                child: _PlateTag(plate: plate),
              ),
          ],
        ),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.directions_car_filled,
            size: 9,
            color: Color(0xFFAE9159),
          ),
          const SizedBox(width: 3),
          Flexible(
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
          ),
        ],
      ),
    );
  }
}
