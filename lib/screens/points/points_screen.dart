import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/points_api.dart';
import 'package:drivelife/providers/points_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/points/points_history_screen.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Points, and the leaderboard.
///
/// NOTHING AWARDS POINTS YET, so this screen is honestly empty: zero in
/// the headline, no rank, and no rows. It is built that way on purpose
/// rather than padded with placeholder names — a leaderboard of invented
/// people is worse than an empty one, because the first real user cannot
/// tell which is which.
class PointsScreen extends StatefulWidget {
  const PointsScreen({super.key});

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  static const Color _ink = Color(0xFF111113);
  static const Color _gold = Color(0xFFAE9159);

  LeaderboardScope _scope = LeaderboardScope.worldwide;

  List<LeaderboardEntry> _entries = const [];
  MyPoints _me = MyPoints.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final result = await PointsAPI.leaderboard(scope: _scope);
    if (!mounted) return;

    setState(() {
      _entries = result.entries;
      _me = result.me;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: RefreshIndicator(
        onRefresh: _load,
        color: theme.primaryColor,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _hero(theme)),
            SliverToBoxAdapter(child: _boardHeader(theme)),

            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 56),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_entries.isEmpty)
              SliverToBoxAdapter(child: _empty(theme))
            else
              SliverList.separated(
                itemCount: _entries.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: theme.dividerColor),
                itemBuilder: (context, i) => _row(theme, _entries[i]),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  /// The headline: your total, over the backdrop.
  Widget _hero(ThemeProvider theme) {
    return Stack(
      children: [
        // The photograph fills whatever height the content below turns
        // out to be. The Stack takes its size from the SafeArea child,
        // which is the only non-positioned one — so the backdrop follows
        // the text rather than the text having to fit a fixed image.
        Positioned.fill(
          child: Image.asset(
            'assets/bg-points.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            // The file is 2.4MB and decodes to something far larger in
            // memory. Capping the decode at roughly the width it is
            // drawn at costs nothing visually and avoids holding a
            // full-resolution bitmap for a background.
            cacheWidth:
                (MediaQuery.sizeOf(context).width *
                        MediaQuery.devicePixelRatioOf(context))
                    .round(),
          ),
        ),

        // A wash over it, fading to the page colour at the bottom.
        //
        // Two jobs: it keeps the photograph from competing with the
        // number, which is the one thing this screen exists to show,
        // and it hands over to the white page underneath with no seam.
        // IgnorePointer because a filled box in a Stack swallows taps
        // over everything it covers — including the back button.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.backgroundColor.withValues(alpha: 0.78),
                    theme.backgroundColor.withValues(alpha: 0.42),
                    theme.backgroundColor,
                  ],
                  // The middle stop sits where the car is, so it shows
                  // through there and nowhere it would fight the type.
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
          ),
        ),

        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _CircleButton(
                    icon: Icons.arrow_back_ios_new,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 24),

                // The heading, with the rules a tap away.
                //
                // mainAxisSize.min and centred, because everything below
                // is centred: a Row left to fill the width would put the
                // heading hard left and the icon hard right.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DlHeading(
                      'Your points',
                      fontSize: 22,
                      color: theme.subtextColor,
                    ),
                    const SizedBox(width: 2),
                    _infoButton(theme),
                  ],
                ),
                const SizedBox(height: 2),

                // The number, as big as it can reasonably be. It is the one
                // thing this screen exists to tell somebody.
                //
                // And it opens the history, because "why is it that
                // number" is the immediate next question and the number
                // is what somebody is looking at when they ask it.
                //
                // behavior.opaque, so the whole box takes the tap rather
                // than only the glyphs — a 76pt number has a lot of
                // empty space inside its bounds.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const PointsHistoryScreen(),
                    ),
                  ),
                  child: Column(
                    children: [
                      DlHeading(
                        _formatPoints(_me.current),
                        fontSize: 76,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        color: theme.textColor,
                      ),
                      const SizedBox(height: 4),
                      // Says it is tappable. A big number gives no hint
                      // on its own, and nobody taps a total on the
                      // chance that something happens.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'See where these came from',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.subtextColor,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: theme.subtextColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Only when there IS a rank. Before anything awards points
                // everybody is on zero, and "#1" or "#40,000" would both be
                // lies — so the pill is simply absent.
                if (_me.rank != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: _ink,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      'You are #${_formatPoints(_me.rank!)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),

                const SizedBox(height: 20),
                Text(
                  'Collect points to redeem against event tickets, DriveLife '
                  'merchandise and services from our partners. Points '
                  'redemption coming soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.45,
                    color: theme.subtextColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _boardHeader(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: DlHeading(
              'Leaderboard',
              fontSize: 26,
              color: theme.textColor,
            ),
          ),
          _scopePicker(theme),
        ],
      ),
    );
  }

  Widget _scopePicker(ThemeProvider theme) {
    return PopupMenuButton<LeaderboardScope>(
      initialValue: _scope,
      onSelected: (scope) {
        if (scope == _scope) return;
        setState(() => _scope = scope);
        _load();
      },
      itemBuilder: (_) => [
        for (final scope in LeaderboardScope.values)
          PopupMenuItem(value: scope, child: Text(scope.label)),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _scope.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: theme.textColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 20, color: theme.textColor),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeProvider theme, LeaderboardEntry entry) {
    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.viewProfile,
        arguments: {'userId': '${entry.userId}', 'username': entry.username},
      ),
      child: Container(
        // Yours is tinted, so you can find it without reading the names.
        color: entry.isMe
            ? theme.primaryColor.withValues(alpha: 0.07)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  // The top three in gold, the rest grey. A podium
                  // without three different metals: the rank number is
                  // small and bronze against grey is not legible at this
                  // size.
                  color: entry.rank <= 3
                      ? theme.primaryColor
                      : theme.subtextColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _avatar(entry),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.bestName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.textColor,
                    ),
                  ),
                  if (entry.country.isNotEmpty)
                    Text(
                      entry.country,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: theme.subtextColor),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formatPoints(entry.points),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: theme.textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(LeaderboardEntry entry) {
    const size = 44.0;

    if (entry.avatar.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFFE8E8E8),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          entry.bestName.isEmpty ? '?' : entry.bestName[0].toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF8A8A8A),
          ),
        ),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: entry.avatar,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
          width: size,
          height: size,
          color: const Color(0xFFE8E8E8),
        ),
        errorWidget: (_, _, _) => Container(
          width: size,
          height: size,
          color: const Color(0xFFE8E8E8),
        ),
      ),
    );
  }

  /// Said plainly, because it is true and temporary.
  Widget _empty(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
      child: Column(
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 44,
            color: theme.dividerColor,
          ),
          const SizedBox(height: 14),
          Text(
            'Nobody on the board yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _scope == LeaderboardScope.country
                ? 'Nobody in your country has earned points yet.'
                : 'Points are coming soon. Once they are live, this is '
                      'where you will see how you compare.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.4,
              color: theme.subtextColor,
            ),
          ),
        ],
      ),
    );
  }

  /// "2,140". Thousands separated — on your own total the exact number
  /// is the interesting part, and "2.1k" throws away what you earned
  /// this week.
  /// A 15px info mark beside the heading.
  ///
  /// Deliberately small: the rules are worth having but are not what
  /// somebody opened this screen to read. The tap target is padded out
  /// so it is still reachable — the icon is well under the minimum on
  /// its own.
  Widget _infoButton(ThemeProvider theme) {
    return GestureDetector(
      onTap: _showRules,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(Icons.info_outline, size: 15, color: theme.subtextColor),
      ),
    );
  }

  /// How points work, in as few words as it can be said.
  ///
  /// THE WORDS COME FROM THE SERVER, built from the same rules that pay
  /// the points — so the sentence and the amounts in it cannot disagree,
  /// and wording that turns out to be wrong can be corrected without a
  /// release.
  ///
  /// A snackbar rather than a dialog: it is a reminder, not a decision,
  /// and a dialog would demand a dismissal for something nobody has to
  /// act on. Eight seconds and a Got it, so it can be read at leisure
  /// or waved away.
  void _showRules() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          context.read<PointsProvider>().rules.summary,
          style: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Colors.white,
          ),
        ),
        action: SnackBarAction(
          label: 'Got it',
          textColor: _gold,
          onPressed: () {},
        ),
      ),
    );
  }

  static String _formatPoints(int n) {
    final s = n.toString();
    final buffer = StringBuffer();

    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }

    return buffer.toString();
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.arrow_back_ios_new, size: 17, color: Colors.black),
        ),
      ),
    );
  }
}
