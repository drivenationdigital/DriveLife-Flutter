import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/tracks_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/widgets/listing/listing_card.dart';
import 'package:drivelife/widgets/listing/listing_chips.dart';
import 'package:flutter/material.dart';
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
      image: _url(json['cover_image']) ?? _url(json['logo']),
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
  const TracksScreen({super.key});

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen>
    with SingleTickerProviderStateMixin {
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
    _loadNearby();
    _loadMine();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onScroll() {
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
      body: Column(
        children: [
          _searchBar(theme),
          // Only on the nearby list. "My tracks" is everything the user owns
          // or follows, wherever it is, so a distance filter over it would
          // hide their own tracks.
          AnimatedBuilder(
            animation: _tabs,
            builder: (context, _) =>
                _tabs.index == 0 ? _ranges(theme) : const SizedBox.shrink(),
          ),
          TabBar(
            controller: _tabs,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorColor: theme.primaryColor,
            indicatorWeight: 3,
            labelColor: theme.primaryColor,
            unselectedLabelColor: theme.subtextColor,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
            tabs: const [
              Tab(
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
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_findTab(theme), _mineTab(theme)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
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
      padding: const EdgeInsets.only(bottom: 8),
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

  Widget _findTab(ThemeProvider theme) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    if (_error != null && _nearby.isEmpty) {
      return _Message(text: _error!, onRetry: _loadNearby);
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

      return _Message(
        text: _query.isNotEmpty
            ? 'No tracks matching "$_query" $where.'
            : 'No tracks or raceways $where yet.\nTry widening the range.',
      );
    }

    return RefreshIndicator(
      color: theme.primaryColor,
      onRefresh: _loadNearby,
      // Two to a row, as Places lists its venues. A circuit is recognised
      // from its photograph long before its address is read, and at two
      // columns twice as many are on screen.
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                const gap = 12.0;
                final cardWidth = (constraints.crossAxisExtent - gap) / 2;

                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: gap,
                    childAspectRatio:
                        cardWidth / (cardWidth / 1.35 + _cardChrome),
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final track = _nearby[i];

                    return ListingCard(
                      imageUrl: track.image ?? '',
                      title: track.title,
                      // The track type reads better than the address here —
                      // "Race Circuit" is what someone is scanning for, and
                      // the address is on the track's own page.
                      subtitle: track.types.isNotEmpty
                          ? track.types.join(' · ')
                          : track.location,
                      onTap: () => _open(track),
                    );
                  }, childCount: _nearby.length),
                );
              },
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
        ],
      ),
    );
  }

  Widget _mineTab(ThemeProvider theme) {
    if (_loadingMine) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    if (_owned.isEmpty && _followed.isEmpty) {
      return const _Message(text: "You don't own or follow any tracks yet.");
    }

    return RefreshIndicator(
      color: theme.primaryColor,
      onRefresh: _loadMine,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_owned.isNotEmpty) ...[
            const _GroupTitle('Tracks you manage'),
            for (final t in _owned) _TrackCard(track: t, onTap: () => _open(t)),
          ],
          if (_followed.isNotEmpty) ...[
            const _GroupTitle('Following'),
            for (final t in _followed)
              _TrackCard(track: t, onTap: () => _open(t)),
          ],
        ],
      ),
    );
  }
}

/// Everything in a [ListingCard] below the picture, in logical pixels.
/// The same stack Places measures — see _listingCardChrome there.
const double _cardChrome = 156;

class _GroupTitle extends StatelessWidget {
  final String text;

  const _GroupTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
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

class _TrackCard extends StatelessWidget {
  final TrackSummary track;
  final VoidCallback onTap;

  const _TrackCard({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final distance = track.distance;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              SizedBox(
                width: 104,
                height: 92,
                child: track.image == null
                    ? const ColoredBox(
                        color: Color(0xFFE6E6E6),
                        child: Icon(
                          Icons.sports_score_rounded,
                          color: Color(0xFF9A9A9E),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: track.image!,
                        fit: BoxFit.cover,
                        // Capped at the size it is drawn, so a 2000px cover
                        // photo does not decode to 16MB for a 104px tile.
                        memCacheWidth:
                            (104 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        errorWidget: (_, _, _) =>
                            const ColoredBox(color: Color(0xFFE6E6E6)),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1C1C1E),
                        ),
                      ),
                      if (track.types.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        // One, not all of them: a card is not the place for
                        // a track's full list of disciplines, and the first
                        // is the one the admin screen lists first.
                        Text(
                          track.types.length == 1
                              ? track.types.first
                              : '${track.types.first} +${track.types.length - 1}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB08E4F),
                          ),
                        ),
                      ],
                      if (track.location != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          track.location!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF8A8A8E),
                          ),
                        ),
                      ],
                      if (distance != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          '${distance.toStringAsFixed(distance < 10 ? 1 : 0)} miles away',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB08E4F),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Color(0xFFC4C4C6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
