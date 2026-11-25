import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/video_playlists_api.dart';
import 'package:drivelife/api/videos_api.dart';
import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/screens/media/video_upload_screen.dart';
import 'package:drivelife/screens/media/video_watch_screen.dart';
import 'package:drivelife/services/watch_progress.dart';
import 'package:flutter/material.dart';

const Color _ink = Color(0xFF111111);
const Color _gold = Color(0xFFAE9159);

/// Every video, and the playlists they are grouped into.
///
/// The counterpart to AllGalleriesScreen, and built to the same
/// shape: an app bar with a back chevron, a pull to refresh, and a
/// two-column grid.
///
/// ── PLAYLISTS FIRST, THEN EVERYTHING ────────────────────────────────
///
/// A playlist is a reason to watch a particular video rather than
/// scroll past all of them, so the curated runs lead and the full
/// list follows. On a library with no playlists yet the row simply is
/// not drawn and this is a grid of videos, which is also correct.
class AllVideosScreen extends StatefulWidget {
  const AllVideosScreen({super.key});

  @override
  State<AllVideosScreen> createState() => _AllVideosScreenState();
}

class _AllVideosScreenState extends State<AllVideosScreen> {
  List<LongVideo> _videos = const [];
  List<VideoPlaylist> _playlists = const [];
  Map<String, int> _watched = const {};

  /// The first load, before anything can be drawn.
  bool _loading = true;

  /// A search is in flight. Separate from [_loading] because the
  /// screen already has content by then - replacing a grid of
  /// results with a full-screen spinner on every keystroke is worse
  /// than leaving the old ones up with a quiet indicator.
  bool _searching = false;

  bool _canUpload = false;

  final TextEditingController _search = TextEditingController();

  /// Debounce, so typing does not fire a request per keystroke.
  ///
  /// 350ms: long enough that a word typed at speed is one request,
  /// short enough that it does not feel like waiting.
  Timer? _debounce;

  /// What the most recent request was for. A slow response for an
  /// earlier term must not overwrite results for a later one - the
  /// classic way a search box ends up showing answers to a question
  /// the person has already moved on from.
  String _inFlightFor = '';

  @override
  void initState() {
    super.initState();

    _loadEverything();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();

    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();

    // Immediately, before the request goes out: the clear button and
    // the heading read off this field, and waiting 350ms for them to
    // notice a keystroke is a large part of why the box felt broken.
    setState(() {});

    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _loadVideos();
    });
  }

  /// Everything: the first load and pull-to-refresh.
  ///
  /// Playlists and the upload permission are fetched HERE and not in
  /// [_loadVideos]. Neither can change because somebody typed a
  /// letter, and refetching them per keystroke made every search
  /// four sequential round trips instead of one.
  Future<void> _loadEverything() async {
    final videos = VideosAPI.list(limit: 50, search: _search.text.trim());
    final playlists = VideoPlaylistsAPI.list();
    final watched = WatchProgress.positions();
    final permission = VideosAPI.uploadPermission();

    // Started together rather than awaited one after another. Four
    // sequential calls is four round trips of latency for no reason;
    // none of them depends on another.
    final result = await (
      videos,
      playlists,
      watched,
      permission,
    ).wait;

    if (!mounted) return;

    setState(() {
      _videos = result.$1;
      _playlists = result.$2;
      _watched = result.$3;
      _canUpload = result.$4.canUpload && result.$4.configured;
      _loading = false;
      _searching = false;
    });
  }

  /// Just the results.
  Future<void> _loadVideos() async {
    final term = _search.text.trim();

    _inFlightFor = term;

    setState(() => _searching = true);

    final videos = await VideosAPI.list(limit: 50, search: term);
    final watched = await WatchProgress.positions();

    if (!mounted) return;

    // A later keystroke has already asked for something else. Its own
    // response will clear the indicator; doing it here would turn it
    // off while that request is still out.
    if (_inFlightFor != term) return;

    setState(() {
      _videos = videos;
      _watched = watched;
      _searching = false;
    });
  }

  Future<void> _open(LongVideo video) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => VideoWatchScreen(video: video)));

    if (mounted) await _loadEverything();
  }

  Future<void> _upload() async {
    final started = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const VideoUploadScreen()));

    if (started == true && mounted) await _loadEverything();
  }

  Future<void> _openPlaylist(VideoPlaylist playlist) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlaylistScreen(playlist: playlist)),
    );

    if (mounted) await _loadEverything();
  }

  bool get _isSearching => _search.text.trim().isNotEmpty;

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: TextField(
        controller: _search,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _loadVideos(),
        decoration: InputDecoration(
          hintText: 'Search videos',
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          // Only once there is something to clear. A permanent X on
          // an empty field is a button that does nothing.
          suffixIcon: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _search.clear();
                    _loadVideos();
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          filled: true,
          fillColor: const Color(0xFFF4F4F4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Videos',
          style: TextStyle(
            color: _ink,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      // The way in for an administrator, and impossible to miss.
      // See the note on VideoUploadButton.
      floatingActionButton: _canUpload
          ? FloatingActionButton.extended(
              onPressed: _upload,
              backgroundColor: _gold,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.video_call_rounded),
              label: const Text(
                'Upload',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      body: _loading
          ? const _VideosSkeleton()
          : RefreshIndicator(
              color: _gold,
              onRefresh: _loadEverything,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _searchField()),
                  // Two points of moving line, under the field it
                  // belongs to. Enough to say "working" without
                  // taking the results away to say it.
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 2,
                      child: _searching
                          ? const LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation(_gold),
                            )
                          : null,
                    ),
                  ),
                  // Playlists step aside while searching. They are a
                  // way to browse, and somebody typing a title has
                  // already decided not to browse.
                  if (_playlists.isNotEmpty && !_isSearching) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: Text(
                          'Playlists',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 186,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _playlists.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) => _PlaylistCard(
                            playlist: _playlists[index],
                            onTap: () => _openPlaylist(_playlists[index]),
                          ),
                        ),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                      child: Text(
                        _isSearching
                            ? '${_videos.length} result'
                                  '${_videos.length == 1 ? '' : 's'}'
                            : 'All videos',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ),
                  ),
                  if (_videos.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            _isSearching
                                ? 'Nothing matches "${_search.text.trim()}".'
                                : 'No videos yet.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 14,
                              childAspectRatio: 0.82,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final video = _videos[index];

                          return VideoGridTile(
                            video: video,
                            watchedSeconds: _watched[video.postId] ?? 0,
                            onTap: () => _open(video),
                          );
                        }, childCount: _videos.length),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// What the screen looks like before it has anything.
///
/// ── WHY NOT A SPINNER ───────────────────────────────────────────────
///
/// A spinner says "wait" and nothing else. This says what is coming -
/// a row of playlists and a grid of videos - so the page does not
/// jump into a different shape the moment it arrives, and the wait is
/// spent looking at the layout rather than at a dot.
class _VideosSkeleton extends StatelessWidget {
  const _VideosSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 4),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: _Shimmer(height: 44, radius: 12),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: _Shimmer(width: 90, height: 16, radius: 4),
        ),
        SizedBox(
          height: 186,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 2,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, __) => const SizedBox(
              width: 184,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Shimmer(width: 184, height: 108, radius: 12),
                  SizedBox(height: 8),
                  _Shimmer(width: 130, height: 14, radius: 4),
                  SizedBox(height: 6),
                  _Shimmer(width: 90, height: 12, radius: 4),
                ],
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: _Shimmer(width: 80, height: 16, radius: 4),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 14,
            childAspectRatio: 0.82,
          ),
          itemCount: 4,
          itemBuilder: (_, __) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(aspectRatio: 16 / 9, child: _Shimmer(radius: 10)),
              SizedBox(height: 8),
              _Shimmer(height: 13, radius: 4),
              SizedBox(height: 5),
              _Shimmer(width: 80, height: 11, radius: 4),
            ],
          ),
        ),
      ],
    );
  }
}

/// One grey block, breathing.
class _Shimmer extends StatefulWidget {
  final double? width;
  final double? height;
  final double radius;

  const _Shimmer({this.width, this.height, this.radius = 8});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      // A pulse rather than a sweeping highlight. One animation
      // controller per block instead of a shader per tile, and at
      // this size nobody can tell the difference.
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_controller),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFFEDEDED),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A playlist, as something you would want to open.
///
/// ── WHY NOT A PILL ──────────────────────────────────────────────────
///
/// It was: the name and a number, in a chip. That tells somebody a
/// playlist exists and nothing about whether it is worth their
/// evening. A cover frame says what it is about, and a runtime
/// answers the question anybody actually has in front of a list of
/// series - "how long is this going to take".
class _PlaylistCard extends StatelessWidget {
  final VideoPlaylist playlist;
  final VoidCallback onTap;

  const _PlaylistCard({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 184,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 184,
                    height: 108,
                    child: playlist.coverUrl.isEmpty
                        ? Container(
                            color: Colors.grey.shade200,
                            child: Icon(
                              Icons.playlist_play_rounded,
                              color: Colors.grey.shade400,
                              size: 34,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: playlist.coverUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 560,
                            errorWidget: (_, __, ___) =>
                                Container(color: Colors.grey.shade200),
                          ),
                  ),
                ),
                // The count, over the artwork, the way a stack of
                // things is labelled everywhere else.
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.playlist_play_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${playlist.count}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                playlist.countLabel,
                if (playlist.runtimeLabel.isNotEmpty) playlist.runtimeLabel,
              ].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

/// One video in a grid. Shared by this screen and [PlaylistScreen].
class VideoGridTile extends StatelessWidget {
  final LongVideo video;
  final int watchedSeconds;
  final VoidCallback onTap;

  const VideoGridTile({
    super.key,
    required this.video,
    required this.watchedSeconds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final partly =
        watchedSeconds > 0 &&
        video.durationSeconds > 0 &&
        watchedSeconds < video.durationSeconds;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              // ── ONE CLIP FOR THE WHOLE CARD ────────────────────────
              //
              // The progress bar used to carry its own ClipRRect with
              // a bottom radius on it, and a corner radius cannot be
              // expressed in a bar three points tall - Flutter clamps
              // it, so the bar's ends stayed square while the picture
              // behind them curved away. It read as a line that did
              // not line up with anything.
              //
              // Clipping the Stack instead means the bar and the
              // artwork are cut by the SAME rounded rectangle, so the
              // ends follow the corner exactly whatever the radius is.
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  video.thumbnailUrl.isEmpty
                      ? Container(color: Colors.grey.shade200)
                      : CachedNetworkImage(
                          imageUrl: video.thumbnailUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 600,
                          errorWidget: (_, __, ___) =>
                              Container(color: Colors.grey.shade200),
                        ),
                  Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white70),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  if (partly)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: watchedSeconds / video.durationSeconds,
                        // 4, up from 3. At three points the bar reads
                        // as an artefact of the image rather than as a
                        // deliberate mark.
                        minHeight: 4,
                        backgroundColor: Colors.black26,
                        valueColor: const AlwaysStoppedAnimation(_gold),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            video.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (video.lengthLabel.isNotEmpty) video.lengthLabel,
              if (video.viewLabel.isNotEmpty) video.viewLabel,
            ].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/// One playlist, and the videos in it, in order.
class PlaylistScreen extends StatefulWidget {
  final VideoPlaylist playlist;

  const PlaylistScreen({super.key, required this.playlist});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  List<LongVideo> _videos = const [];
  Map<String, int> _watched = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    final result = await VideoPlaylistsAPI.videos(widget.playlist.id);
    final watched = await WatchProgress.positions();

    if (!mounted) return;

    setState(() {
      _videos = result.videos;
      _watched = watched;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.playlist.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _ink,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : RefreshIndicator(
              color: _gold,
              onRefresh: _load,
              child: _videos.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 80),
                        Center(
                          child: Text(
                            'Nothing in this playlist yet.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 14,
                            childAspectRatio: 0.82,
                          ),
                      itemCount: _videos.length,
                      itemBuilder: (context, index) {
                        final video = _videos[index];

                        return VideoGridTile(
                          video: video,
                          watchedSeconds: _watched[video.postId] ?? 0,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => VideoWatchScreen(video: video),
                              ),
                            );

                            if (mounted) await _load();
                          },
                        );
                      },
                    ),
            ),
    );
  }
}
