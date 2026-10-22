import 'package:drivelife/api/tracks_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/widgets/listing/listing_row.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:drivelife/widgets/nav/pinned_sliver_bar.dart';
import 'package:drivelife/widgets/listing/listing_chips.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/widgets/nav/dl_haptics.dart';
import 'package:provider/provider.dart';

/// One track, as the list shows it.
@immutable
class TrackSummary {
  final String id;
  final String title;
  final String? location;
  final String? image;
  final double? distance;
  final String? site;

  /// "Race circuit", "Drag strip", and so on. A track can be several at once,
  /// which is why this is a list rather than one value.
  final List<String> types;

  const TrackSummary({
    required this.id,
    required this.title,
    this.location,
    this.image,
    this.distance,
    this.site,
    this.types = const [],
  });

  static String? _text(dynamic value) {
    if (value == null) return null;
    final s = '$value'.trim();
    // "false" and "null" arrive as literal strings often enough to matter:
    // PHP's wp_get_attachment_image_url returns false for a missing
    // attachment, and an absent ACF field encodes as null. Rendered, they
    // become a caption reading "false" or a request for an image at that
    // address.
    if (s.isEmpty || s == 'null' || s == 'false') return null;
    return s;
  }

  /// A URL, or null if it is not one.
  ///
  /// Stricter than [_text] because this feeds an image loader, where anything
  /// that is not an address is a guaranteed failed request and a broken tile.
  static String? _url(dynamic value) {
    final text = _text(value);
    if (text == null) return null;
    return text.startsWith('http') ? text : null;
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  /// The track types, dropping anything that is not a usable label.
  static List<String> _types(dynamic value) {
    if (value is! List) return const [];
    return value.map(_text).whereType<String>().toList(growable: false);
  }

  factory TrackSummary.fromJson(Map<String, dynamic> json) {
    return TrackSummary(
      // Capital ID: the server returns the raw column name.
      id: '${json['ID'] ?? json['id'] ?? ''}',
      title: _text(json['title']) ?? 'Untitled track',
      location: _text(json['track_location']),
      // The logo first, the cover second.
      //
      // A listing thumbnail is 56px square, and a cover photo cropped to
      // that is a patch of sky or a wheel arch — it says nothing about
      // which track it is. A badge is designed to be read small and is the
      // thing people recognise. The cover is the fallback for the tracks
      // that have no badge yet.
      image: _url(json['logo']) ?? _url(json['cover_image']),
      distance: _number(json['distance']),
      site: _text(json['site']),
      types: _types(json['types']),
    );
  }
}

/// How far out to look.
///
/// The same set the venues screen offers, so the two behave alike — and the
/// same keywords the server already understands, so this needs nothing new
/// behind it.
@immutable
class TrackRange {
  final String label;
  final String value;

  const TrackRange(this.label, this.value);

  static const List<TrackRange> all = [
    TrackRange('Near me', 'near-me'),
    TrackRange('50 miles', '50-miles'),
    TrackRange('100 miles', '100-miles'),
    TrackRange('National', 'national'),
  ];
}

/// Tracks & raceways.
///
/// Its own screen rather than the venues one with a different post type. The
/// shared version listed the user's *venues* under "My tracks", because that
/// tab called a venue-only endpoint — the kind of thing that happens when two
/// unrelated things share a file to save typing.
class TracksScreen extends StatefulWidget {
  /// Told which way the user is scrolling, so the shell can take the bottom
  /// bar away and bring it back. The same notifier the feed reports to.
  final ChromeVisibility? chrome;

  /// The shell's header and section tabs, drawn inside this screen's own
  /// scroll view rather than above it — see [VenuesScreen.header] for why
  /// that is the only way to move it without resizing the viewport.
  final Widget? header;

  /// How tall [header] is. A sliver header declares its extent up front.
  final double headerHeight;

  const TracksScreen({
    super.key,
    this.chrome,
    this.header,
    this.headerHeight = 0,
  });

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen>
    with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<TrackSummary> _nearby = const [];
  List<TrackSummary> _owned = const [];
  List<TrackSummary> _followed = const [];

  bool _loading = true;
  bool _loadingMine = true;
  String? _error;
  String _query = '';

  /// Which range the list is showing. Changing it refetches, because the
  /// radius is applied by the server rather than to the loaded page.
  /// 100 miles, as Places starts. Near me is the tightest of the four and
  /// usually empty on a first run — a circuit is rarely round the corner.
  String _range = '100-miles';

  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _tabs.addListener(_onTabChanged);
    attachTabHaptics(_tabs);
    _loadNearby();
    _loadMine();
  }

  /// The tabs no longer live in a TabBarView, so nothing swaps the content
  /// for us — this does, by rebuilding with the other tab's slivers on
  /// stage.
  void _onTabChanged() {
    if (!mounted) return;

    setState(() {});

    // Back to the top on a real switch. The two tabs share one scroll
    // offset now, and landing halfway down a tab holding two rows reads as
    // an empty tab.
    if (!_tabs.indexIsChanging && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Only the Discover tab pages. Both tabs share one scroll controller
    // now, so without this, reaching the bottom of My Tracks would fetch
    // another page of nearby ones behind it.
    if (_tabs.index != 0) return;

    if (!_scroll.hasClients || _loadingMore || !_hasMore) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadNearby(more: true);
    }
  }

  Future<void> _loadNearby({bool more = false}) async {
    if (more) {
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    }

    final result = await TracksApiService.getTracks(
      page: more ? _page + 1 : 1,
      limit: 20,
      location: _range,
      search: _query,
    );
    if (!mounted) return;

    if (result == null) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (!more) _error = 'Could not load tracks. Pull down to try again.';
      });
      return;
    }

    final rows = (result['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TrackSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    setState(() {
      if (more) {
        _nearby = [..._nearby, ...rows];
        _page += 1;
      } else {
        _nearby = rows;
      }
      // A short page is the last page. Trusting total_pages instead would
      // keep asking for pages the radius has already run out of.
      _hasMore = rows.length >= 20;
      _loading = false;
      _loadingMore = false;
    });
  }

  Future<void> _loadMine() async {
    setState(() => _loadingMine = true);

    final result = await TracksApiService.getMyTracks();
    if (!mounted) return;

    List<TrackSummary> read(String key) => (result?[key] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TrackSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    setState(() {
      _owned = read('owned_tracks');
      _followed = read('followed_tracks');
      _loadingMine = false;
    });
  }

  void _open(TrackSummary track) => Navigator.pushNamed(
    context,
    AppRoutes.trackDetails,
    arguments: {'trackId': track.id, 'site': track.site},
  );

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      // Nothing above the scroll views. The header, the search field and
      // the tabs are slivers inside them, so the scroll moves them and the
      // viewport keeps one size — the arrangement the feed uses.
      //
      // Every scroll in here reports to the shell through this listener,
      // which is what takes the bottom bar away and brings it back.
      body: NotificationListener<ScrollNotification>(
        onNotification: widget.chrome?.handle ?? (_) => false,
        child: RefreshIndicator(
          color: theme.primaryColor,
          onRefresh: _refreshActiveTab,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _floatingChrome(),
              _pinnedTabs(theme),

              // One scroll view, not one per tab inside a TabBarView. With
              // a view each, the chrome and the tabs were inside the thing
              // that slides, so switching tab swept the header off sideways
              // and brought an identical one back — the whole page moving
              // to change what is under it. Here only the content swaps.
              //
              // The tab that is not showing stays in the tree: SliverOffstage
              // does not lay it out, but its element is still mounted, so
              // what it had loaded survives a switch.
              SliverOffstage(
                offstage: _tabs.index != 0,
                sliver: SliverMainAxisGroup(slivers: _findSlivers(theme)),
              ),
              SliverOffstage(
                offstage: _tabs.index != 1,
                sliver: SliverMainAxisGroup(slivers: _mineSlivers(theme)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Discover / My Tracks row. Lifted out of build() so a pinned sliver
  /// can hold it in both tabs.
  Widget _tabBar(ThemeProvider theme) {
    return TabBar(
      controller: _tabs,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorColor: theme.primaryColor,
      indicatorWeight: 3,
      labelColor: theme.primaryColor,
      unselectedLabelColor: theme.subtextColor,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
      tabs: const [
        Tab(
          height: _tabHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore_outlined, size: 18),
              SizedBox(width: 6),
              Text('Discover'),
            ],
          ),
        ),
        Tab(
          height: _tabHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_border_rounded, size: 18),
              SizedBox(width: 6),
              Text('My Tracks'),
            ],
          ),
        ),
      ],
    );
  }

  /// The search field's height, declared because the floating header has
  /// to know its extent before layout. [_searchBarField] boxes itself to
  /// the same number so the two cannot drift.
  ///
  /// 62: an 8/8 margin around a 46 field, matching Places.
  static const double _searchBarHeight = 62;

  /// How tall one tab is.
  ///
  /// Declared, because Flutter's default is 46 and a TabBar adds its
  /// indicatorWeight on top — 49 in all, which does not fit the 44 the
  /// pinned sliver declares for the row. A SizedBox does not shrink a
  /// TabBar; it overflows it.
  ///
  ///   40 + 3 indicator = 43, inside 44.
  static const double _tabHeight = 40;

  /// The tab row's height, declared for the same reason.
  static const double _tabBarHeight = 44;

  /// The shell's header and section tabs, with this screen's search field
  /// under them. Floating: gone as you scroll on, back the moment you
  /// scroll up, without having to reach the top.
  Widget _floatingChrome() {
    return SliverPersistentHeader(
      floating: true,
      delegate: FloatingChromeHeader(
        height: widget.headerHeight + _searchBarHeight,
        vsync: this,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.header != null) widget.header!,
            _searchBarField(),
          ],
        ),
      ),
    );
  }

  /// Discover / My Tracks, pinned. Navigation, so it stays.
  Widget _pinnedTabs(ThemeProvider theme) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: PinnedSliverBar(height: _tabBarHeight, child: _tabBar(theme)),
    );
  }

  /// The search field, without the theme it never used.
  Widget _searchBarField() {
    return SizedBox(
      height: _searchBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) {
            setState(() => _query = value);
            _loadNearby();
          },
          decoration: InputDecoration(
            hintText: 'Search tracks & raceways',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                      _loadNearby();
                    },
                  ),
            filled: true,
            fillColor: const Color(0xFFF4F4F4),
            // Dense, because the box around this is 46 tall and a filled
            // field with a prefix icon asks for 48 unless told otherwise.
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  /// The distance pills.
  ///
  /// The shared [ListingChips], the same row Places uses, so the two
  /// listing screens do not drift into two slightly different pills.
  Widget _ranges(ThemeProvider theme) {
    return Padding(
      // Room above as well as below. The pills used to sit under a search
      // field that carried its own 12 of bottom padding; now the pinned tab
      // row is directly above them, and its underline was touching them.
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: ListingChips(
        selected: _range,
        onChanged: (value) {
          if (value == _range) return;
          setState(() => _range = value);
          _loadNearby();
        },
        chips: [
          for (final range in TrackRange.all)
            ListingChip(label: range.label, value: range.value),
        ],
      ),
    );
  }

  /// The Discover tab, as slivers.
  List<Widget> _findSlivers(ThemeProvider theme) {
    if (_loading) {
      return [
        _fillRest(
          Center(child: CircularProgressIndicator(color: theme.primaryColor)),
        ),
      ];
    }

    if (_error != null && _nearby.isEmpty) {
      return [_fillRest(_Message(text: _error!, onRetry: _loadNearby))];
    }

    if (_nearby.isEmpty) {
      // Names the filter that produced the empty list, so the next move is
      // obvious. "None found" alone invites a reload that changes nothing.
      final where = TrackRange.all
          .firstWhere(
            (r) => r.value == _range,
            orElse: () => TrackRange.all.first,
          )
          .label
          .toLowerCase();

      return [
        // The pills stay: the way out of an empty list is to widen the
        // range, and that is the control that does it.
        SliverToBoxAdapter(child: _ranges(theme)),
        _fillRest(
          _Message(
            text: _query.isNotEmpty
                ? 'No tracks matching "$_query" $where.'
                : 'No tracks or raceways $where yet.\nTry widening the range.',
          ),
        ),
      ];
    }

    return [
      // The distance pills, in the list rather than above it. They used
      // to sit between the search field and the tabs and be shown only
      // on this tab, so the row above the tabs changed height every time
      // you switched — the one thing a pinned tab row must not do.
      SliverToBoxAdapter(child: _ranges(theme)),

      // Rows, the same as Places lists its venues — the two sections are
      // the same kind of list and should not be two different shapes.
      //
      // The address rather than the track's disciplines, for the same
      // reason: whatever reads better in the abstract, a row that says one
      // thing on one screen and another on the next is harder to read than
      // either. The disciplines are on the track's own page.
      SliverPadding(
        padding: const EdgeInsets.only(top: 8),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            final track = _nearby[i];

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i > 0) const ListingRowDivider(),
                ListingRow(
                  imageUrl: track.image ?? '',
                  title: track.title,
                  subtitle: track.location,
                  onTap: () => _open(track),
                ),
              ],
            );
          }, childCount: _nearby.length),
        ),
      ),
      if (_loadingMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(
                color: theme.primaryColor,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  /// Fills what is left of the viewport with [child], for the states that
  /// are not a list.
  Widget _fillRest(Widget child) =>
      SliverFillRemaining(hasScrollBody: false, child: child);

  /// Refreshes whichever tab is showing.
  Future<void> _refreshActiveTab() =>
      _tabs.index == 0 ? _loadNearby() : _loadMine();

  /// The My Tracks tab, as slivers.
  List<Widget> _mineSlivers(ThemeProvider theme) {
    if (_loadingMine) {
      return [
        _fillRest(
          Center(child: CircularProgressIndicator(color: theme.primaryColor)),
        ),
      ];
    }

    if (_owned.isEmpty && _followed.isEmpty) {
      return [
        _fillRest(
          const _Message(text: "You don't own or follow any tracks yet."),
        ),
      ];
    }

    return [
      // The same rows the Discover tab uses, and the same rows Places
      // uses. The group titles stay: owning a track and following one are
      // different things, and the list is short enough to say so.
      SliverPadding(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            if (_owned.isNotEmpty) ...[
              const _GroupTitle('Tracks you manage'),
              for (var i = 0; i < _owned.length; i++) ...[
                if (i > 0) const ListingRowDivider(),
                ListingRow(
                  imageUrl: _owned[i].image ?? '',
                  title: _owned[i].title,
                  subtitle: _owned[i].location,
                  onTap: () => _open(_owned[i]),
                ),
              ],
            ],
            if (_followed.isNotEmpty) ...[
              const _GroupTitle('Following'),
              for (var i = 0; i < _followed.length; i++) ...[
                if (i > 0) const ListingRowDivider(),
                ListingRow(
                  imageUrl: _followed[i].image ?? '',
                  title: _followed[i].title,
                  subtitle: _followed[i].location,
                  onTap: () => _open(_followed[i]),
                ),
              ],
            ],
          ]),
        ),
      ),
    ];
  }
}

class _GroupTitle extends StatelessWidget {
  final String text;

  const _GroupTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 16 to the left, which is where the thumbnails below it start.
      //
      // It was 4, back when the list around it carried its own 16 of
      // horizontal padding. The rows now bring their own, so the group
      // title was the only thing left sitting against the screen edge.
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1C1C1E),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _Message({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF8A8A8E)),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
