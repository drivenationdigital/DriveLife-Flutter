import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One destination in the floating bottom bar.
@immutable
class DlNavItem {
  final String label;

  /// Built rather than named so a destination can supply something live —
  /// the account avatar, a badge — instead of a fixed asset.
  final Widget Function(bool selected) icon;

  const DlNavItem({required this.label, required this.icon});
}

/// The floating bottom navigation bar.
///
/// A rounded bar inset from the edges rather than a full-width strip across
/// the bottom. It sits over the content, so the page behind it needs bottom
/// padding of roughly [height] or its last row hides underneath.
class DlBottomNav extends StatelessWidget {
  final List<DlNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// How much vertical room the bar occupies, before the safe area.
  ///
  /// Shorter than it was. At 74 the corner radius could never catch up with
  /// the height, so the ends read as rounded corners on a rectangle rather
  /// than as the ends of a pill — which is the difference you can see
  /// against Uber's.
  static const double height = 62;

  /// Inset of the travelling highlight from the bar's own edges.
  static const double _inset = 7;

  /// Shared by the travelling highlight and the labels it passes under, so
  /// the colour change lands with the pill rather than trailing behind it.
  static const Duration _duration = Duration(milliseconds: 260);
  static const Curve _curve = Curves.easeOutCubic;

  const DlBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            // Half the height: a true stadium, so the ends are semicircles
            // rather than corners. Anything less and the straight section
            // between them is what the eye reads.
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: [
              // Two shadows: a tight one to lift the bar off the content and
              // a wide soft one to ground it. A single shadow either looks
              // pasted on or smudged.
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          // The highlight is a single widget behind the row rather than a
          // background on each item. That is the whole difference between it
          // sliding to the tab you picked and it fading out in one place
          // while fading in somewhere else — the second reads as two things
          // happening, the first as one thing moving.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / items.length;

              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: _duration,
                    curve: _curve,
                    left: slot * currentIndex,
                    top: _inset,
                    bottom: _inset,
                    width: slot,
                    child: Center(
                      child: Container(
                        // Every pill the same width, sized to the slot rather
                        // than to its own label. Hugging each label would
                        // make the highlight grow and shrink as it travelled,
                        // which draws the eye to the wrong thing.
                        width: slot - 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F2),
                          // Also a stadium, and for the same reason: a
                          // rounded rectangle travelling inside a pill looks
                          // like a different shape loose in the bar.
                          borderRadius: BorderRadius.circular(
                            (height - _inset * 2) / 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _Item(
                            item: items[i],
                            selected: i == currentIndex,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onChanged(i);
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final DlNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _Item({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const duration = DlBottomNav._duration;
    const curve = DlBottomNav._curve;

    return GestureDetector(
      onTap: onTap,
      // Opaque so the whole column is tappable, not just the glyph. A nav
      // item you have to hit precisely is the most-used fiddly target in an
      // app.
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Padding(
          // Tighter than it looks it should be. Six destinations on a narrow
          // phone leave about 44 logical pixels a slot, and the padding is
          // the first thing that has to give.
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              item.icon(selected),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: duration,
                curve: curve,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? const Color(0xFF111111)
                      : const Color(0xFF9A9A9A),
                ),
                // Shrinks to fit rather than wrapping or clipping. At six
                // destinations "Discover" is wider than its slot on a small
                // screen; scaling it down keeps the word readable, where an
                // ellipsis would turn it into "Disco…" and a wrap would make
                // one item taller than the rest.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
