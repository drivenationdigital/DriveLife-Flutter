import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A result in a listing — a venue, a track.
///
/// A row rather than a card in a grid. A grid shows the photographs bigger
/// and fewer; this shows four or five results in the space two cards took,
/// and the thing people scan for in a list of places is the name and where
/// it is, not the picture. The picture is here to tell them apart, which a
/// thumbnail does.
///
/// The chevron is doing real work: it is the only thing on the row that says
/// it opens something, now that there is no button.
class ListingRow extends StatelessWidget {
  final String imageUrl;
  final String title;

  /// Under the name — an address, usually. One line, clipped: an address is
  /// recognised from its beginning, and a row that grows to fit the longest
  /// one makes every other row look wrong.
  final String? subtitle;

  /// Shows the gold tick beside the name.
  final bool isVerified;

  final VoidCallback? onTap;

  static const Color _gold = Color(0xFFAE9159);

  /// The thumbnail's side.
  ///
  /// 48, which with 10 of padding either side makes a 68pt row. Instagram
  /// runs 44 avatars in its own lists at about 62 — this sits just above
  /// that, which suits a photograph where theirs is a face.
  ///
  /// It was 56 in a 80pt row, and on the Clubs tab that meant three rows
  /// under everything stacked above them.
  static const double _thumb = 48;

  const ListingRow({
    super.key,
    required this.imageUrl,
    required this.title,
    this.subtitle,
    this.isVerified = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: _thumb,
                  height: _thumb,
                  child: _picture(),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              color: Color(0xFF111111),
                            ),
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.verified, size: 14, color: _gold),
                        ],
                      ],
                    ),

                    if ((subtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: Color(0xFF8A8A8E),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),

              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFFBDBDBD),
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
        size: 20,
        color: Colors.grey.shade400,
      ),
    );
  }
}

/// The hairline between two [ListingRow]s.
///
/// Inset past the thumbnail so it reads as separating the text, which is
/// what the eye is following down the list.
class ListingRowDivider extends StatelessWidget {
  const ListingRowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: Color(0xFFEFEFEF),
    );
  }
}
