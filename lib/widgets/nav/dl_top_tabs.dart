import 'package:flutter/material.dart';
import 'package:drivelife/widgets/nav/dl_haptics.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One section in the top tab row.
@immutable
class DlTopTab {
  final String label;

  /// Path to an SVG in assets/app-icons. Null when [glyph] is used instead.
  final String? icon;

  /// A Material icon, for tabs that have no SVG drawn for them yet.
  ///
  /// Both exist because the icon set is incomplete: there is no chequered
  /// flag or briefcase in assets/app-icons, and waiting for one would mean
  /// two tabs sharing the Places pin and meaning nothing by it. A tab with a
  /// glyph swaps to an SVG by changing this one line.
  final IconData? glyph;

  const DlTopTab({required this.label, this.icon, this.glyph})
    : assert(
        icon != null || glyph != null,
        'A tab needs something to draw: an SVG path or a Material icon.',
      );
}

/// The section switcher that sits under the header.
///
/// Scrolls horizontally rather than squeezing: the labels are words, not
/// abbreviations, and four of them do not fit a phone at a readable size. The
/// row deliberately runs off the right edge so it reads as scrollable instead
/// of looking like a cramped segmented control.
class DlTopTabs extends StatefulWidget {
  /// Fixed, and declared rather than measured.
  ///
  /// The row rides in a sliver header, which has to know its extent before
  /// it is laid out. 5 top padding + 7/9 around a 34 chip + 1 divider.
  ///
  /// Trimmed from 64. Six points off every screen that carries it, and the
  /// chips still clear a 44pt touch target with the row's own padding.
  static const double height = 56;

  final List<DlTopTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  const DlTopTabs({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  State<DlTopTabs> createState() => _DlTopTabsState();
}

class _DlTopTabsState extends State<DlTopTabs> {
  final ScrollController _scroll = ScrollController();

  /// One key per tab, so the selected one can be scrolled into view without
  /// guessing at widths — the labels differ in length, so arithmetic would
  /// drift.
  late List<GlobalKey> _keys = List.generate(
    widget.tabs.length,
    (_) => GlobalKey(),
  );

  @override
  void didUpdateWidget(DlTopTabs old) {
    super.didUpdateWidget(old);

    if (old.tabs.length != widget.tabs.length) {
      _keys = List.generate(widget.tabs.length, (_) => GlobalKey());
    }

    if (old.currentIndex != widget.currentIndex) _revealSelected();
  }

  /// Brings the selected tab fully into view.
  ///
  /// Without this, selecting a tab that is half off the edge leaves it half
  /// off the edge — the row looks broken rather than scrolled.
  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _keys.elementAtOrNull(widget.currentIndex);
      final ctx = key?.currentContext;
      if (ctx == null) return;

      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: DlTopTabs.height,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 5, 14, 0),
            child: Row(
              children: [
                for (var i = 0; i < widget.tabs.length; i++)
                  _Tab(
                    key: _keys[i],
                    tab: widget.tabs[i],
                    selected: i == widget.currentIndex,
                    onTap: () {
                      if (i == widget.currentIndex) return;
                      DLHaptics.tabChange();
                      widget.onChanged(i);
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEDEDED)),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final DlTopTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
    super.key,
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 220);
    const curve = Curves.easeOutCubic;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        // Generous, because the tabs are icon-and-label pairs rather than
        // bare words: too close together and two tabs read as one control.
        padding: const EdgeInsets.symmetric(horizontal: 14),
        // A Stack so the underline can span the tab's own width without
        // anybody having to know what that is.
        //
        // It used to be a Column with `width: double.infinity`, which is a
        // perfectly ordinary way to say "as wide as my parent" — except this
        // row scrolls horizontally, so the parent's width IS infinity and
        // the constraint assertion fires on the first frame. Inside a Stack,
        // left/right 0 resolves against the sized child instead.
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 7, 0, 9),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: duration,
                    curve: curve,
                    width: 38,
                    height: 34,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF111111)
                          : const Color(0xFFF4F4F4),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      // Gold on black reads as the brand; grey on grey would
                      // be invisible at this size.
                      child: tab.icon != null
                          ? SvgPicture.asset(
                              tab.icon!,
                              width: 18,
                              height: 18,
                              colorFilter: ColorFilter.mode(
                                selected
                                    ? const Color(0xFFC9A449)
                                    : const Color(0xFF9A9A9A),
                                BlendMode.srcIn,
                              ),
                            )
                          : Icon(
                              tab.glyph,
                              size: 17,
                              color: selected
                                  ? const Color(0xFFC9A449)
                                  : const Color(0xFF9A9A9A),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedDefaultTextStyle(
                    duration: duration,
                    curve: curve,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? const Color(0xFF111111)
                          : const Color(0xFF8E8E8E),
                    ),
                    child: Text(tab.label),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),

            // The underline. Grows out from the middle rather than fading,
            // so the selection reads as moving between tabs instead of
            // blinking out in one place and in again somewhere else.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedScale(
                duration: duration,
                curve: curve,
                scale: selected ? 1 : 0,
                child: Container(
                  height: 3,
                  decoration: const BoxDecoration(
                    color: Color(0xFF111111),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
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
