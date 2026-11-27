import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/videos_api.dart';
import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/media/video_watch_screen.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The line under an episode's title.
///
/// ── NO EPISODE NUMBERS, AND WHY NOT ─────────────────────────────────
///
/// The design showed "Ep 42 · 38 min". Nothing stores an episode
/// number, and deriving one from a position in a list would be a number
/// that changes whenever something is published, unpublished or deleted
/// - which is the worst kind of wrong, because it looks authoritative.
///
/// So this is the date and the length, both of which are true. An
/// `episode_number` column is a small change when somebody wants one.
///
/// Shared with the podcast block on the Watch tab, so the two cannot
/// drift into formatting the same episode differently.
String podcastMeta(LongVideo episode) {
  final parts = <String>[];

  final published = episode.publishedAt;

  if (published != null) parts.add(_podcastDate(published));

  final seconds = episode.durationSeconds;

  if (seconds >= 60) {
    // Minutes, not 38:14. Nobody picks a podcast by its seconds.
    parts.add('${(seconds / 60).round()} min');
  } else if (seconds > 0) {
    parts.add('$seconds sec');
  }

  return parts.join(' · ');
}

String _podcastDate(DateTime value) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  final local = value.toLocal();

  return '${local.day} ${months[local.month - 1]}';
}

/// Every episode of the DriveLife podcast.
///
/// ── WHAT MAKES SOMETHING AN EPISODE ─────────────────────────────────
///
/// Who published it, and nothing else. The server decides - see
/// DL_PODCAST_USER_IDS in endpoints/videos.php - and this screen simply
/// asks for `podcast: true`. There is no second kind of upload, no flag
/// on the create form, and nothing for anybody to set wrongly.
///
/// ── THE BLOCK IS DARK, THIS PAGE IS NOT ─────────────────────────────
///
/// The podcast panel on the Watch tab is inverted against a light page
/// on purpose: it is one block among several and the inversion is what
/// separates it from the video rows around it.
///
/// A whole screen has nothing to separate itself FROM, so the same
/// trick stops being a signal and becomes just a dark page in a light
/// app. This one follows the app like every other screen.
///
/// Colours come from ThemeProvider rather than being pinned white, so
/// the dark-mode branch picks this up with nothing further to do.
class PodcastScreen extends StatefulWidget {
  const PodcastScreen({super.key});

  @override
  State<PodcastScreen> createState() => _PodcastScreenState();
}

class _PodcastScreenState extends State<PodcastScreen> {
  static const Color _gold = Color(0xFFAE9159);

  /// Behind a thumbnail that has not arrived, and behind the skeleton
  /// blocks. Follows the theme: a pale block is invisible on a dark
  /// page and a dark one is invisible on a light page.
  static Color _block(ThemeProvider theme) =>
      theme.isDarkMode ? const Color(0xFF242424) : const Color(0xFFE8E8E8);

  List<LongVideo> _episodes = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);

    try {
      // 50 is the server's ceiling. A podcast that outgrows it needs
      // paging, which is worth doing when there is something to page.
      final episodes = await VideosAPI.list(limit: 50, podcast: true);

      if (!mounted) return;

      setState(() {
        _episodes = episodes;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[podcast] load failed: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Could not load the podcast.';
      });
    }
  }

  Future<void> _open(LongVideo episode) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VideoWatchScreen(video: episode)),
    );

    // Watching changes the view count and may fill in a duration the
    // server did not have - see dl_videos_record_view.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        surfaceTintColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: DlHeading(
          'DriveLife podcast',
          fontSize: 21,
          color: theme.textColor,
        ),
      ),
      body: RefreshIndicator(
        color: _gold,
        backgroundColor: theme.backgroundColor,
        onRefresh: _load,
        child: _body(theme),
      ),
    );
  }

  Widget _body(ThemeProvider theme) {
    if (_loading) return _PodcastSkeleton(theme: theme);

    if (_error != null) {
      return _message(theme, _error!, onRetry: _load);
    }

    if (_episodes.isEmpty) {
      return _message(
        theme,
        'No episodes yet.\nThey will appear here as they are published.',
      );
    }

    final latest = _episodes.first;
    final rest = _episodes.skip(1).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _latest(theme, latest),
        const SizedBox(height: 22),
        for (final episode in rest) ...[
          _row(theme, episode),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  /// The newest one, given the room a new thing deserves.
  /// The newest episode.
  ///
  /// Its text stays white whatever the theme is, because it is drawn
  /// over a photograph behind a scrim rather than on the page.
  Widget _latest(ThemeProvider theme, LongVideo episode) {
    return GestureDetector(
      onTap: () => _open(episode),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _thumbnail(theme, episode.thumbnailUrl),
              const _Scrim(),
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Text(
                    'LATEST EPISODE',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              const Center(
                child: _PlayCircle(size: 62, iconSize: 28),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      podcastMeta(episode),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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

  Widget _row(ThemeProvider theme, LongVideo episode) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(episode),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: 104,
              height: 66,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _thumbnail(theme, episode.thumbnailUrl),
                  const Positioned(
                    left: 7,
                    bottom: 7,
                    child: _PlayCircle(size: 24, iconSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  episode.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  podcastMeta(episode),
                  style: TextStyle(
                    color: theme.subtextColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(
    ThemeProvider theme,
    String text, {
    Future<void> Function()? onRetry,
  }) {
    // A ListView, not a Column: RefreshIndicator needs something
    // scrollable under it or pulling down does nothing on the one
    // screen where somebody most wants to try again.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.subtextColor,
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => onRetry(),
              style: TextButton.styleFrom(foregroundColor: _gold),
              child: const Text('Try again'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _thumbnail(ThemeProvider theme, String url) {
    final empty = ColoredBox(color: _block(theme));

    if (url.isEmpty) return empty;

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => empty,
      errorWidget: (_, __, ___) => empty,
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x73000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0xBF000000),
          ],
          stops: [0, 0.3, 0.5, 1],
        ),
      ),
    );
  }
}

class _PlayCircle extends StatelessWidget {
  const _PlayCircle({required this.size, required this.iconSize});

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        size: iconSize,
        color: const Color(0xFF111111),
      ),
    );
  }
}

/// The shape of the page while it loads, rather than a spinner in the
/// middle of a black screen.
class _PodcastSkeleton extends StatelessWidget {
  const _PodcastSkeleton({required this.theme});

  final ThemeProvider theme;

  @override
  Widget build(BuildContext context) {
    final block = _PodcastScreenState._block(theme);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: Container(
            decoration: BoxDecoration(
              color: block,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < 4; i++) ...[
          Row(
            children: [
              Container(
                width: 104,
                height: 66,
                decoration: BoxDecoration(
                  color: block,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 13, color: block),
                    const SizedBox(height: 7),
                    FractionallySizedBox(
                      widthFactor: 0.6,
                      child: Container(height: 13, color: block),
                    ),
                    const SizedBox(height: 7),
                    FractionallySizedBox(
                      widthFactor: 0.3,
                      child: Container(height: 11, color: block),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}
