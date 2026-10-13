import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One thing worth knowing about the Discover map.
@immutable
class DiscoverTip {
  final IconData icon;
  final String title;
  final String body;

  const DiscoverTip({
    required this.icon,
    required this.title,
    required this.body,
  });
}

/// The tour of the Discover map, shown once.
///
/// Ordered by what someone needs first: what they are looking at, then the
/// one thing on screen that is not self-explanatory, then the controls, then
/// the gesture nothing else would reveal.
abstract final class DiscoverTips {
  const DiscoverTips._();

  /// Bump the version to show these again after the page changes. The old key
  /// is left behind rather than migrated: someone who saw v1 has not seen v2,
  /// which is the whole point of showing it again.
  static const String _seenKey = 'discover_tips_seen_v1';

  static const List<DiscoverTip> steps = [
    DiscoverTip(
      icon: Icons.explore_outlined,
      title: 'Everything nearby',
      body:
          'Events and venues around you, on one map. The coloured pins match '
          'the categories in the row at the top.',
    ),
    DiscoverTip(
      icon: Icons.filter_tilt_shift_rounded,
      title: 'Numbers are groups',
      body:
          'A circle with a number means several results are close together. '
          'Tap it to zoom in and they separate into individual pins.',
    ),
    DiscoverTip(
      icon: Icons.search_rounded,
      title: 'Two halves, two jobs',
      body:
          'The left of the search bar finds something by name. The right '
          'changes where you are looking.',
    ),
    DiscoverTip(
      icon: Icons.touch_app_outlined,
      title: 'Press and hold the map',
      body:
          'Hold anywhere to search that spot — useful for places with no '
          'name worth typing, like a stretch of coast or a meeting point.',
    ),
    DiscoverTip(
      icon: Icons.tune_rounded,
      title: 'Narrow it down',
      body:
          'The filter button sets categories, dates and distance. Drag the '
          'panel at the bottom up for the full list.',
    ),
  ];

  /// Whether the tour has not been seen yet.
  ///
  /// Never throws: if preferences cannot be read, the answer is "already
  /// seen". Showing a tour on every single launch because storage is
  /// unavailable is far worse than never showing it.
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
/// A route rather than a widget in the screen's Stack, so the scrim covers
/// the floating bottom bar as well — that is drawn by the shell above this
/// screen, and anything inside the screen's own Stack would leave it lit.
Future<void> showDiscoverTips(BuildContext context) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close tips',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => const _TipsCard(),
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

  await DiscoverTips.markSeen();
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

  bool get _isLast => _index == DiscoverTips.steps.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fixed height: the steps have different amounts of text, and a
              // card that resized between them would jump on every tap.
              SizedBox(
                height: 236,
                child: PageView.builder(
                  controller: _pages,
                  itemCount: DiscoverTips.steps.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _Step(DiscoverTips.steps[i]),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Row(
                  children: [
                    for (var i = 0; i < DiscoverTips.steps.length; i++) ...[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: i == _index ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _index
                              ? const Color(0xFF1C1C1E)
                              : const Color(0xFFE0E0E0),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    const Spacer(),
                    // Always available. A tour you cannot leave until the end
                    // is a dialog, not a tip.
                    if (!_isLast)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF8A8A8E),
                        ),
                        child: const Text('Skip'),
                      ),
                    const SizedBox(width: 4),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1C1C1E),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      onPressed: _next,
                      child: Text(
                        _isLast ? 'Got it' : 'Next',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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
    );
  }
}

class _Step extends StatelessWidget {
  final DiscoverTip tip;

  const _Step(this.tip);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFBF8F1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2D2AC), width: 1.2),
            ),
            child: Icon(tip.icon, size: 22, color: const Color(0xFFB08E4F)),
          ),
          const SizedBox(height: 16),
          Text(
            tip.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tip.body,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: Color(0xFF8A8A8E),
            ),
          ),
        ],
      ),
    );
  }
}
