import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Somebody's profile photograph, in a circle.
///
/// ── WHY THIS IS NOT JUST A CircleAvatar ─────────────────────────────
///
/// It was, with a plain `NetworkImage`, and that is expensive in two
/// ways that only show up on the screens this widget is used on -
/// the feed, notifications, followers, profiles. All of them are long
/// scrolling lists of small circles.
///
/// 1. **No disk cache.** `NetworkImage` keeps decoded frames in
///    Flutter's in-memory cache and nothing on disk, so every avatar
///    is downloaded again from cold on every app launch. On a feed
///    that is dozens of requests before anybody has scrolled.
///
/// 2. **No bound on decoding.** A profile photograph is whatever the
///    owner uploaded - commonly 1000x1000 or larger. Decoded, that is
///    4MB of RAM, held to draw a circle 40 points across. Fifty of
///    them in a list is 200MB and a jettisoned app on an older phone.
///
/// [ResizeImage] fixes the second by decoding straight to the size
/// actually drawn, and [CachedNetworkImageProvider] fixes the first.
class ProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final VoidCallback? onTap;

  const ProfileAvatar({super.key, this.imageUrl, this.radius = 20, this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundImage: hasImage
          ? _provider(context)
          : const AssetImage('assets/profile-placeholder.jpg') as ImageProvider,
      // Always safe to pass here: backgroundImage is never null — a
      // missing photo already falls back to the bundled placeholder,
      // so the assert that pairs these two cannot fire.
      onBackgroundImageError: (_, _) {},
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }

    return avatar;
  }

  /// The photograph, cached on disk and decoded to the size drawn.
  ///
  /// Width ONLY, never both dimensions. [ResizeImage] defaults to
  /// `ResizeImagePolicy.exact`, which honours both and squashes
  /// anything whose aspect ratio does not match - and a profile
  /// photograph is rarely square. Given one dimension it keeps the
  /// ratio, and CircleAvatar crops the rest.
  ImageProvider _provider(BuildContext context) {
    // Device pixels, not logical ones: a 20-point radius is 120
    // physical pixels across on a 3x screen, and decoding to 40 would
    // draw a visibly soft avatar.
    final pixels = (radius * 2 * MediaQuery.devicePixelRatioOf(context))
        .round()
        // A floor rather than trusting the arithmetic. A radius of 0
        // during a layout pass would otherwise ask for a 0-wide decode,
        // which throws.
        .clamp(32, 512);

    return ResizeImage(
      CachedNetworkImageProvider(imageUrl!),
      width: pixels,
      // Keeps the decoded frame in the memory cache under its RESIZED
      // key. Without it two avatars of the same person at different
      // radii share one cache entry and the smaller one wins, so the
      // large profile header renders from a thumbnail.
      allowUpscaling: false,
    );
  }
}
