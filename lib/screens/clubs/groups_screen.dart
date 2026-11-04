import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/club_api_service.dart';
import 'package:drivelife/api/global_groups_api.dart';
import 'package:drivelife/models/my_clubs.dart';
import 'package:drivelife/screens/clubs/global_group_screen.dart';
import 'package:drivelife/screens/clubs/group_browse_screen.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/clubs/open_club_creator.dart';
import 'package:drivelife/theme/dl_type.dart';
// FilterOption lives beside a bottom sheet rather than with the models,
// which is where ClubApiService.fetchClubTypes() returns it from too.
import 'package:drivelife/widgets/events/filter_bottom_sheet.dart';
import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:drivelife/widgets/groups/group_chrome.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The groups list, redesigned.
///
/// WHAT IS REAL AND WHAT IS NOT
///
/// EVERY section is live. Search and YOUR GROUPS read /clubs; scene,
/// marque and model read /app/v1/groups; BASED ON YOUR GARAGE reads
/// /app/v1/groups/suggested, which matches the group rules against
/// this person's own vehicles. No placeholder data remains.
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
  /// Created and run by DriveLife rather than by a member, which is
  /// the difference between this section and the clubs below it.
  scene,

  /// One make, or one model: Land Rover Defender, Mazda MX-5.
  marque,

  /// Everything a member made themselves. National or local is a
  /// separate, existing flag.
  club,
}

/// A group as every section here needs it, whatever its source.
/// Which half of the screen is showing.
///
/// Communities are national and topical — a marque, a scene. Clubs are
/// local and run by somebody. They were one list until now, which made
/// "Your groups" a rail of two different kinds of thing with nothing to
/// tell them apart.
enum _Tab { communities, clubs }

class GroupSummary {
  final String id;
  final String title;
  final int memberCount;
  final String? image;
  final GroupKind kind;

  /// Faces to show on a scene tile. Empty when unknown — the summary
  /// endpoints return no avatars today, so this is always empty.
  final List<String> memberAvatars;

  /// Set for a GLOBAL GROUP, empty for a club.
  ///
  /// This is also how the two are told apart. A club id is a WordPress
  /// post id and a group id is a ce_groups id: both small integers, so
  /// "42" alone cannot say which table it came from, and opening the
  /// wrong one is a silent bug rather than an error. A slug is
  /// unambiguous, and only global groups have one.
  final String slug;

  /// Why this group is being suggested: "Because of your Mazda MX-5".
  ///
  /// Only set on the garage-match list. Null everywhere else, which is
  /// how the row knows whether to show a second line.
  final String? reason;

  /// draft | published | hidden, for a global group.
  ///
  /// Shown as a badge while testing, because the endpoint is
  /// deliberately returning drafts and a test build should not look
  /// identical to a live one.
  final String status;

  const GroupSummary({
    required this.id,
    required this.title,
    required this.memberCount,
    this.kind = GroupKind.club,
    this.image,
    this.memberAvatars = const [],
    this.slug = '',
    this.status = '',
    this.reason,
  });

  /// True for a global group, false for a club.
  bool get isGlobal => slug.isNotEmpty;

  /// From /app/v1/groups.
  ///
  /// The API's three kinds collapse into two here: `marque` and
  /// `model` share one section on this page ("Marque & model"), and a
  /// third enum value would have to be handled by every switch for no
  /// visible difference. The real kind is still on the group itself
  /// and the detail screen reads it from the API.
  factory GroupSummary.fromGlobalGroup(GlobalGroup group) => GroupSummary(
    id: '${group.id}',
    title: group.title,
    memberCount: group.memberCount,
    image: group.image,
    kind: group.kind == 'scene' ? GroupKind.scene : GroupKind.marque,
    slug: group.slug,
    status: group.status,
    reason: group.reason,
  );

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

  /// Label, its gap and the underline, plus the hairline beneath.
  ///
  /// 64, not the 56 this started at. A 16.5pt label is about 24 high
  /// once its line height is counted, which the first number did not:
  /// 13 + 24 + 10 + 2.5 + 13 + 1 is 63.5, and the row overflowed by the
  /// 7.5 it was short.
  static const double _tabBarHeight = 64;
  static const Color _ink = Color(0xFF111113);
  static const Color _panel = Color(0xFF1E1E21);

  final TextEditingController _search = TextEditingController();

  _Tab _tab = _Tab.communities;

  /// Joined communities and joined clubs, kept apart.
  ///
  /// These were one list. Splitting them is the point of the tabs:
  /// each rail now shows one kind, and its count means something.
  List<GroupSummary> _mine = const [];
  List<GroupSummary> _myClubs = const [];
  bool _loadingMine = true;

  /// The two filters, which are the two MyClubsScreen had.
  ///
  /// NOT club_type. fetchClubs() takes that as well, but it means
  /// public or private — a different question from the one somebody
  /// browsing clubs is asking. Category is what kind of club, location
  /// is where, and between them they are the filter that worked.
  /// What kind of club, from /club-categories.
  ///
  /// This is the filter MyClubsScreen had, and the one that belongs
  /// here. fetchClubs() also takes a club_type, which is national or
  /// local, and the ACF field named club_type is the club's privacy —
  /// three different things, and this is the one worth browsing by.
  String _clubCategory = 'all';
  List<FilterOption> _clubCategories = const [];

  /// 'national', not 'all'.
  ///
  /// This is what the list asked for before it had a filter: the
  /// Communities tab's "Local Clubs" section called
  /// fetchClubs(location: 'national'). Defaulting the new filter to
  /// 'all' changed the query as well as moving it, which is a bad way
  /// to find out whether the move worked.
  String _clubLocation = 'national';

  /// The scene and marque sections, before their first response.
  ///
  /// Separate from _loadingMine because they are separate requests —
  /// and without it both sections simply did not exist until they
  /// arrived, so the page assembled itself under the reader.
  bool _loadingSections = true;

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
  bool _loadingAll = false;

  /// The last fetch threw.
  ///
  /// Held so the list can SAY so. fetchClubs() rethrows on any non-200
  /// and this was caught and dropped, so a server error and a genuinely
  /// empty result drew the same "No groups to show yet" — and there was
  /// no way to tell which from the outside.
  bool _allError = false;
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

  /// Groups with a join or leave in flight, so a second tap cannot
  /// start a second request against the same row.
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _scroll.addListener(_onScroll);
    _loadMine();
    _loadSections();
    // _loadAll() is NOT here. It fetches the clubs list, which only
    // renders on the Local Clubs tab — opening that tab is what asks
    // for it. This screen already makes two requests before it can
    // draw, and most visits never leave Communities.
  }

  /// Fetch the next page a screenful before the end, so the list has
  /// usually grown by the time somebody reaches the bottom of it.
  void _onScroll() {
    if (!_scroll.hasClients || _results != null) return;

    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 600) return;

    // The clubs list is the only paged list on this screen, and it
    // only renders on the clubs tab. Paging it while Communities is
    // showing would fetch pages nobody can see.
    if (_tab != _Tab.clubs) return;

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
      _loadingSections = false;
    });
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Groups of one kind. LIVE.
  ///
  /// This was the swap point and it has been swapped: both sections
  /// now read /app/v1/groups, which serves the ce_groups table rather
  /// than anything to do with clubs.
  ///
  /// Marque and model are fetched together because this page shows
  /// them in one section, and the endpoint takes a comma-separated
  /// list so that costs one request rather than two.
  ///
  /// A failure returns an empty list, which hides the section. The API
  /// client already logs the reason; a section that cannot load should
  /// disappear rather than take the page down.
  Future<List<GroupSummary>> _loadKind(GroupKind kind) async {
    switch (kind) {
      case GroupKind.scene:
        final groups = await GlobalGroupsApi.fetchGroups(
          kinds: const ['scene'],
          perPage: _sectionSize,
        );
        return groups.map(GroupSummary.fromGlobalGroup).toList();

      case GroupKind.marque:
        final groups = await GlobalGroupsApi.fetchGroups(
          kinds: const ['marque', 'model'],
          perPage: _sectionSize,
        );
        return groups.map(GroupSummary.fromGlobalGroup).toList();

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
    final suggestions = await GlobalGroupsApi.fetchSuggested(limit: 3);

    return suggestions.map(GroupSummary.fromGlobalGroup).toList();
  }

  /// Join or leave, from the suggestion row.
  ///
  /// Optimistic: the pill flips immediately and goes back if the
  /// server disagreed. A join that silently failed but still reads
  /// "Joined" is the one outcome worth engineering against — the user
  /// walks away believing they are in a group they are not.
  ///
  /// The group is NOT removed from the list on joining. It would be
  /// tidier, but a row vanishing under the finger that just tapped it
  /// reads as a mis-tap; it goes on the next load instead, by which
  /// point the suggestion endpoint has stopped returning it.
  Future<void> _toggleJoin(GroupSummary group) async {
    if (group.slug.isEmpty) return;

    final wasJoined = _joined.contains(group.id);

    // Ask before leaving, never before joining.
    //
    // The two are not symmetrical: joining is trivially undone by the
    // same button, while leaving loses a membership and — because
    // leaving writes a tombstone — stops the group being suggested
    // again. A confirm on join would just be a tax on the common case.
    if (wasJoined && !await _confirmLeave(group)) return;

    setState(() {
      _busy.add(group.id);
      // The pill shows a spinner while this is in flight rather than
      // flipping straight to its new label: it switched instantly
      // before, which made a slow request look like it had finished.
    });

    final ok = wasJoined
        ? await GlobalGroupsApi.leave(group.slug)
        : await GlobalGroupsApi.join(group.slug);

    if (!mounted) return;

    setState(() {
      _busy.remove(group.id);

      // Applied on success only. The pill waited rather than guessing,
      // so a failure leaves it exactly where it was and there is
      // nothing to roll back.
      if (ok) {
        wasJoined ? _joined.remove(group.id) : _joined.add(group.id);
      }
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasJoined
                ? 'Could not leave ${group.title}.'
                : 'Could not join ${group.title}.',
          ),
        ),
      );
      return;
    }

    // YOUR GROUPS is a different query from this list, so it does not
    // know anything happened. Reloading it here is what puts the group
    // at the top of the page straight away rather than on next open.
    await _loadMine();
  }

  /// "Leave this group?"
  ///
  /// Says what leaving actually costs, because one consequence is not
  /// obvious: the group stops being suggested afterwards. Somebody who
  /// leaves expecting to find it again in BASED ON YOUR GARAGE would
  /// be surprised, and the dialog is the only place to say so.
  Future<bool> _confirmLeave(GroupSummary group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leave ${group.title}?'),
        content: const Text(
          'Your vehicles will be removed from this group, and it will '
          'stop being suggested to you. You can join again by finding '
          'it in the groups list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  /// How many groups a page of the full list holds.
  static const int _pageSize = 15;

  /// How many of a kind the page shows before "See all".
  ///
  /// Six fills the scene grid exactly three rows deep and keeps the
  /// marque list short enough that the sections below it are still
  /// reachable without scrolling past a catalogue.
  static const int _sectionSize = 6;

  /// Open the full, paginated list of one or more kinds.
  void _seeAll(String title, List<String> kinds) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupBrowseScreen(title: title, kinds: kinds),
      ),
    );
  }

  /// The full list, from the top.
  ///
  /// 'national' rather than the endpoint's own default of 'near-me'.
  /// The location filter went with the rest of the filters, so there is
  /// no way for somebody to widen a 25-mile radius that came back
  /// empty — and an empty list they cannot do anything about is worse
  /// than a long one. Filtering returns with Club search.
  Future<void> _loadAll() async {
    // Raised here rather than assumed. This used to start true because
    // initState called it immediately; now that the tab calls it, the
    // list would show its empty state for a frame first.
    setState(() {
      _loadingAll = true;
      _allPage = 1;
      _hasMoreAll = true;
    });

    try {
      final raw = await ClubApiService.fetchClubs(
        category: _clubCategory,
        location: _clubLocation,
        page: 1,
        perPage: _pageSize,
      );

      _allError = false;

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

      debugPrint('[Groups] clubs failed: $e');

      setState(() {
        _loadingAll = false;
        _allError = true;
      });
    }
  }

  Future<void> _loadMoreAll() async {
    if (_loadingMoreAll || !_hasMoreAll || _loadingAll) return;

    setState(() => _loadingMoreAll = true);

    try {
      final raw = await ClubApiService.fetchClubs(
        category: _clubCategory,
        location: _clubLocation,
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

  /// YOUR GROUPS — clubs AND joined global groups.
  ///
  /// Two sources, because they are two different things on the server:
  /// a club is a WordPress post with ACF membership, a global group is
  /// a row in ce_group_members. Reading only the first is why a group
  /// somebody had just joined did not appear here, even though opening
  /// it showed them as a member.
  ///
  /// Global groups lead. They are the ones somebody has joined most
  /// recently and the ones they are least likely to be able to find
  /// again by name.
  Future<void> _loadMine() async {
    // Both started before either is awaited, so they overlap — but
    // without Future.wait, which erases the two different types into
    // List<Object> and needs casting back.
    final clubsRequest = ClubApiService.getMyClubs();
    final groupsRequest = GlobalGroupsApi.fetchGroups(mine: true, perPage: 50);

    final clubsResponse = await clubsRequest;
    final groups = await groupsRequest;

    if (!mounted) return;

    final clubs = clubsResponse.data?.clubs;

    setState(() {
      // Apart, not appended. Each tab's rail shows its own kind, and
      // the "3 joined" beside it counts that kind only.
      _mine = groups.map(GroupSummary.fromGlobalGroup).toList();
      _myClubs = (clubs ?? const <MyClub>[])
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
              else if (_tab == _Tab.clubs)
                ..._clubSlivers(theme)
              else
                ..._browseSlivers(theme),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    // _loadMine() feeds both tabs' rails, so it runs either way. The
    // rest is whichever tab is showing: reloading the communities
    // sections while somebody is pulling on the clubs list spends two
    // requests on content they are not looking at, and leaves the list
    // they ARE looking at untouched.
    await Future.wait([
      _loadMine(),
      if (_tab == _Tab.clubs) _loadAll() else _loadSections(),
    ]);
  }

  Future<void> _loadClubCategories() async {
    // fetchClubTypes() rethrows, and this was once neither awaited nor
    // caught — so a failure became an unhandled async error and left
    // the menu holding only its own label. A filter that cannot load
    // its options should be a filter with one option, not a crash in
    // the console.
    try {
      final options = await ClubApiService.fetchClubTypes();

      if (!mounted) return;

      setState(() => _clubCategories = options);
    } catch (e) {
      debugPrint('[Groups] club categories failed: $e');
    }
  }

  /// One of the two filter pills under ALL CLUBS.
  ///
  /// A menu rather than a bottom sheet: two or three short options
  /// each, and a sheet for that is a lot of movement to change one
  /// word.
  Widget _clubFilter({
    required String label,
    required String value,
    required List<FilterOption> options,
    required ValueChanged<String> onPick,
  }) {
    final selected = options.firstWhere(
      (o) => o.value == value,
      orElse: () => FilterOption(label: label, value: value),
    );

    return PopupMenuButton<String>(
      onSelected: onPick,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        for (final option in options)
          PopupMenuItem(value: option.value, child: Text(option.label)),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDDDDDD)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selected.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          ],
        ),
      ),
    );
  }

  /// The Local Clubs tab.
  List<Widget> _clubSlivers(ThemeProvider theme) {
    return [
      if (_loadingMine || _myClubs.isNotEmpty) ...[
        _sliver(
          _sectionHeader(
            theme,
            'Your clubs',
            trailing: _myClubs.isEmpty
                ? null
                : Text(
                    '${_myClubs.length} joined',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
          ),
        ),
        _sliver(
          _loadingMine
              ? _yourGroupsSkeleton()
              : SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _myClubs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _railCard(_myClubs[i]),
                  ),
                ),
        ),
      ],

      _sliver(const SizedBox(height: 26)),
      _sliver(_sectionHeader(theme, 'All clubs')),

      _sliver(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: _clubFilter(
                  // "All clubs", not "Club type", for the unset state:
                  // a pill reads as the thing it is currently showing,
                  // and "Club type" named the question instead of the
                  // answer.
                  label: 'All clubs',
                  value: _clubCategory,
                  options: [
                    FilterOption(label: 'All clubs', value: 'all'),
                    ..._clubCategories,
                  ],
                  onPick: (value) {
                    setState(() => _clubCategory = value);
                    _loadAll();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _clubFilter(
                  label: 'Location',
                  value: _clubLocation,
                  // The list MyClubsScreen offered. Near me and the two
                  // radii are the ones somebody looking for a local
                  // club actually wants, and club_type never had them.
                  //
                  // 'custom' is left out: it needs a place search and
                  // somewhere to put the coordinates, which is a bigger
                  // change than restoring the filter.
                  options: [
                    FilterOption(label: 'National', value: 'national'),
                    FilterOption(label: 'Everywhere', value: 'all'),
                    FilterOption(label: 'Near me', value: 'near-me'),
                    FilterOption(label: 'Within 50 miles', value: '50-miles'),
                    FilterOption(label: 'Within 100 miles', value: '100-miles'),
                  ],
                  onPick: (value) {
                    setState(() => _clubLocation = value);
                    _loadAll();
                  },
                ),
              ),
            ],
          ),
        ),
      ),

      // The list that used to sit at the foot of Communities. One
      // loader, one list, on the tab it is named after.
      ..._allSlivers(theme),

      _sliver(const SizedBox(height: 120)),
    ];
  }

  /// Communities | Local Clubs.
  Widget _tabBar(ThemeProvider theme) {
    Widget tab(_Tab which, String label) {
      final selected = _tab == which;

      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_tab == which) return;

            setState(() => _tab = which);

            // The clubs list is fetched the first time somebody asks
            // for it, not on open. Most people never leave
            // Communities, and two more requests on every visit to
            // this screen is a cost they would pay for nothing.
            if (which == _Tab.clubs && _all.isEmpty && !_loadingAll) {
              _loadAll();
              _loadClubCategories();
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? _ink : Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 10),
                // The underline is part of the row rather than a
                // decoration on the text, so both tabs are the same
                // height whichever is selected.
                Container(
                  height: 2.5,
                  color: selected ? _ink : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                tab(_Tab.communities, 'Communities'),
                tab(_Tab.clubs, 'Local Clubs'),
              ],
            ),
          ),
          const SizedBox(
            height: 1,
            width: double.infinity,
            child: ColoredBox(color: Color(0xFFEDEDED)),
          ),
        ],
      ),
    );
  }

  Widget _chrome() {
    return SliverPersistentHeader(
      floating: true,
      delegate: FloatingChromeHeader(
        // The tab row travels with the search box. Both are chrome for
        // the list below, and leaving the tabs behind when the header
        // floats away would strand somebody on a page with no way back
        // to the other half of it.
        height: widget.headerHeight + _searchBarHeight + _tabBarHeight,
        vsync: this,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.header != null) widget.header!,
            _searchField(),
            _tabBar(Provider.of<ThemeProvider>(context, listen: false)),
          ],
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

      if (_loadingSections || _scenes.isNotEmpty) ...[
        _sliver(const SizedBox(height: 26)),
        _sliver(
          _sectionHeader(
            theme,
            'Scene groups',
            // "See all", where a "Hosted by DriveLife" badge used to
            // sit. Both would not fit beside a 24pt heading on a
            // phone, and the badge has since been dropped entirely.
            trailing: TextButton(
              onPressed: () => _seeAll('Scene groups', const ['scene']),
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
        _sliver(
          _loadingSections ? const GroupTileGridSkeleton() : _sceneGrid(theme),
        ),
      ],

      if (_loadingSections || _marques.isNotEmpty) ...[
        _sliver(const SizedBox(height: 26)),
        _sliver(
          _sectionHeader(
            theme,
            'Marque & model',
            trailing: TextButton(
              onPressed: () =>
                  _seeAll('Marque & model', const ['marque', 'model']),
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
        _sliver(
          _loadingSections
              ? const GroupRowsSkeleton(count: 4)
              : _marqueList(theme),
        ),
      ],

      // ── Everything else ──────────────────────────────────────────
      //
      // Last, and plainly presented. The sections above are the ones
      // with an argument for why you in particular should look; this
      // is the rest, in the order the server ranks them.
      _sliver(const SizedBox(height: 26)),
      // The clubs list used to end this tab, under a "Local Clubs"
      // heading. It lives on the Local Clubs tab now, which is the
      // whole point of there being one.

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

    return Material(
      color: _panel,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // The row opens the group; only the pill joins it. Deciding
        // whether to join something you cannot look at first is a poor
        // ask, and the pill already stops the tap from reaching here.
        onTap: () => _openGroup(group),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                      // The reason, when there is one, in place of the
                      // member count. Which car put this group in front of
                      // them is more use than how many people are in it —
                      // it is the difference between a recommendation and
                      // an advert.
                      group.reason ?? _members(group.memberCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: Colors.grey.shade500,
                      ),
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
                  onTap: _busy.contains(group.id)
                      ? null
                      : () => _toggleJoin(group),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 11,
                    ),
                    child: _busy.contains(group.id)
                        // Sized to the text it replaces, so the row
                        // does not jump while the request is in
                        // flight.
                        ? SizedBox(
                            height: 19,
                            width: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: joined
                                  ? Colors.grey.shade400
                                  : Colors.white,
                            ),
                          )
                        : Text(
                            joined ? 'Joined' : 'Join',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: joined
                                  ? Colors.grey.shade400
                                  : Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Scene groups  [LIVE: /app/v1/groups?kind=scene] ─────────────

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

  // ─── Marque & model  [LIVE: kind=marque,model] ──────────────────

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _allError
                      ? 'Could not load clubs.'
                      : 'No clubs match those filters.',
                  style: TextStyle(
                    fontSize: 15.5,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (_allError) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loadAll,
                    style: _linkStyle,
                    child: Text(
                      'Try again',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ],
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
    // A GLOBAL GROUP, which is not a club and must not be opened as
    // one. Both carry a bare numeric id from different tables, so
    // group 42 and club 42 both exist — routing on the id alone would
    // silently open the wrong thing. The slug is what disambiguates,
    // and only a global group has one.
    if (group.isGlobal) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GlobalGroupScreen(slug: group.slug)),
      );
      return;
    }

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
