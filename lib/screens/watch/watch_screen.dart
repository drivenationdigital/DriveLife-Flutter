import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/creators_api.dart';
import 'package:drivelife/api/video_playlists_api.dart';
import 'package:drivelife/api/videos_api.dart';
import 'package:drivelife/models/creator.dart';
import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/media/all_videos_screen.dart';
import 'package:drivelife/screens/media/video_watch_screen.dart';
import 'package:drivelife/screens/watch/creator_screen.dart';
import 'package:drivelife/screens/watch/podcast_screen.dart';
import 'package:drivelife/services/watch_progress.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:drivelife/widgets/media/video_list_row.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Watch tab.
///
/// ── WHERE EACH SECTION COMES FROM ───────────────────────────────────
///
/// Everything here is live now. Three requests, made together on open:
///
///   * `/videos` - the whole of the top of the screen. The featured
///     card is the newest video and the row underneath is the rest of
///     the same list, so they are one request cut in two rather than
///     two racing for the same rows.
///
///   * `/creators?featured=1` - the Favourite Creators row.
///
///   * `/videos?podcast=1` - the podcast block.
///
/// ── AND WHAT IS NOT WIRED ───────────────────────────────────────────
///
/// The filter chips along the top. They set a local variable and
/// nothing reads it: filtering needs the server to narrow a list this
/// screen currently assembles from three, which is a change worth
/// making deliberately rather than as a side effect of this one.
///
/// Every section hides itself when it has nothing, so an installation
/// with no videos shows a search box and no empty furniture.
class WatchScreen extends StatefulWidget {
  /// The shell's bottom-bar visibility.
  ///
  /// Every destination in the tab shell reports its scrolling through
  /// one of these, and that is what takes the bottom bar away on the
  /// way down and brings it back on the way up. A tab that does not
  /// pass it scrolls in silence while the bar sits there through all
  /// of it - which is how this screen behaved for exactly one build.
  ///
  /// Nullable, so the screen still works when pushed as a plain route
  /// with no shell around it.
  final ChromeVisibility? chrome;

  const WatchScreen({super.key, this.chrome});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  static const Color _gold = Color(0xFFAE9159);
  static const Color _ink = Color(0xFF111111);

  /// Which chip is on.
  ///
  /// ── WHAT A CHIP DOES ─────────────────────────────────────────────
  ///
  /// It changes which SECTIONS the page is made of, not which rows a
  /// request returns. 'All' is the magazine front page - a hero, the
  /// creators, a row of videos, the podcast. Every other chip replaces
  /// all of that with one plain list of that one thing.
  ///
  /// That is the honest reading of these chips, and it is also the one
  /// that needs no new endpoint: each section is already its own
  /// request, so a chip is a choice of which to show rather than a
  /// filter to push down to the server.
  String _filter = 'All';

  // ── SEARCH ───────────────────────────────────────────────────────
  //
  // Searching replaces the whole page below the box rather than
  // narrowing one chip: the field says "videos & creators" and
  // answering only half of that while a chip happened to be on would
  // be a search that quietly ignored most of what was asked.
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  List<Creator> _creatorHits = const [];
  List<LongVideo> _videoHits = const [];
  bool _searching = false;

  /// The term the in-flight request was for.
  ///
  /// Replies can arrive out of order - a short term is cheaper to
  /// answer than a long one - so a late reply for "go" must not land
  /// on top of the results for "goodwood".
  String _inFlightFor = '';

  bool get _isSearching => _search.text.trim().isNotEmpty;

  void _onSearchChanged(String value) {
    _debounce?.cancel();

    // At once, before the request goes out: the clear button and the
    // headings read off this field, and waiting 350ms for them to
    // notice a keystroke is most of why a box feels broken.
    setState(() {});

    final term = value.trim();

    if (term.isEmpty) {
      setState(() {
        _searching = false;
        _creatorHits = const [];
        _videoHits = const [];
      });

      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _runSearch();
    });
  }

  Future<void> _runSearch() async {
    final term = _search.text.trim();

    if (term.isEmpty) return;

    _inFlightFor = term;

    setState(() => _searching = true);

    final results = await (
      CreatorsAPI.list(limit: 20, search: term),
      VideosAPI.list(limit: 30, search: term),
    ).wait;

    if (!mounted || _inFlightFor != term) return;

    setState(() {
      _creatorHits = results.$1;
      _videoHits = results.$2;
      _searching = false;
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();

    setState(() {
      _searching = false;
      _creatorHits = const [];
      _videoHits = const [];
    });

    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();

    super.dispose();
  }

  // ── WHAT EACH TAB NEEDS, FETCHED WHEN IT IS FIRST OPENED ─────────
  //
  // The front page loads three short lists on open. The tabs want long
  // ones, and loading four long lists for somebody who only ever looks
  // at the front page would be four requests wasted on every visit.
  //
  // So each is fetched the first time its chip is tapped and kept
  // afterwards - the second tap is instant, and pull-to-refresh is
  // what re-reads it.
  List<Creator> _allCreators = const [];
  List<LongVideo> _allEpisodes = const [];
  List<VideoPlaylist> _playlists = const [];

  final Set<String> _loadedTabs = {};
  final Set<String> _loadingTabs = {};

  Future<void> _selectFilter(String filter) async {
    setState(() => _filter = filter);

    await _ensureTab(filter);
  }

  /// Loads a tab's list, once.
  Future<void> _ensureTab(String filter, {bool force = false}) async {
    // 'All' and 'Video' are both served by the list fetched on open.
    if (filter == 'All' || filter == 'Video') return;

    if (!force && _loadedTabs.contains(filter)) return;
    if (_loadingTabs.contains(filter)) return;

    setState(() => _loadingTabs.add(filter));

    switch (filter) {
      case 'Creators':
        // Everybody, not just the featured ones - the front page row
        // is the editorial pick and this is the directory.
        final creators = await CreatorsAPI.list(limit: 100);

        if (!mounted) return;

        _allCreators = creators;

      case 'Podcast':
        final episodes = await VideosAPI.list(limit: 50, podcast: true);

        if (!mounted) return;

        _allEpisodes = episodes;

      case 'Playlists':
        final playlists = await VideoPlaylistsAPI.list();

        if (!mounted) return;

        _playlists = playlists;
    }

    if (!mounted) return;

    setState(() {
      _loadingTabs.remove(filter);
      _loadedTabs.add(filter);
    });
  }

  // ── THE PODCAST ──────────────────────────────────────────────────
  //
  // Its own request rather than a slice of the videos list, because
  // the server decides what an episode is - from who published it, or
  // from the creator it came from - and re-deriving that rule here
  // would be a second copy of it to keep in step.
  List<LongVideo> _episodes = const [];
  bool _loadingEpisodes = true;

  List<Creator> _creatorList = const [];
  bool _loadingCreators = true;

  // ── ONE REQUEST, TWO SECTIONS ────────────────────────────────────
  //
  // The featured card and the row underneath it are the same list cut
  // in two, so they are fetched together rather than racing each other
  // for the same rows.
  List<LongVideo> _videos = const [];
  bool _loadingVideos = true;

  /// Seconds watched, by post id. Absent means not started.
  ///
  /// Read from the device rather than the server - see WatchProgress -
  /// so it costs nothing and is refreshed alongside every list.
  Map<String, int> _watched = const {};

  int _watchedOn(LongVideo video) => _watched[video.postId] ?? 0;

  /// The hero.
  ///
  /// ── CHOSEN IF SOMEBODY CHOSE, NEWEST IF NOBODY DID ───────────────
  ///
  /// An editor's pick beats a date, so a featured video wins. Falling
  /// back to the newest matters just as much: a fresh installation
  /// has nothing featured, and a front page with an empty hero until
  /// somebody discovers the admin screen is worse than one that shows
  /// the obvious thing.
  ///
  /// The fallback also covers the featured video being deleted or
  /// unpublished - the hero quietly becomes the newest again rather
  /// than becoming a hole.
  LongVideo? get _featuredVideo {
    for (final video in _videos) {
      if (video.isFeatured) return video;
    }

    return _videos.isEmpty ? null : _videos.first;
  }

  /// The ten videos under the creators row.
  ///
  /// ── FROM THE PEOPLE ON THIS PERSON'S FRONT PAGE ──────────────────
  ///
  /// Its own request rather than a slice of the general list: the
  /// videos here are the ones belonging to the creators above them -
  /// DriveLife's picks plus whoever this person follows - in the order
  /// they were published, mixed together.
  ///
  /// Episodes are left out, as they are below: the podcast has its own
  /// block further down, and a row that is the same four things in a
  /// different shape is a row worth scrolling past. One flag if that
  /// ever stops being wanted.
  List<LongVideo> _homeVideos = const [];
  bool _loadingHomeVideos = true;

  @override
  void initState() {
    super.initState();

    _loadEpisodes();
    _loadCreators();
    _loadVideos();
    _loadHomeVideos();
  }

  /// Everything the open tab shows.
  Future<void> _refresh() async {
    await Future.wait([
      _loadVideos(),
      _loadHomeVideos(),
      _loadEpisodes(),
      _loadCreators(),
      _ensureTab(_filter, force: true),
    ]);
  }

  Future<void> _loadHomeVideos() async {
    final videos = await VideosAPI.list(limit: 10, home: true, podcast: false);

    if (!mounted) return;

    setState(() {
      _homeVideos = videos;
      _loadingHomeVideos = false;
    });
  }

  Future<void> _loadVideos() async {
    // Enough to fill the hero and the row with a margin, without
    // asking for a page nobody scrolls to.
    // Together: a list is useless a moment before the marks on it,
    // and two sequential awaits would draw the rows then move them.
    final results = await Future.wait([
      VideosAPI.list(limit: 15),
      WatchProgress.positions(),
    ]);

    if (!mounted) return;

    setState(() {
      _videos = results[0] as List<LongVideo>;
      _watched = results[1] as Map<String, int>;
      _loadingVideos = false;
    });
  }

  Future<void> _openVideo(LongVideo video) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => VideoWatchScreen(video: video)));

    // _loadVideos re-reads WatchProgress too, which is the point:
    // somebody who watches half of something and comes back should
    // see the bar move, not where they were an hour ago.
    if (mounted) await _loadVideos();
  }

  Future<void> _openCreator(Creator creator) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CreatorScreen(creator: creator)));

    // Following somebody in there changes who is on this row and what
    // is under it, so both are re-read rather than left stale behind
    // a back button.
    if (!mounted) return;

    await Future.wait([_loadCreators(), _loadHomeVideos()]);
  }

  Future<void> _loadCreators() async {
    // Featured only: this row is the editorial pick, not the whole
    // directory. Twelve is more than fits on any screen, which is the
    // point - it scrolls.
    // home, not featured: the editorial list PLUS whoever this
    // person follows, with theirs first. The server orders it, so
    // nothing here has to know which is which.
    final creators = await CreatorsAPI.list(limit: 20, home: true);

    if (!mounted) return;

    setState(() {
      _creatorList = creators;
      _loadingCreators = false;
    });
  }

  Future<void> _loadEpisodes() async {
    // Four: one to feature and three underneath, which is what the
    // block has room for before "See all" is the better answer.
    final episodes = await VideosAPI.list(limit: 4, podcast: true);

    if (!mounted) return;

    setState(() {
      _episodes = episodes;
      _loadingEpisodes = false;
    });
  }

  Future<void> _openEpisode(LongVideo episode) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => VideoWatchScreen(video: episode)));

    if (mounted) await _loadEpisodes();
  }

  Future<void> _openPodcast() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PodcastScreen()));

    if (mounted) await _loadEpisodes();
  }

  static const List<String> _filters = [
    'All',
    'Video',
    'Creators',
    'Podcast',
    'Playlists',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    // No AppBar and no bottom bar: the tab shell owns both, and this
    // screen is dropped into it. See the note in the handover.
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      // ── NO SafeArea, AND THAT IS NOT AN OVERSIGHT ─────────────────
      //
      // The shell has already dealt with the top. Its Column starts
      // with a SizedBox the height of MediaQuery.padding.top, then
      // draws the header, and only then hands the rest to the
      // destinations - so a SafeArea in here inset the status bar a
      // SECOND time and left a status bar's worth of blank page
      // between the header and the search field.
      //
      // The bottom is a different problem: the shell sets
      // extendBody: true so the bar can slide away without reflowing
      // the content, which means it floats OVER the end of this list.
      // Hence the padding below rather than a SafeArea there either.
      body: NotificationListener<ScrollNotification>(
        onNotification: widget.chrome?.handle ?? (_) => false,
        child: RefreshIndicator(
          color: _gold,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 110),
            // So the pull works on a tab whose list is short enough
            // not to scroll - which is every empty one, and the empty
            // ones are where somebody most wants to try again.
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _searchField(theme),
              const SizedBox(height: 16),
              // The chips are not a second filter on top of a search -
              // they are the thing a search replaces. Hidden while one
              // is running so nothing claims to be narrowing results
              // that are already narrowed.
              if (!_isSearching) ...[
                _filterRow(theme),
                const SizedBox(height: 20),
              ],
              ...(_isSearching ? _searchResults(theme) : _sections(theme)),
            ],
          ),
        ),
      ),
    );
  }

  /// Creators, then videos - what matched.
  List<Widget> _searchResults(ThemeProvider theme) {
    if (_searching) return const [_VideoListSkeleton()];

    if (_creatorHits.isEmpty && _videoHits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 50, 32, 40),
          child: Text(
            'Nothing matched “${_search.text.trim()}”.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.subtextColor,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ];
    }

    return [
      // Creators first, and usually far fewer of them: somebody
      // searching a creator's name wants the person, and burying them
      // under thirty videos they happen to appear in is the wrong
      // answer to the right question.
      if (_creatorHits.isNotEmpty) ...[
        _sectionHeader('Creators', theme, action: null),
        const SizedBox(height: 10),
        ..._creatorRows(theme, _creatorHits),
        const SizedBox(height: 22),
      ],

      if (_videoHits.isNotEmpty) ...[
        _sectionHeader('Videos', theme, action: null),
        const SizedBox(height: 10),
        for (final video in _videoHits)
          VideoListRow(
            video: video,
            subtitle: _rowSubtitle(video),
            watchedSeconds: _watchedOn(video),
            onTap: () => _openVideo(video),
          ),
      ],
    ];
  }

  /// What sits below the chips.
  List<Widget> _sections(ThemeProvider theme) {
    switch (_filter) {
      case 'Video':
        return [
          ..._listTab(
            theme,
            loading: _loadingVideos,
            // Every video, episodes included. This tab is "the
            // library", and leaving things out of a list labelled
            // Video would be the surprising choice.
            items: _videos,
            empty: 'No videos yet.',
            builder: (video) => VideoListRow(
              video: video,
              subtitle: _rowSubtitle(video),
              watchedSeconds: _watchedOn(video),
              onTap: () => _openVideo(video),
            ),
          ),
        ];

      case 'Creators':
        return _creatorsTab(theme);

      case 'Podcast':
        return _listTab(
          theme,
          loading: _loadingTabs.contains('Podcast'),
          items: _allEpisodes,
          empty: 'No episodes yet.',
          builder: (video) => VideoListRow(
            video: video,
            subtitle: podcastMeta(video),
            watchedSeconds: _watchedOn(video),
            onTap: () => _openVideo(video),
          ),
        );

      case 'Playlists':
        return _playlistsTab(theme);

      default:
        return _frontPage(theme);
    }
  }

  /// The magazine front page.
  ///
  /// ── A HIDDEN SECTION TAKES ITS SPACING WITH IT ───────────────────
  ///
  /// Each block used to be followed by a fixed SizedBox. That is fine
  /// while every block is on screen and wrong the moment one is not: a
  /// section that collapses to nothing leaves the padding on both
  /// sides of it behind, and two gaps meet to make one large one.
  ///
  /// It showed up as a canyon between the creators and the podcast on
  /// any installation whose videos are all episodes - the row between
  /// them renders nothing, and its 12 above and 28 below still took
  /// forty points.
  ///
  /// So the gap belongs to the block UNDER it, and a block that is not
  /// drawn cannot contribute one. The first one on screen drops its
  /// gap, whichever it turns out to be.
  List<Widget> _frontPage(ThemeProvider theme) {
    final blocks = <({double gap, Widget child})>[
      if (_showFeatured) (gap: 0, child: _featured()),
      if (_showCreators) (gap: 28, child: _creators(theme)),
      if (_showVideoRow) (gap: 12, child: _videoRow()),
      if (_showPodcast) (gap: 24, child: _podcast()),
    ];

    return [
      for (var i = 0; i < blocks.length; i++) ...[
        if (i > 0) SizedBox(height: blocks[i].gap),
        blocks[i].child,
      ],
    ];
  }

  // ── WHICH BLOCKS ARE ON SCREEN ───────────────────────────────────
  //
  // Read twice each: once to decide whether to draw the block, once
  // to decide whether to draw the gap above it. Kept here rather than
  // inside the widgets so the two answers cannot disagree - which is
  // exactly how the spacing drifted in the first place.
  bool get _showFeatured => _loadingVideos || _featuredVideo != null;

  bool get _showCreators => _loadingCreators || _creatorList.isNotEmpty;

  bool get _showVideoRow => _loadingHomeVideos || _homeVideos.isNotEmpty;

  bool get _showPodcast => _loadingEpisodes || _episodes.isNotEmpty;

  /// "Tom Reeve · 2 days ago", dropping whichever half is missing.
  String _rowSubtitle(LongVideo video) {
    final parts = <String>[];

    if (video.authorName.isNotEmpty) parts.add(video.authorName);

    final when = videoAgo(video.publishedAt);

    if (when.isNotEmpty) parts.add(when);

    return parts.join(' · ');
  }

  /// A plain vertical list, with its loading and empty states.
  ///
  /// Shared by Video and Podcast because they differ only in which
  /// list they draw and what the subtitle says.
  List<Widget> _listTab(
    ThemeProvider theme, {
    required bool loading,
    required List<LongVideo> items,
    required String empty,
    required Widget Function(LongVideo) builder,
  }) {
    if (loading) return const [_VideoListSkeleton()];

    if (items.isEmpty) return [_emptyTab(theme, empty)];

    return [for (final item in items) builder(item)];
  }

  List<Widget> _creatorsTab(ThemeProvider theme) {
    if (_loadingTabs.contains('Creators')) {
      return const [_VideoListSkeleton()];
    }

    if (_allCreators.isEmpty) {
      return [_emptyTab(theme, 'No creators yet.')];
    }

    return _creatorRows(theme, _allCreators);
  }

  /// A creator as a row. Shared by the Creators tab and the search
  /// results, because they are the same thing twice.
  List<Widget> _creatorRows(ThemeProvider theme, List<Creator> creators) {
    return [
      for (final creator in creators)
        InkWell(
          onTap: () => _openCreator(creator),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _gold, width: 1.8),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: _Avatar(
                    name: creator.name,
                    avatarUrl: creator.avatarUrl,
                    colour: _colourFor(creator.id),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        creator.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        creator.isPodcast
                            ? 'The DriveLife podcast'
                            : 'YouTube creator',
                        style: TextStyle(
                          color: theme.subtextColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: theme.subtextColor),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _playlistsTab(ThemeProvider theme) {
    if (_loadingTabs.contains('Playlists')) {
      return const [_VideoListSkeleton()];
    }

    if (_playlists.isEmpty) {
      return [_emptyTab(theme, 'No playlists yet.')];
    }

    return [
      for (final playlist in _playlists)
        InkWell(
          // The playlist viewer the media tab already has, rather
          // than a second one that would have to be kept in step.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlaylistScreen(playlist: playlist),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 130,
                    height: 82,
                    child: playlist.coverUrl.isEmpty
                        ? ColoredBox(
                            color: videoBlockColour(theme),
                            child: Icon(
                              Icons.playlist_play_rounded,
                              color: theme.subtextColor,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: playlist.coverUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                ColoredBox(color: videoBlockColour(theme)),
                            errorWidget: (_, __, ___) =>
                                ColoredBox(color: videoBlockColour(theme)),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        [
                          playlist.countLabel,
                          playlist.runtimeLabel,
                        ].where((part) => part.isNotEmpty).join(' · '),
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
          ),
        ),
    ];
  }

  Widget _emptyTab(ThemeProvider theme, String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: theme.subtextColor,
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── Search ─────────────────────────────────────────────────────────

  Widget _searchField(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _search,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        // So the keyboard's Search key does not wait out the debounce
        // somebody has already decided they are finished with.
        onSubmitted: (_) {
          _debounce?.cancel();
          _runSearch();
        },
        decoration: InputDecoration(
          hintText: 'Search videos & creators',
          hintStyle: TextStyle(
            color: theme.subtextColor,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: theme.subtextColor),
          // Only when there is something to clear, so the field is not
          // carrying a button that does nothing most of the time.
          suffixIcon: _isSearching
              ? IconButton(
                  onPressed: _clearSearch,
                  icon: Icon(Icons.close_rounded, color: theme.subtextColor),
                  tooltip: 'Clear',
                )
              : null,
          filled: true,
          fillColor: theme.isDarkMode
              ? const Color(0xFF1E1E1E)
              : const Color(0xFFF2F2F2),
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ── Filters ────────────────────────────────────────────────────────

  Widget _filterRow(ThemeProvider theme) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final label = _filters[index];
          final on = label == _filter;

          return GestureDetector(
            onTap: () => _selectFilter(label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                // The selected chip inverts against the page, so it has
                // to be read from the theme rather than pinned - see
                // the same decision on the feed's pills.
                color: on ? theme.textColor : theme.backgroundColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: on ? theme.textColor : theme.dividerColor,
                  width: 1.4,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: on ? theme.backgroundColor : theme.textColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── The featured video ─────────────────────────────────────────────

  Widget _featured() {
    if (_loadingVideos) return const _FeaturedSkeleton();

    final item = _featuredVideo;

    // Nothing published at all. No placeholder and no empty frame:
    // the screen simply starts at whatever it does have.
    //
    // _showFeatured decides this too, for the gap - see _frontPage.
    // This stays as the backstop for anything calling it directly.
    if (item == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          onTap: () => _openVideo(item),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _thumbnail(item.thumbnailUrl),
                // Top and bottom, because there is a badge in one corner
                // and two lines of text in the other.
                const _Scrim(),
                Positioned(
                  left: 14,
                  top: 14,
                  child: _pill(
                    icon: Icons.play_arrow_rounded,
                    label: 'FEATURED',
                  ),
                ),
                const Center(child: _PlayCircle(size: 76, iconSize: 34)),
                VideoProgressBar(video: item, watchedSeconds: _watchedOn(item)),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitle(item),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13.5,
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
      ),
    );
  }

  /// "Tom Reeve · 8:12", dropping whichever half is missing.
  ///
  /// A video whose length nobody has established yet would otherwise
  /// read "Tom Reeve · " with a dangling separator, which looks like
  /// a rendering fault rather than an absent number.
  static String _subtitle(LongVideo video) {
    final parts = <String>[];

    if (video.authorName.isNotEmpty) parts.add(video.authorName);
    if (video.lengthLabel.isNotEmpty) parts.add(video.lengthLabel);

    return parts.join(' · ');
  }

  // ── Creators ───────────────────────────────────────────────────────

  Widget _creators(ThemeProvider theme) {
    // Nothing featured and nothing loading: no row. A fresh
    // installation has no creators, and an empty strip under a
    // heading is a section announcing that it has nothing.
    //
    // Except for an administrator, who needs a way IN to add the
    // first one - and hiding the only entrance until somebody has
    // already used it is the kind of thing that gets reported as a
    // missing feature.
    if (!_showCreators) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No action. The row already shows every featured creator,
        // so "See all" would lead to the same list; choosing WHICH
        // creators appear is done in wp-admin now, not here.
        _sectionHeader('Favourite creators', theme, action: null),
        const SizedBox(height: 14),
        SizedBox(
          // Measured rather than guessed: 68 for the circle, 7 for
          // the gap, and about 17 for a single line of 12.5pt. The
          // 108 this used to be left twenty points of empty row
          // under the names, which read as a gap below the section
          // rather than as slack inside it.
          height: 94,
          child: _loadingCreators
              ? const _CreatorSkeleton()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _creatorList.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final creator = _creatorList[index];

                    return SizedBox(
                      width: 72,
                      child: GestureDetector(
                        // The whole cell, not just the circle: the
                        // name underneath is what people aim for
                        // when the picture is this small.
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _openCreator(creator),
                        child: Column(
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                // The gold ring is what marks somebody
                                // as featured, and it is the only place
                                // the brand colour appears here.
                                border: Border.all(color: _gold, width: 2),
                              ),
                              padding: const EdgeInsets.all(2.5),
                              child: _Avatar(
                                name: creator.name,
                                avatarUrl: creator.avatarUrl,
                                // Keyed on the ROW id, not the linked
                                // account: most creators have no
                                // account, so userId is 0 for them and
                                // every one of those circles would have
                                // come out the same colour.
                                colour: _colourFor(creator.id),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              creator.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.textColor,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// A colour for somebody with no picture.
  ///
  /// Picked from their id so it never changes between visits - a
  /// circle that is brown today and green tomorrow reads as a
  /// different person.
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

  // ── The video row ──────────────────────────────────────────────────

  Widget _videoRow() {
    if (_loadingHomeVideos) return const _VideoRowSkeleton();

    final videos = _homeVideos;

    // Nobody featured and nobody followed, or everything they have
    // made is an episode. Either way there is nothing here the block
    // below does not already show.
    if (videos.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) => _videoCard(videos[index]),
      ),
    );
  }

  Widget _videoCard(LongVideo video) {
    return GestureDetector(
      onTap: () => _openVideo(video),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 272,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _thumbnail(video.thumbnailUrl),
              const _Scrim(),

              // Where it came from. Only drawn for a YouTube-sourced
              // video - a DriveLife upload carries no badge, because the
              // absence of one is what says "ours".
              if (video.isYoutube)
                const Positioned(left: 10, top: 10, child: _YouTubeMark()),

              VideoProgressBar(video: video, watchedSeconds: _watchedOn(video)),

              // Only when it is known - a pill reading "0:00" on a
              // video whose length nobody has established yet is worse
              // than an empty corner.
              if (video.durationSeconds > 0)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      video.lengthLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: _Avatar(
                            name: video.authorName,
                            avatarUrl: video.authorAvatar,
                            // Keyed on the post id so a given video's
                            // circle is a stable colour, and different
                            // creators rarely collide.
                            colour: _colourFor(int.tryParse(video.postId) ?? 0),
                            fontSize: 9,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            video.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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

  // ── The podcast block ──────────────────────────────────────────────

  /// Dark whatever the app theme is.
  ///
  /// Not an oversight and not a dark-mode leftover: this is one block
  /// on a light page and the inversion is what separates it from the
  /// video sections above. It reads as a different KIND of thing,
  /// which is exactly what it is.
  Widget _podcast() {
    // Nothing published and nothing loading: no block at all. An empty
    // dark panel saying "no episodes" on the main tab is a section
    // apologising for itself on every visit.
    if (!_showPodcast) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 2, bottom: 14),
              child: Row(
                children: [
                  const Expanded(
                    child: DlHeading(
                      'DriveLife podcast',
                      fontSize: 21,
                      color: Colors.white,
                    ),
                  ),
                  GestureDetector(
                    onTap: _openPodcast,
                    child: Text(
                      'See all',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_loadingEpisodes)
              const _EpisodeSkeleton()
            else ...[
              // The latest episode, given the space a new thing
              // deserves.
              _latestEpisode(_episodes.first),

              if (_episodes.length > 1) const SizedBox(height: 14),

              for (final episode in _episodes.skip(1)) ...[
                _episodeRow(episode),
                if (episode != _episodes.last) const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _latestEpisode(LongVideo episode) {
    return GestureDetector(
      onTap: () => _openEpisode(episode),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _thumbnail(episode.thumbnailUrl),
              const _Scrim(),
              Positioned(
                left: 12,
                top: 12,
                child: _pill(label: 'LATEST EPISODE'),
              ),
              const Center(child: _PlayCircle(size: 62, iconSize: 28)),
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

  Widget _episodeRow(LongVideo episode) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openEpisode(episode),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: 104,
              height: 66,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _thumbnail(episode.thumbnailUrl),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  podcastMeta(episode),
                  style: const TextStyle(
                    color: Colors.white70,
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

  // ── Shared pieces ──────────────────────────────────────────────────

  Widget _sectionHeader(
    String title,
    ThemeProvider theme, {
    VoidCallback? action = _noop,
    String label = 'See all',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: DlHeading(title, fontSize: 21, color: theme.textColor),
          ),
          if (action != null)
            GestureDetector(
              onTap: action == _noop ? null : action,
              child: Text(
                label,
                style: TextStyle(
                  color: theme.subtextColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The default for [_sectionHeader]'s action: draw the link, do
  /// nothing on tap. Sections still waiting on a screen use it; a
  /// section that has none passes null and the link is not drawn.
  static void _noop() {}

  Widget _pill({IconData? icon, required String label}) {
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 10 : 7, 5, 10, 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: _ink),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      // No spinner. A thumbnail that flickers a loader on every scroll
      // is noisier than one that simply arrives.
      placeholder: (_, __) => const ColoredBox(color: Color(0xFF1C1C1C)),
      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF1C1C1C)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Small shared widgets
// ─────────────────────────────────────────────────────────────────────

/// Darkens the top and bottom of a thumbnail so white text reads on it.
///
/// Both ends rather than a flat wash: the middle of the picture is the
/// picture, and a card that dims all of it to carry two lines of text
/// has given up the only thing making somebody tap it.
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

/// A vertical list's shape while it loads.
class _VideoListSkeleton extends StatelessWidget {
  const _VideoListSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final block = videoBlockColour(theme);

    return Column(
      children: [
        for (var i = 0; i < 5; i++)
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

/// The hero's shape while it loads.
class _FeaturedSkeleton extends StatelessWidget {
  const _FeaturedSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: videoBlockColour(theme),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

/// And the row's.
class _VideoRowSkeleton extends StatelessWidget {
  const _VideoRowSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) => Container(
          width: 272,
          decoration: BoxDecoration(
            color: videoBlockColour(theme),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// The podcast block's shape while its episodes load.
///
/// Inside an already-dark panel, so the blocks are LIGHTER than their
/// background rather than darker - the usual grey-on-white skeleton
/// inverted, because on #111111 a darker block is invisible.
class _EpisodeSkeleton extends StatelessWidget {
  const _EpisodeSkeleton();

  static const Color _block = Color(0xFF242424);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: Container(
            decoration: BoxDecoration(
              color: _block,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < 2; i++) ...[
          Row(
            children: [
              Container(
                width: 104,
                height: 66,
                decoration: BoxDecoration(
                  color: _block,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 13, color: _block),
                    const SizedBox(height: 7),
                    FractionallySizedBox(
                      widthFactor: 0.55,
                      child: Container(height: 13, color: _block),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (i == 0) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// YouTube's mark, drawn rather than fetched.
class _YouTubeMark extends StatelessWidget {
  const _YouTubeMark();

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

/// A creator's picture, or their initials until there is one.
///
/// Takes a name and a URL rather than a model, so the real creators
/// row and the cards still on mock data draw the same circle.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.colour,
    this.avatarUrl = '',
    this.fontSize = 17,
  });

  final String name;
  final Color colour;
  final String avatarUrl;
  final double fontSize;

  String get _initials {
    final trimmed = name.trim();

    if (trimmed.isEmpty) return '?';

    final parts = trimmed.split(RegExp(r'\s+'));

    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (avatarUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          fit: BoxFit.cover,
          // The initials underneath while it loads and if it fails,
          // rather than a grey disc or a broken-image glyph.
          placeholder: (_, __) => _letters(),
          errorWidget: (_, __, ___) => _letters(),
        ),
      );
    }

    return _letters();
  }

  Widget _letters() {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The creators row's shape while it loads.
class _CreatorSkeleton extends StatelessWidget {
  const _CreatorSkeleton();

  @override
  Widget build(BuildContext context) {
    const block = Color(0xFFE8E8E8);

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(width: 16),
      itemBuilder: (context, index) => const SizedBox(
        width: 72,
        child: Column(
          children: [
            SizedBox(
              width: 68,
              height: 68,
              child: DecoratedBox(
                decoration: BoxDecoration(color: block, shape: BoxShape.circle),
              ),
            ),
            SizedBox(height: 9),
            SizedBox(height: 11, width: 56, child: ColoredBox(color: block)),
          ],
        ),
      ),
    );
  }
}
