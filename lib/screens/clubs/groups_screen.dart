import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/api/garage_api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/club_api_service.dart';
import 'package:drivelife/models/my_clubs.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/clubs/open_club_creator.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The groups list, redesigned.
///
/// WHAT IS REAL AND WHAT IS NOT
///
/// Two sections are live: the search field and YOUR GROUPS, which read
/// /clubs and /clubs/my-clubs. The rest are drawn from the placeholder
/// lists below, because the backend has no concept of them yet.
///
/// They will come from ONE new field, not three new endpoints. A group
/// is to be classified by an admin as a scene, a marque/model, or an
/// ordinary user club — see [GroupKind] — so every section here is the
/// same query with a different `kind`, and swapping one over is
/// replacing a list with a call.
///
/// What is still missing beyond that field: a relationship between a
/// vehicle and a group (for BASED ON YOUR GARAGE), member avatars on a
/// group summary (the faces on a scene tile), and a join that does not
/// require answering questions. docs/groups-backend-notes.md has the
/// detail.

// ─── Placeholder data ────────────────────────────────────────────────
//
// Deliberately obvious in the code and deliberately ordinary on screen:
// these are here to be replaced, and a mock that looks like a mock gets
// noticed, while one that looks like data gets shipped.

/// What kind of group this is.
///
/// To be an admin-set field on the group itself, which is why it is one
/// enum and not three separate ideas: the sections on this page are the
/// same list filtered three ways.
///
/// Note what is NOT here. A user club being national or local is
/// already stored — `is_national` on the summary, `location_type` on
/// MyClub — so this field must not say it a second time. Two places to
/// record one fact is two places to disagree.
enum GroupKind {
  /// Broad, by interest rather than by car: JDM, Classics, Track Days.
  /// Created and run by DriveLife, which is what the "Hosted by
  /// DriveLife" badge on that section means.
  scene,

  /// One make, or one model: Land Rover Defender, Mazda MX-5.
  marque,

  /// Everything a member made themselves. National or local is a
  /// separate, existing flag.
  club,
}

/// A group as every section here needs it, whatever its source.
class GroupSummary {
  final String id;
  final String title;
  final int memberCount;
  final String? image;
  final GroupKind kind;

  /// Faces to show on a scene tile. Empty when unknown — the summary
  /// endpoints return no avatars today, so this is always empty.
  final List<String> memberAvatars;

  const GroupSummary({
    required this.id,
    required this.title,
    required this.memberCount,
    this.kind = GroupKind.club,
    this.image,
    this.memberAvatars = const [],
  });

  /// From /clubs/my-clubs.
  ///
  /// `Id`, NOT `clubId`. A MyClub carries both: `club_id` is the
  /// ENCRYPTED id the editor addresses a club by, and `id` is the raw
  /// post id everything else wants. Using the encrypted one here threw
  /// a FormatException the moment somebody opened a group they had
  /// joined, because the route does int.parse on it.
  factory GroupSummary.fromMyClub(MyClub club) => GroupSummary(
    id: club.Id ?? '',
    title: club.title,
    memberCount: club.memberCount,
    image: club.coverImage ?? club.logo,
  );
}

/// Suggested from the user's garage. Marques, because that is what a
/// vehicle can be matched to — a scene is too broad to infer from a
/// car, and an ordinary club is somebody else's to advertise.
const _mockGarageMatches = <GroupSummary>[
  GroupSummary(
    id: 'mock-ev',
    title: 'EV Owners',
    memberCount: 2140,
    kind: GroupKind.marque,
  ),
  GroupSummary(
    id: 'mock-polestar',
    title: 'Polestar Owners',
    memberCount: 412,
    kind: GroupKind.marque,
  ),
  GroupSummary(
    id: 'mock-mx5',
    title: 'Mazda MX-5',
    memberCount: 1240,
    kind: GroupKind.marque,
  ),
];

const _mockSceneGroups = <GroupSummary>[
  GroupSummary(
    id: 'mock-4x4',
    title: '4x4 & Overlanding',
    memberCount: 3200,
    kind: GroupKind.scene,
  ),
  GroupSummary(
    id: 'mock-jdm',
    title: 'JDM',
    memberCount: 5800,
    kind: GroupKind.scene,
  ),
  GroupSummary(
    id: 'mock-classics',
    title: 'Classics',
    memberCount: 4100,
    kind: GroupKind.scene,
  ),
  GroupSummary(
    id: 'mock-supercars',
    title: 'Supercars',
    memberCount: 7300,
    kind: GroupKind.scene,
  ),
  GroupSummary(
    id: 'mock-track',
    title: 'Track Days',
    memberCount: 2600,
    kind: GroupKind.scene,
  ),
  GroupSummary(
    id: 'mock-detailing',
    title: 'Detailing',
    memberCount: 3900,
    kind: GroupKind.scene,
  ),
];

const _mockMarques = <GroupSummary>[
  GroupSummary(
    id: 'mock-defender',
    title: 'Land Rover Defender',
    memberCount: 860,
    kind: GroupKind.marque,
  ),
  GroupSummary(
    id: 'mock-mx5-marque',
    title: 'Mazda MX-5',
    memberCount: 1240,
    kind: GroupKind.marque,
  ),
  GroupSummary(
    id: 'mock-gr86',
    title: 'Toyota GR86',
    memberCount: 640,
    kind: GroupKind.marque,
  ),
];

// ─── Screen ──────────────────────────────────────────────────────────

class GroupsScreen extends StatefulWidget {
  /// Told which way the user is scrolling, so the shell can take the
  /// bottom bar away and bring it back.
  final ChromeVisibility? chrome;

  /// The shell's header, drawn inside this screen's own scroll view
  /// rather than above it — above, the only way to hide it would be to
  /// shrink the box it sits in, which resizes the viewport on every
  /// frame of the animation.
  final Widget? header;

  /// How tall [header] is. A sliver header declares its extent up front.
  final double headerHeight;

  const GroupsScreen({
    super.key,
    this.chrome,
    this.header,
    this.headerHeight = 0,
  });

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with TickerProviderStateMixin {
  static const double _searchBarHeight = 62;
  static const Color _ink = Color(0xFF111113);
  static const Color _panel = Color(0xFF1E1E21);

  final TextEditingController _search = TextEditingController();

  List<GroupSummary> _mine = const [];
  bool _loadingMine = true;

  // Read from the loaders above rather than straight from the consts,
  // so the widgets below are already reading state and nothing but the
  // loader changes when these become requests.
  List<GroupSummary> _scenes = const [];
  List<GroupSummary> _marques = const [];
  List<GroupSummary> _garageMatchList = const [];

  /// Every group the server will give us, under everything else.
  ///
  /// The sections above are all curated or personal; this is the plain
  /// list, and it is what somebody scrolls to when none of the
  /// suggestions were what they were after.
  List<GroupSummary> _all = const [];
  bool _loadingAll = true;
  bool _loadingMoreAll = false;
  bool _hasMoreAll = true;
  int _allPage = 1;

  final ScrollController _scroll = ScrollController();

  /// Groups matching the search box, or null when not searching.
  List<GroupSummary>? _results;
  bool _searching = false;

  /// Which placeholder rows the user has tapped Join on.
  ///
  /// Local only — there is nothing to send it to yet. It exists so the
  /// button does something when pressed, because a button that does
  /// nothing reads as broken rather than as unfinished.
  final Set<String> _joined = <String>{};

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _scroll.addListener(_onScroll);
    _loadMine();
    _loadSections();
    _loadAll();
  }

  /// Fetch the next page a screenful before the end, so the list has
  /// usually grown by the time somebody reaches the bottom of it.
  void _onScroll() {
    if (!_scroll.hasClients || _results != null) return;

    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 600) return;

    _loadMoreAll();
  }

  Future<void> _loadSections() async {
    final results = await Future.wait([
      _loadKind(GroupKind.scene),
      _loadKind(GroupKind.marque),
      _loadGarageMatches(),
    ]);

    if (!mounted) return;

    setState(() {
      _scenes = results[0];
      _marques = results[1];
      _garageMatchList = results[2];
    });
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Groups of one kind.
  ///
  /// THE SWAP POINT. When the admin `kind` field exists, each of these
  /// becomes the same call with a different argument — something like
  /// ClubApiService.fetchClubs(kind: 'scene') — and the placeholder
  /// list goes. Until then every section draws from a const above, and
  /// this is the only method that needs to change.
  ///
  /// Deliberately async already, so turning it into a request does not
  /// also mean turning three widgets into loading states.
  Future<List<GroupSummary>> _loadKind(GroupKind kind) async {
    switch (kind) {
      case GroupKind.scene:
        return _mockSceneGroups;
      case GroupKind.marque:
        return _mockMarques;
      case GroupKind.club:
        return const [];
    }
  }

  /// Groups suggested from the user's garage.
  ///
  /// Not a [_loadKind] call even though the results are marques: the
  /// question is "which of these match THIS person's cars", which is a
  /// different query from "list the marques", and nothing relates a
  /// vehicle to a group yet to answer it.
  ///
  /// An empty garage returns nothing, which hides the section. There
  /// is no honest version of "based on your garage" for somebody who
  /// has not added a car — and it is the worst possible first
  /// impression of the feature, since it would be recommending on the
  /// basis of nothing at all.
  Future<List<GroupSummary>> _loadGarageMatches() async {
    try {
      final user = await AuthService().getUser();
      final id = (user?['id'] as num?)?.toInt();
      if (id == null) return const [];

      final garage = await GarageAPI.getUserGarage(id);
      if (garage == null || garage.isEmpty) return const [];

      return _mockGarageMatches;
    } catch (e) {
      debugPrint('[Groups] garage check failed: $e');
      return const [];
    }
  }

  /// How many groups a page of the full list holds.
  static const int _pageSize = 15;

  /// The full list, from the top.
  ///
  /// 'national' rather than the endpoint's own default of 'near-me'.
  /// The location filter went with the rest of the filters, so there is
  /// no way for somebody to widen a 25-mile radius that came back
  /// empty — and an empty list they cannot do anything about is worse
  /// than a long one. Filtering returns with Club search.
  Future<void> _loadAll() async {
    try {
      final raw = await ClubApiService.fetchClubs(
        location: 'national',
        page: 1,
        perPage: _pageSize,
      );

      if (!mounted) return;

      final groups = _parseGroups(raw);

      setState(() {
        _all = groups;
        _allPage = 1;
        _hasMoreAll = groups.length >= _pageSize;
        _loadingAll = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingAll = false);
    }
  }

  Future<void> _loadMoreAll() async {
    if (_loadingMoreAll || !_hasMoreAll || _loadingAll) return;

    setState(() => _loadingMoreAll = true);

    try {
      final raw = await ClubApiService.fetchClubs(
        location: 'national',
        page: _allPage + 1,
        perPage: _pageSize,
      );

      if (!mounted) return;

      final groups = _parseGroups(raw);

      setState(() {
        _all = [..._all, ...groups];
        _allPage += 1;
        _hasMoreAll = groups.length >= _pageSize;
        _loadingMoreAll = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Stops asking. A page that failed once will usually fail again,
      // and a list that retries on every scroll frame is a list that
      // hammers the server while looking broken.
      setState(() {
        _loadingMoreAll = false;
        _hasMoreAll = false;
      });
    }
  }

  /// The club summary shape, whichever list it came from.
  List<GroupSummary> _parseGroups(List<dynamic>? raw) {
    return (raw ?? const [])
        .whereType<Map>()
        .map(
          (c) => GroupSummary(
            id: '${c['ID'] ?? c['id'] ?? ''}',
            title: '${c['title'] ?? ''}',
            memberCount: (c['member_count'] as num?)?.toInt() ?? 0,
            image: c['cover_image'] as String? ?? c['logo'] as String?,
          ),
        )
        .where((g) => g.id.isNotEmpty && g.title.isNotEmpty)
        .toList();
  }

  Future<void> _loadMine() async {
    final response = await ClubApiService.getMyClubs();
    if (!mounted) return;

    setState(() {
      _mine = (response.data?.clubs ?? const <MyClub>[])
          .map(GroupSummary.fromMyClub)
          .toList();
      _loadingMine = false;
    });
  }

  void _onSearchChanged() {
    final query = _search.text.trim();

    if (query.isEmpty) {
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _runSearch(query);
  }

  Future<void> _runSearch(String query) async {
    try {
      final raw = await ClubApiService.fetchClubs(search: query, perPage: 20);

      // Dropped if the box has moved on. Two keystrokes in flight finish
      // in whatever order the network decides, and the slower one must
      // not land on top of the newer answer.
      if (!mounted || _search.text.trim() != query) return;

      setState(() {
        _results = _parseGroups(raw);
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: NotificationListener<ScrollNotification>(
        onNotification: widget.chrome?.handle ?? (_) => false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: theme.primaryColor,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _chrome(),
              if (_results != null)
                ..._searchSlivers(theme)
              else
                ..._browseSlivers(theme),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    await Future.wait([_loadMine(), _loadSections(), _loadAll()]);
  }

  Widget _chrome() {
    return SliverPersistentHeader(
      floating: true,
      delegate: FloatingChromeHeader(
        height: widget.headerHeight + _searchBarHeight,
        vsync: this,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [if (widget.header != null) widget.header!, _searchField()],
        ),
      ),
    );
  }

  Widget _searchField() {
    return SizedBox(
      height: _searchBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'Search groups',
            isDense: true,
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: _search.clear,
                  ),
            filled: true,
            fillColor: const Color(0xFFF2F2F2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Browsing ──────────────────────────────────────────────────────

  List<Widget> _browseSlivers(ThemeProvider theme) {
    return [
      if (_loadingMine || _mine.isNotEmpty) ...[
        _sliver(
          _sectionHeader(
            theme,
            'Your groups',
            trailing: _mine.isEmpty
                ? null
                : Text(
                    '${_mine.length} joined',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
          ),
        ),
        _sliver(_loadingMine ? _yourGroupsSkeleton() : _yourGroupsRail(theme)),
      ],

      if (_garageMatchList.isNotEmpty) ...[
        _sliver(const SizedBox(height: 26)),
        _sliver(_garageMatches(theme)),
      ],

      if (_scenes.isNotEmpty) ...[
        _sliver(const SizedBox(height: 26)),
        _sliver(
          _sectionHeader(
            theme,
            'Scene groups',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, size: 16, color: theme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  'Hosted by DriveLife',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
        _sliver(_sceneGrid(theme)),
      ],

      if (_marques.isNotEmpty) ...[
        _sliver(const SizedBox(height: 26)),
        _sliver(
          _sectionHeader(
            theme,
            'Marque & model',
            trailing: TextButton(
              onPressed: () {},
              style: _linkStyle,
              child: Text(
                'See all',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: theme.primaryColor,
                ),
              ),
            ),
          ),
        ),
        _sliver(_marqueList(theme)),
      ],

      // ── Everything else ──────────────────────────────────────────
      //
      // Last, and plainly presented. The sections above are the ones
      // with an argument for why you in particular should look; this
      // is the rest, in the order the server ranks them.
      _sliver(const SizedBox(height: 26)),
      _sliver(_sectionHeader(theme, 'All groups')),
      ..._allSlivers(theme),

      // Clears the floating bottom bar.
      _sliver(const SizedBox(height: 120)),
    ];
  }

  SliverToBoxAdapter _sliver(Widget child) => SliverToBoxAdapter(child: child);

  static final ButtonStyle _linkStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Widget _sectionHeader(ThemeProvider theme, String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: DlHeading(title, fontSize: 24, color: theme.textColor),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ─── Your groups ───────────────────────────────────────────────────

  /// A sideways rail, not a grid.
  ///
  /// However many groups somebody is in, this section is a reminder
  /// rather than a destination — the list of them lives behind a tap.
  /// A grid would make it the biggest thing on a page whose job is to
  /// show what they have NOT joined.
  Widget _yourGroupsRail(ThemeProvider theme) {
    return SizedBox(
      height: _railHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _mine.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _railCard(_mine[i]),
      ),
    );
  }

  /// Small enough that a second card is always part-visible, which is
  /// what tells somebody the row scrolls. At the old 268x196 one card
  /// filled most of a phone and the section read as a banner.
  static const double _railWidth = 176;
  static const double _railHeight = 132;

  Widget _railCard(GroupSummary group) {
    return SizedBox(
      width: _railWidth,
      child: Material(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openGroup(group),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if ((group.image ?? '').isNotEmpty)
                CachedNetworkImage(
                  imageUrl: group.image!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),

              // Bottom-up scrim. The name sits on a photograph nobody
              // chose for its contrast, so it needs its own.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(11),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _members(group.memberCount),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.white70,
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

  Widget _yourGroupsSkeleton() {
    return SizedBox(
      height: _railHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, _) => Container(
          width: _railWidth,
          decoration: BoxDecoration(
            color: const Color(0xFFEDEDED),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  // ─── Based on your garage  [PLACEHOLDER DATA] ──────────────────────

  Widget _garageMatches(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BASED ON YOUR GARAGE',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: theme.primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'You might like these groups',
              style: TextStyle(fontSize: 16.5, color: Colors.white),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _garageMatchList.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _garageRow(theme, _garageMatchList[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _garageRow(ThemeProvider theme, GroupSummary group) {
    final joined = _joined.contains(group.id);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _members(group.memberCount),
                  style: TextStyle(fontSize: 14.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: joined ? Colors.transparent : theme.primaryColor,
            shape: StadiumBorder(
              side: joined
                  ? BorderSide(color: Colors.grey.shade700)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() {
                joined ? _joined.remove(group.id) : _joined.add(group.id);
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 11,
                ),
                child: Text(
                  joined ? 'Joined' : 'Join',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: joined ? Colors.grey.shade400 : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Scene groups  [PLACEHOLDER DATA] ──────────────────────────────

  Widget _sceneGrid(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final tile = (constraints.maxWidth - gap) / 2;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final group in _scenes)
                SizedBox(
                  width: tile,
                  height: tile * 0.78,
                  child: _sceneTile(group),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _sceneTile(GroupSummary group) {
    return Material(
      color: Colors.grey.shade300,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openGroup(group),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if ((group.image ?? '').isNotEmpty)
              CachedNetworkImage(
                imageUrl: group.image!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Faces, when there are any. The design shows two
                  // overlapping members; the summary endpoint returns
                  // no avatars, so today there are none to show and
                  // the tile simply omits them.
                  if (group.memberAvatars.isNotEmpty)
                    _avatarStack(group.memberAvatars),
                  const Spacer(),
                  Text(
                    group.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _members(group.memberCount),
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarStack(List<String> urls) {
    const size = 34.0;

    return SizedBox(
      height: size,
      width: size + (urls.length - 1) * (size * 0.62),
      child: Stack(
        children: [
          for (var i = 0; i < urls.length; i++)
            Positioned(
              left: i * (size * 0.62),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  image: DecorationImage(
                    image: CachedNetworkImageProvider(urls[i]),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Marque & model  [PLACEHOLDER DATA] ────────────────────────────

  Widget _marqueList(ThemeProvider theme) {
    return Column(
      children: [
        for (var i = 0; i < _marques.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(left: 92, right: 16),
              child: Divider(height: 1, color: Colors.grey.shade200),
            ),
          _groupRow(theme, _marques[i]),
        ],
      ],
    );
  }

  /// One group as a row: thumbnail, name, members, chevron.
  ///
  /// Shared by Marque & model, by search results and by the full list
  /// at the bottom — they are the same thing presented the same way,
  /// and three copies of it would be three places to restyle.
  Widget _groupRow(ThemeProvider theme, GroupSummary group) {
    return InkWell(
      onTap: () => _openGroup(group),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 64,
                height: 48,
                color: Colors.grey.shade200,
                child: (group.image ?? '').isEmpty
                    ? Icon(
                        Icons.directions_car_outlined,
                        color: Colors.grey.shade400,
                        size: 22,
                      )
                    : CachedNetworkImage(
                        imageUrl: group.image!,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: theme.textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _members(group.memberCount),
                    style: TextStyle(
                      fontSize: 14.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 22),
          ],
        ),
      ),
    );
  }

  // ─── All groups ────────────────────────────────────────────────────

  List<Widget> _allSlivers(ThemeProvider theme) {
    if (_loadingAll) {
      return [
        _sliver(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(color: theme.primaryColor),
            ),
          ),
        ),
      ];
    }

    if (_all.isEmpty) {
      return [
        _sliver(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Text(
              'No groups to show yet.',
              style: TextStyle(fontSize: 15.5, color: Colors.grey.shade600),
            ),
          ),
        ),
      ];
    }

    return [
      SliverList.separated(
        itemCount: _all.length,
        separatorBuilder: (_, _) => Padding(
          padding: const EdgeInsets.only(left: 92, right: 16),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ),
        itemBuilder: (_, i) => _groupRow(theme, _all[i]),
      ),
      if (_loadingMoreAll)
        _sliver(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: theme.primaryColor,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  // ─── Search ────────────────────────────────────────────────────────

  List<Widget> _searchSlivers(ThemeProvider theme) {
    final results = _results ?? const <GroupSummary>[];

    if (_searching && results.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(color: theme.primaryColor),
          ),
        ),
      ];
    }

    if (results.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
            child: Column(
              children: [
                Icon(Icons.search_off, size: 54, color: Colors.grey.shade300),
                const SizedBox(height: 14),
                Text(
                  'No groups match “${_search.text.trim()}”',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => openClubCreator(context),
                  child: Text(
                    'Start one instead',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverList.separated(
        itemCount: results.length,
        separatorBuilder: (_, _) => Padding(
          padding: const EdgeInsets.only(left: 92, right: 16),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ),
        itemBuilder: (_, i) => _groupRow(theme, results[i]),
      ),
      _sliver(const SizedBox(height: 120)),
    ];
  }

  // ─── Shared ────────────────────────────────────────────────────────

  void _openGroup(GroupSummary group) {
    // A placeholder row has no club behind it, so there is nowhere to
    // go. Said out loud rather than silently ignored, so it is obvious
    // in testing which rows are not wired up yet.
    if (group.id.startsWith('mock-')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${group.title} is placeholder content')),
      );
      return;
    }

    // Checked here, not left to the route. AppRoutes.clubDetail does
    // int.parse on whatever it is given and throws on anything else,
    // and a tap that does nothing beats a tap that takes the app down.
    if (int.tryParse(group.id) == null) {
      debugPrint('[Groups] ${group.title} has a non-numeric id: ${group.id}');
      return;
    }

    Navigator.pushNamed(
      context,
      AppRoutes.clubDetail,
      arguments: {'clubId': group.id},
    );
  }

  /// "188 members", "3.2k members".
  ///
  /// Abbreviated above a thousand, unlike the points balance: there the
  /// exact figure is the point, here it is a rough sense of how busy a
  /// group is and "3,910" asks to be read digit by digit.
  static String _members(int n) {
    if (n < 1000) return '$n member${n == 1 ? '' : 's'}';

    final thousands = n / 1000;
    final label = thousands >= 10
        ? thousands.round().toString()
        : thousands.toStringAsFixed(1).replaceAll('.0', '');

    return '${label}k members';
  }
}
