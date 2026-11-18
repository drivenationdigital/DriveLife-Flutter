import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One thing worth knowing before drawing a road.
@immutable
class RoadTip {
  final IconData icon;
  final String title;
  final String body;

  const RoadTip({
    required this.icon,
    required this.title,
    required this.body,
  });
}

/// The tour of the add-a-road screen, shown once.
///
/// ── WHY THIS SCREEN NEEDS ONE AT ALL ────────────────────────────────
///
/// Because the central idea is not guessable from looking at it. The
/// line somebody draws is NOT the road that gets stored — it is a
/// sketch, routed along the real tarmac afterwards — and without being
/// told that, the obvious reading of a dashed line cutting a corner is
/// that the feature is broken.
///
/// Everything else here follows from that one fact, which is why it is
/// first.
///
/// ── A NOTE ON THE DUPLICATION ───────────────────────────────────────
///
/// discover_tips.dart has the same shape: a list, a seen-flag, and a
/// paged card. The card chrome is worth extracting into one widget the
/// next time either is touched. It is not worth rewriting a live
/// screen's tour to do it today.
abstract final class RoadTips {
  const RoadTips._();

  /// Bump the version to show these again after the screen changes.
  /// The old key is left behind rather than migrated: somebody who saw
  /// v1 has not seen v2, which is the whole point of showing it again.
  static const String _seenKey = 'road_tips_seen_v1';

  static const List<RoadTip> steps = [
    RoadTip(
      icon: Icons.touch_app_outlined,
      title: 'Tap the two ends',
      body:
          'One tap where the road starts, one where it finishes. That is '
          'usually the whole job — you are saying WHICH road, not drawing '
          'its shape.',
    ),
    RoadTip(
      icon: Icons.auto_fix_high_rounded,
      title: 'We follow the tarmac',
      body:
          'Your taps are a sketch, and the line on screen is dashed to say '
          'so. Before it is saved we route it along the real road, so the '
          'stored line bends where the road bends.',
    ),
    RoadTip(
      icon: Icons.alt_route_rounded,
      title: 'Add a point at a junction',
      body:
          'If two roads could get between your ends, the route might take '
          'the wrong one. A tap on the road you mean settles it. Two points '
          'and a junction beat twelve placed roughly.',
    ),
    RoadTip(
      icon: Icons.swap_horiz_rounded,
      title: 'The order is the direction',
      body:
          'Your first tap is the START and the arrows run from it. A road '
          'is a different road the other way — Reverse flips it without '
          'redrawing anything.',
    ),
    RoadTip(
      icon: Icons.open_in_full_rounded,
      title: 'Go full screen',
      body:
          'Tapping precisely is easier with the whole screen. The map keeps '
          'everything you have drawn when you come back out.',
    ),
  ];

  /// Whether the tour has not been seen yet.
  ///
  /// Never throws: if preferences cannot be read, the answer is
  /// "already seen". Showing a tour on every single launch because
  /// storage is unavailable is far worse than never showing it.
  static Future<bool> shouldShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_seenKey) ?? false);
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {
      // Worst case it is offered again next time, which is survivable.
    }
  }
}

/// Shows the tour, and records that it has been.
///
/// [force] is the help button in the corner: somebody asking for the
/// tips has not forgotten them, they want them again.
Future<void> showRoadTips(BuildContext context, {bool force = false}) async {
  if (!force && !await RoadTips.shouldShow()) return;

  if (!context.mounted) return;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close tips',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => const _TipsCard(),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );

      return FadeTransition(
        opacity: curved,
        // Rises slightly as it fades in, rather than appearing flat.
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );

  await RoadTips.markSeen();
}

class _TipsCard extends StatefulWidget {
  const _TipsCard();

  @override
  State<_TipsCard> createState() => _TipsCardState();
}

class _TipsCardState extends State<_TipsCard> {
  final PageController _pages = PageController();

  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _last => _index == RoadTips.steps.length - 1;

  void _next() {
    if (_last) {
      Navigator.of(context).pop();
      return;
    }

    _pages.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFAE9159);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  // Fixed, so the card does not resize between pages —
                  // a dialog that grows and shrinks as you swipe reads
                  // as a layout fault rather than as a tour.
                  height: 290,
                  child: PageView.builder(
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemCount: RoadTips.steps.length,
                    itemBuilder: (_, i) {
                      final tip = RoadTips.steps[i];

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(26, 32, 26, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(tip.icon, size: 26, color: accent),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              tip.title,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0B0B0B),
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              tip.body,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                color: Color(0xFF4A4A4A),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 0, 18, 18),
                  child: Row(
                    children: [
                      for (var i = 0; i < RoadTips.steps.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            width: i == _index ? 18 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == _index
                                  ? accent
                                  : const Color(0xFFDDDDDD),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: _next,
                        child: Text(
                          _last ? 'Got it' : 'Next',
                          style: const TextStyle(
                            color: accent,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
