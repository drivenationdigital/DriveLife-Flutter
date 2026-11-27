import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/creators_api.dart';
import 'package:drivelife/api/videos_api.dart';
import 'package:drivelife/models/creator.dart';
import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/media/video_watch_screen.dart';
import 'package:drivelife/services/watch_progress.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:drivelife/widgets/media/video_list_row.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// One creator, and everything of theirs DriveLife has.
///
/// ── WHERE THE VIDEOS COME FROM ──────────────────────────────────────
///
/// ce_videos.creator_id, asked for by id - so this is the same list
/// the rest of the app reads, filtered. A creator's videos are not a
/// separate thing with its own storage; they are the DriveLife video
/// library with one column matched.
///
/// Which also means everything already works on them: tapping one
/// opens the ordinary watch screen, with its likes, its comments and
/// its resume position.
class CreatorScreen extends StatefulWidget {
  const CreatorScreen({super.key, required this.creator});

  final Creator creator;

  @override
  State<CreatorScreen> createState() => _CreatorScreenState();
}

class _CreatorScreenState extends State<CreatorScreen> {
  static const Color _gold = Color(0xFFAE9159);

  /// Held in state rather than read from the widget: following
  /// changes it, and the button has to redraw before the request
  /// comes back or it feels broken.
  late Creator _creator = widget.creator;

  bool _following = false;

  List<LongVideo> _videos = const [];
  List<LongVideo> _shorts = const [];
  bool _loading = true;

  /// Which tab is open.
  ///
  /// Split by [LongVideo.isShort], which the server decided once when
  /// each video was stored - a Short in a 16:9 row is mostly black
  /// bars, and a row of them next to full videos makes both look
  /// wrong.
  bool _showingShorts = false;

  /// What the open tab shows.
  List<LongVideo> get _current => _showingShorts ? _shorts : _videos;

  /// Seconds watched, by post id. Absent means not started.
  Map<String, int> _watched = const {};

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    // Together: the list is useless a moment before the marks on it,
    // and two sequential awaits would show the rows then move them.
    // Both tabs at once. Fetching the second when it is opened would
    // mean a spinner on a tap that looks like it should be instant,
    // and a creator's catalogue is fifty rows at most.
    final results = await (
      VideosAPI.list(limit: 50, creatorId: _creator.id, shorts: false),
      VideosAPI.list(limit: 50, creatorId: _creator.id, shorts: true),
      WatchProgress.positions(),
    ).wait;

    if (!mounted) return;

    setState(() {
      _videos = results.$1;
      _shorts = results.$2;
      _watched = results.$3;
      _loading = false;
    });
  }

  Future<void> _open(LongVideo video) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => VideoWatchScreen(video: video)));

    // Watching moves the view count and can fill in a duration the
    // server did not have.
    if (mounted) await _load();
  }

  /// Opens the creator's channel so somebody can subscribe there.
  ///
  /// ── WHY IT IS NOT A DRIVELIFE "FOLLOW" ──────────────────────────
  ///
  /// There is no following here to do. Nothing stores who follows a
  /// creator, nothing would change if it did, and most creators are
  /// not DriveLife members for a follow to connect to.
  ///
  /// Subscribing on YouTube is the thing somebody actually wants when
  /// they press this, and it is the thing that reaches the creator -
  /// it shows up in their subscriber count rather than in a table
  /// only we can see.
  ///
  /// sub_confirmation=1 is YouTube's own parameter: it opens the
  /// channel with the subscribe prompt already up, so this is one tap
  /// rather than a trip to a page and a hunt for the button.
  Future<void> _subscribe() async {
    final url = _creator.channelUrl;

    if (url.isEmpty) return;

    final target = Uri.parse('$url?sub_confirmation=1');

    // externalApplication so the YouTube app takes it when installed.
    // An in-app webview would mean signing in again to subscribe,
    // which is the one thing that has to work here.
    final opened = await launchUrl(target, mode: LaunchMode.externalApplication)
        .catchError((Object e) {
          debugPrint('[creator] subscribe launch failed: $e');

          return false;
        });

    if (opened || !mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open YouTube.')));
  }

  /// Follow, or stop.
  ///
  /// ── REDRAWN BEFORE IT IS SAVED ───────────────────────────────────
  ///
  /// A follow button that waits for a round trip reads as one that did
  /// not work, and the second tap undoes the first. So the button
  /// changes at once and goes back only if the server disagreed.
  ///
  /// [_following] blocks a second tap while the first is in flight -
  /// the endpoint takes an explicit true/false rather than toggling,
  /// so two in flight at once would be two writes racing to decide the
  /// same thing.
  Future<void> _toggleFollow() async {
    if (_following) return;

    final wanted = !_creator.isFollowing;

    setState(() {
      _following = true;
      _creator = _creator.withFollowing(wanted);
    });

    final ok = await CreatorsAPI.setFollowing(_creator.id, wanted);

    if (!mounted) return;

    setState(() {
      _following = false;

      if (!ok) _creator = _creator.withFollowing(!wanted);
    });

    if (ok) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wanted ? 'Could not follow them.' : 'Could not unfollow them.',
        ),
      ),
    );
  }

  Future<void> _share() async {
    final creator = _creator;

    // Their channel, not a DriveLife link: there is no public page
    // for a creator outside the app to send somebody to, and a link
    // that opens nothing is worse than sharing the real thing.
    final url = creator.channelUrl;

    if (url.isEmpty) return;

    await SharePlus.instance.share(
      ShareParams(text: '${creator.name} on YouTube\n$url'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final creator = _creator;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        surfaceTintColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Creator',
          style: TextStyle(
            color: theme.textColor,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          // Only when there is a channel to send. A creator with no
          // channel on file has nothing shareable, and a share button
          // that opens an empty sheet is a bug people report.
          if (creator.channelUrl.isNotEmpty)
            IconButton(
              onPressed: _share,
              icon: const Icon(Icons.ios_share_rounded, size: 22),
              tooltip: 'Share',
            ),
        ],
      ),
      body: RefreshIndicator(
        color: _gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 110),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 4),
            _header(theme, creator),
            const SizedBox(height: 26),
            _videosHeader(theme),
            const SizedBox(height: 12),
            if (_loading)
              const _VideoListSkeleton()
            else if (_current.isEmpty)
              _empty(theme)
            else
              for (final video in _current)
                VideoListRow(
                  video: video,
                  subtitle: _subtitle(video),
                  watchedSeconds: _watched[video.postId] ?? 0,
                  onTap: () => _open(video),
                ),
          ],
        ),
      ),
    );
  }

  // ── The top ────────────────────────────────────────────────────────

  Widget _header(ThemeProvider theme, Creator creator) {
    return Column(
      children: [
        Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _gold, width: 2.5),
          ),
          padding: const EdgeInsets.all(5),
          child: _avatar(creator),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: DlHeading(
            creator.name,
            fontSize: 30,
            color: theme.textColor,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10),

        // What they are, which for now is always the same thing -
        // every creator is a YouTube channel. It is drawn from the
        // data rather than hard-coded so the day a creator is not,
        // this is one condition rather than a redesign.
        if (creator.channelId.isNotEmpty) _youtubePill(theme),

        const SizedBox(height: 18),

        // ── TWO DIFFERENT THINGS, TOLD APART ────────────────────
        //
        // Following is DriveLife's: it puts them on the front of this
        // person's Watch tab and mixes their videos into the row
        // under it.
        //
        // Subscribing is YouTube's, and it is worth something to the
        // creator in a way a follow here is not - it lands in their
        // own subscriber count.
        //
        // They were one button for a while, labelled Subscribe on
        // YouTube, because there was no following to do. Now that
        // there is, one is the primary action and the other is a
        // quiet link - rather than a single button that does one
        // thing and is named after the other.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            height: 54,
            width: double.infinity,
            child: creator.isFollowing
                ? OutlinedButton(
                    onPressed: _toggleFollow,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.textColor,
                      side: BorderSide(color: theme.dividerColor, width: 1.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(27),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, size: 21),
                        SizedBox(width: 8),
                        Text(
                          'Following',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                : FilledButton(
                    onPressed: _toggleFollow,
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(27),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Follow',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),

        if (creator.channelUrl.isNotEmpty) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _subscribe,
            icon: const Icon(Icons.open_in_new_rounded, size: 17),
            label: const Text(
              'Subscribe on YouTube',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            style: TextButton.styleFrom(foregroundColor: theme.subtextColor),
          ),
        ],

        if (creator.bio.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              creator.bio,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.subtextColor,
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _youtubePill(ThemeProvider theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 16, 7),
      decoration: BoxDecoration(
        color: theme.isDarkMode
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 21,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFF0000),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            'YouTube creator',
            style: TextStyle(
              color: theme.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(Creator creator) {
    final letters = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _colourFor(creator.id),
        shape: BoxShape.circle,
      ),
      child: Text(
        creator.initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 38,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    if (creator.avatarUrl.isEmpty) return letters;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: creator.avatarUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => letters,
        errorWidget: (_, __, ___) => letters,
      ),
    );
  }

  /// Keyed on the row id, so somebody's circle is the same colour
  /// here as it is in the Favourite Creators row.
  static Color _colourFor(int id) {
    const palette = [
      Color(0xFF8D6E63),
      Color(0xFFAD4F5B),
      Color(0xFF556B55),
      Color(0xFF7E5A8C),
      Color(0xFF3F6A8A),
      Color(0xFFB07A3C),
    ];

    return palette[id.abs() % palette.length];
  }

  // ── The list ───────────────────────────────────────────────────────

  Widget _videosHeader(ThemeProvider theme) {
    // ── BOTH TABS, ALWAYS ────────────────────────────────────────
    //
    // This used to collapse to a plain "Videos" heading when a
    // creator had no Shorts, on the reasoning that one tab is not a
    // choice.
    //
    // It is worse in practice: the page changes SHAPE depending on
    // whose it is, so somebody who taps Shorts on one creator and
    // then opens another finds the control gone and no explanation
    // of where it went. A tab that says 0 answers the question the
    // missing tab raises.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _tab(theme, 'Videos', _videos.length, !_showingShorts),
          const SizedBox(width: 10),
          _tab(theme, 'Shorts', _shorts.length, _showingShorts),
        ],
      ),
    );
  }

  Widget _tab(ThemeProvider theme, String label, int count, bool on) {
    return GestureDetector(
      onTap: () => setState(() => _showingShorts = label == 'Shorts'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          // Selected inverts against the page, the same rule the
          // Watch tab's chips follow.
          color: on ? theme.textColor : theme.backgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? theme.textColor : theme.dividerColor,
            width: 1.4,
          ),
        ),
        child: Text(
          // The count is in the tab rather than beside it: with two
          // of them, a single number off to the right belongs to
          // neither.
          _loading ? label : '$label  $count',
          style: TextStyle(
            color: on ? theme.backgroundColor : theme.textColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// "2 days ago", with the view count when there is one.
  String _subtitle(LongVideo video) {
    final parts = <String>[];

    final when = videoAgo(video.publishedAt);

    if (when.isNotEmpty) parts.add(when);

    if (video.viewLabel.isNotEmpty) parts.add(video.viewLabel);

    return parts.join(' · ');
  }

  Widget _empty(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
      child: Text(
        _showingShorts
            ? 'No Shorts from them yet.'
            : 'Nothing from them yet.\nTheir videos appear here as they '
                  'are pulled in.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: theme.subtextColor,
          fontSize: 13.5,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The list's shape while it loads.
class _VideoListSkeleton extends StatelessWidget {
  const _VideoListSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    final block = videoBlockColour(theme);

    return Column(
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 130,
                  height: 82,
                  decoration: BoxDecoration(
                    color: block,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 14, color: block),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: 0.7,
                        child: Container(height: 14, color: block),
                      ),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: 0.35,
                        child: Container(height: 11, color: block),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
