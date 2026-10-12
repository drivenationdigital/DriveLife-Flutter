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
  static const double height = 74;

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
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
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
                    top: 10,
                    bottom: 10,
                    width: slot,
                    child: Center(
                      child: Container(
                        // Every pill the same width, sized to the slot rather
                        // than to its own label. Hugging each label would
                        // make the highlight grow and shrink as it travelled,
                        // which draws the eye to the wrong thing.
                        width: slot - 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(16),
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                child: Text(item.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
