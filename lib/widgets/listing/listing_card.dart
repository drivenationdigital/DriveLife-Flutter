import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A card in the two-column grid on a listing screen.
///
/// Picture, name, where it is, and one button. The button is the point: the
/// card used to be a wide row whose whole surface was the tap target, which
/// works but tells you nothing about what tapping does. "View" says it, and
/// it gives the card a bottom edge to end on.
///
/// The whole card is still tappable. The button is there to be read, not to
/// be the only way in.
class ListingCard extends StatelessWidget {
  final String imageUrl;
  final String title;

  /// Under the title — an address, a club type. Two lines at most.
  final String? subtitle;

  /// Shows the gold tick beside the title.
  final bool isVerified;

  /// The button's words. "View" on a place, and whatever else suits
  /// elsewhere.
  final String actionLabel;

  final VoidCallback? onTap;

  static const Color _gold = Color(0xFFAE9159);

  const ListingCard({
    super.key,
    required this.imageUrl,
    required this.title,
    this.subtitle,
    this.isVerified = false,
    this.actionLabel = 'View',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEDEDED)),
          ),
          // Fills the grid cell rather than hugging its contents.
          //
          // It used to shrink to fit, so the column ended wherever the
          // address did and the button sat directly under it — under one
          // line on one card and two on the next, leaving a row of buttons
          // at two different heights. The cell is a fixed size either way.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(13),
                ),
                child: AspectRatio(
                  // Fixed, so two cards side by side line their titles up
                  // whatever shape the photographs happen to be.
                  aspectRatio: 1.35,
                  child: _picture(),
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Takes whatever is left once the button has had its
                      // 38, so the button lands on the bottom edge every
                      // time and the text gives way instead of overflowing
                      // when a title runs long or a platform's font metrics
                      // run tall. iOS measures these a little taller than
                      // Android, which is where this first showed up.
                      Expanded(child: _text()),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        height: 38,
                        child: OutlinedButton(
                          onPressed: onTap,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _gold,
                            side: const BorderSide(color: _gold),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(19),
                            ),
                          ),
                          child: Text(
                            actionLabel,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _picture() {
    if (imageUrl.isEmpty) return _placeholder();

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (_, _) => ColoredBox(color: Colors.grey.shade200),
      errorWidget: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey.shade400,
      ),
    );
  }

  Widget _text() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: Color(0xFF111111),
                ),
              ),
            ),
            if (isVerified) ...[
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.verified, size: 16, color: _gold),
              ),
            ],
          ],
        ),

        if ((subtitle ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          // Flexible, not plain: when the cell is tight this is what gives,
          // rather than the column overflowing its cell.
          Flexible(
            child: Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: Color(0xFF8A8A8E),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
