import 'package:flutter/material.dart';

/// The gap between two posts.
///
/// A band of #E6E6E6 with the post above casting a short shadow onto
/// it. Replaces the 1px hairline that was here: a line separates two
/// things, a band with a shadow makes the one above read as a card
/// sitting on a background, which is what the design asks for.
///
/// ── WHY THE SHADOW IS DRAWN HERE ────────────────────────────────────
///
/// It belongs to the card above, but it cannot be painted by it. A
/// Column paints its children in order, so a BoxShadow on the card
/// would be covered by this band the moment it was drawn — the band
/// comes after. Putting a short dark-to-clear gradient at the TOP of
/// the band produces the same picture in the right paint order.
///
/// Shared by the home feed and a group's Latest tab, so the two cannot
/// drift. Both draw it between rows rather than inside a card, because
/// only the list knows which row is last — and a separator under the
/// final item is an edge with nothing beyond it.
class FeedDivider extends StatelessWidget {
  const FeedDivider({super.key});

  /// The band itself.
  static const Color background = Color(0xFFE6E6E6);

  /// How tall the whole gap is.
  static const double height = 10;

  /// How far the shadow reaches down it.
  ///
  /// Short on purpose: the shadow is there to lift the card's edge, and
  /// anything deeper reads as a gradient somebody chose rather than as
  /// a shadow something is casting.
  static const double _shadow = 3;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: height,
      width: double.infinity,
      child: ColoredBox(
        color: background,
        child: Column(
          // Stretch, or the gradient would size to its own content —
          // which is nothing — and never appear.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _shadow,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x1A000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
