import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A gallery in a list: cover image with the title over it.
///
/// Shared by the profile Galleries tab and the event/venue gallery tabs, so a
/// gallery looks the same wherever it is listed. The title sits *on* the cover
/// rather than beneath it — a gallery's cover is the point, and a caption
/// underneath halves the image for no gain.
class GalleryCard extends StatelessWidget {
  final String title;
  final String coverUrl;

  /// Optional line under the title — a photo count, or the event it came from.
  final String subtitle;

  final VoidCallback onTap;

  /// Held down on the card. Null where there is nothing to offer — a card in
  /// someone else's profile, for instance.
  final VoidCallback? onLongPress;

  const GalleryCard({
    super.key,
    required this.title,
    required this.coverUrl,
    required this.onTap,
    this.onLongPress,
    this.subtitle = '',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coverUrl.isEmpty)
              Container(color: Colors.grey.shade300)
            else
              CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                memCacheWidth: 600,
                placeholder: (_, __) => Container(color: Colors.grey.shade200),
                errorWidget: (_, __, ___) =>
                    Container(color: Colors.grey.shade300),
              ),

            // Gradient rather than a flat scrim: the title needs contrast at
            // the bottom without dulling the whole image.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: SizedBox.expand(),
            ),

            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.isEmpty ? 'Untitled gallery' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
