import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A card in the featured carousel at the top of a listing screen.
///
/// The picture carries the whole card and the text sits on it, so everything
/// written here has to stay readable over a photograph nobody chose for its
/// contrast. That is what the scrim is for, and why the subtitle is white at
/// 85% rather than a grey that would disappear over a bright sky.
class FeaturedCard extends StatelessWidget {
  final String imageUrl;

  /// The headline — a venue, track or club name.
  final String title;

  /// Above the title: a category, a club type. Omitted when there is none,
  /// rather than left as an empty line that pushes the title off its baseline.
  final String? kicker;

  /// Below the title, beside a pin: a town, a region, a member count.
  final String? subtitle;

  /// The pin. Null drops the icon and leaves the subtitle on its own, which
  /// is what a member count wants.
  final IconData? subtitleIcon;

  final VoidCallback? onTap;

  /// The gold pill in the top corner. Hidden when false — the carousel is
  /// also used for things that are simply first in a list.
  final bool showFeaturedBadge;

  static const Color _gold = Color(0xFFAE9159);

  const FeaturedCard({
    super.key,
    required this.imageUrl,
    required this.title,
    this.kicker,
    this.subtitle,
    this.subtitleIcon,
    this.onTap,
    this.showFeaturedBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.grey.shade300),

            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => ColoredBox(
                  color: Colors.grey.shade300,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),

            // Bottom-weighted, and stopping short of the top so the badge
            // sits on the photograph rather than on a dark band.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.35, 1.0],
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),

            if (showFeaturedBadge)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 13, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'Featured',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((kicker ?? '').isNotEmpty) ...[
                    Text(
                      kicker!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xD9FFFFFF),
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: Colors.white,
                    ),
                  ),
                  if ((subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (subtitleIcon != null) ...[
                          Icon(subtitleIcon, size: 14, color: Colors.white),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xF2FFFFFF),
                            ),
                          ),
                        ),
                      ],
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
