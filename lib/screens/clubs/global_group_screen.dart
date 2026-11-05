import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/components/post_card.dart';
import 'package:drivelife/api/global_groups_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:drivelife/widgets/feed/feed_divider.dart';
import 'package:drivelife/screens/create-post/create_post_screen.dart';
import 'package:drivelife/widgets/home/home_activity_card.dart';
import 'package:drivelife/widgets/groups/group_chrome.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A global group, viewed.
///
/// GLOBAL GROUPS ONLY — scene, marque and model. Clubs keep their
/// existing screen. The intention is that clubs move onto this UI
/// later, which is why nothing here is named after a scene or a
/// marque and why the tabs are driven by counts rather than by kind:
/// pointing it at a club should eventually be a matter of giving it a
/// different data source, not a rewrite.
///
/// READ ONLY, deliberately.
///
/// The designs show a Joined pill and a composer, and both are drawn
/// here — but neither writes. Membership and posting are a later step,
/// and while this is being tested against production data a screen
/// that cannot write cannot surprise anybody. Each is wired to a
/// single "not yet" snackbar rather than being hidden, so the layout
/// is the real one and turning them on later is replacing a callback.
///
/// WHAT IS REAL
///
///   Latest    activity index — empty until the refresh has run
///   Garages   ce_group_vehicles — same
///   Spots     activity index, item_type 'spot' — same
///   Events    NOTHING. No column, no table, no rule relates an event
///             to a global group. The tab is here because the design
///             has it and because the shape should exist before the
///             relationship is designed; it says so on screen rather
///             than showing a bare empty state.
///
/// "Car of the week" from the design is not built: nothing picks one.
/// Left out rather than faked with the top-liked car, which would be a
/// different claim wearing the same badge.
class GlobalGroupScreen extends StatefulWidget {
  const GlobalGroupScreen({super.key, required this.slug, this.initial});

  final String slug;

  /// What the list already knew, so the header renders immediately
  /// instead of flashing a spinner over data we have in hand.
  final GlobalGroup? initial;

  @override
  State<GlobalGroupScreen> createState() => _GlobalGroupScreenState();
}

class _GlobalGroupScreenState extends State<GlobalGroupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  GlobalGroup? _group;
  List<Map<String, dynamic>> _latest = const [];
  List<GlobalGroupVehicle> _garages = const [];

  /// How many each tab holds in ALL, so a list knows whether it has
  /// reached the end or merely the end of a page. A page length cannot
  /// answer that: a tab with exactly one page of content would otherwise
  /// sit waiting for a page that never comes.
  int _garageTotal = 0;
  int _latestTotal = 0;
  int _spotTotal = 0;

  bool _garagesLoadingMore = false;
  bool _latestLoadingMore = false;
  bool _spotsLoadingMore = false;

  /// The last page each tab has FETCHED, which is not the same as how
  /// much of it is on screen.
  ///
  /// These used to be worked out as `items.length ~/ perPage + 1`. That
  /// holds only while every row the endpoint returns becomes a card, and
  /// Latest is a feed where plenty do not: an item_type this build does
  /// not know resolves to nothing, a post already on the page is
  /// deduped, a gallery that is not live hydrates to nothing. One short
  /// page and the arithmetic stops advancing - it asks for the page it
  /// just had, every row of it is already on screen so nothing is
  /// appended, and it asks again on the next scroll, for ever.
  int _garagePage = 1;
  int _latestPage = 1;
  int _spotPage = 1;

  /// Whether the NEXT page would start before the end of the rows.
  ///
  /// In pages, because the totals count rows in the index and a page is a
  /// window over them. `items.length < total` compared a card count
  /// against a row count: a group with 1244 activity rows of which any
  /// one fails to hydrate could never satisfy it, so the skeleton sat at
  /// the bottom of the list for ever even with every page fetched.
  bool get _garagesHasMore => _garagePage * _garagesPerPage < _garageTotal;
  bool get _latestHasMore => _latestPage * _latestPerPage < _latestTotal;
  bool get _spotsHasMore => _spotPage * _spotsPerPage < _spotTotal;

  /// What each tab asks for per page. Matched to the endpoints' own
  /// defaults, and used to work out which page to ask for next.
  static const int _latestPerPage = 15;
  static const int _spotsPerPage = 30;
  static const int _garagesPerPage = 24;
  List<GlobalGroupSpot> _spots = const [];
  List<GlobalGroupEvent> _events = const [];

  bool _loading = true;
  bool _failed = false;

  /// A join or leave in flight, so a second tap cannot start a second
  /// request.
  bool _joining = false;

  /// Uploads this screen has already reloaded for.
  ///
  /// Seeded on the first look with whatever is ALREADY finished, so
  /// opening a group while an unrelated upload sits completed does not
  /// reload the feed on arrival. Only an upload that completes while
  /// this screen is mounted is news.
  final Set<String> _seenUploads = {};
  bool _uploadsSeeded = false;

  /// One reload per burst. Several photos finishing together would
  /// otherwise each ask for the same page.
  bool _reloadScheduled = false;

  /// The membership state while the server catches up, or null to use
  /// whatever the group last said. Cleared by the reload that follows
  /// a successful join.
  bool? _joinedOverride;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _group = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Everything at once.
  ///
  /// Four small requests in parallel rather than one per tab on first
  /// view: the counts are in the header from the start, so a tab that
  /// says 212 and then takes a second to fill would be the worse
  /// experience. Revisit if any of these grows expensive.
  Future<void> _load() async {
    // All five start together, but the GROUP is awaited on its own.
    //
    // They used to be one Future.wait, so the screen showed its skeleton
    // page until the slowest of five requests came back — and the Latest
    // feed is much the heaviest of them, hydrating posts, vehicles,
    // galleries and now photo sets. Opening a group meant waiting on
    // that before the title and the Join button would even appear, which
    // is why a cold open spins and a second one is instant: the cost is
    // in the feed, and by then the server has it warm.
    //
    // The group itself is one row. Rendering the page around it the
    // moment it lands gives something to look at and somewhere to tap,
    // while the tabs fill in behind their own skeletons.
    final groupRequest = GlobalGroupsApi.fetchGroup(widget.slug);
    final activityRequest = GlobalGroupsApi.fetchActivity(widget.slug);
    final vehiclesRequest = GlobalGroupsApi.fetchVehicles(widget.slug);
    final spotsRequest = GlobalGroupsApi.fetchSpots(widget.slug);
    final eventsRequest = GlobalGroupsApi.fetchEvents(widget.slug);

    final group = await groupRequest;

    if (!mounted) return;

    setState(() {
      _group = group ?? _group;

      // Fresh truth from the server supersedes the optimistic flip.
      // Left in place, a stale override would keep claiming "Joined"
      // through any later reload.
      if (group != null) _joinedOverride = null;
    });

    final results = await Future.wait([
      activityRequest,
      vehiclesRequest,
      spotsRequest,
      eventsRequest,
    ]);

    if (!mounted) return;

    setState(() {
      final latestPage =
          results[0] as ({List<Map<String, dynamic>> items, int total});

      _latest = latestPage.items;
      _latestTotal = latestPage.total;
      _latestPage = 1;
      _latestLoadingMore = false;
      final garagePage =
          results[1] as ({List<GlobalGroupVehicle> items, int total});

      _garages = garagePage.items;
      _garageTotal = garagePage.total;
      _garagePage = 1;
      _garagesLoadingMore = false;
      final spotPage = results[2] as ({List<GlobalGroupSpot> items, int total});

      _spots = spotPage.items;
      _spotTotal = spotPage.total;
      _spotPage = 1;
      _spotsLoadingMore = false;
      _events = results[3] as List<GlobalGroupEvent>;
      _loading = false;

      // Only now, because _failed hides the whole page. A group that
      // loaded fine but whose feed is still in flight is not a failure.
      _failed = _group == null;
    });
  }

  /// Open the composer with this group already attached.
  ///
  /// The composer takes an association as three strings and carries
  /// them through untouched, so a group needed no special case there —
  /// only a type the server knows, which is 'group'.
  ///
  /// Does NOT reload on return. [_checkUploads] does that, when the
  /// upload finishes — which is the only moment the post exists to be
  /// fetched. Awaiting this push and reloading after it looked right and
  /// fired immediately: tapping Post replaces the composer with the
  /// tagging screen, and replacing a route completes the replaced
  /// route's future there and then.
  Future<void> _composeToGroup(GlobalGroup group) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CreatePostScreen(
          associationId: '${group.id}',
          associationType: 'group',
          associationLabel: group.title,
        ),
      ),
    );
  }

  /// Reload when a post finishes uploading.
  ///
  /// This, and not the composer closing, is when the post exists. The
  /// composer pushReplacement()s to the tagging screen, which completes
  /// the awaited push straight away, and the upload itself runs on in
  /// UploadPostProvider after both are gone — so a reload tied to either
  /// of those ran before there was anything new to fetch.
  ///
  /// Delayed, like the home feed's: the upload reports completed when
  /// the last file lands, and the post is not always queryable in the
  /// same instant.
  void _checkUploads(Map<String, UploadPostProgress> uploads) {
    if (!mounted) return;

    final done = uploads.entries
        .where((e) => e.value.status == UploadStatus.completed)
        .map((e) => e.key);

    if (!_uploadsSeeded) {
      _uploadsSeeded = true;
      _seenUploads.addAll(done);
      return;
    }

    final fresh = done.where((id) => !_seenUploads.contains(id)).toList();

    _seenUploads
      ..addAll(fresh)
      ..removeWhere((id) => !uploads.containsKey(id));

    if (fresh.isEmpty || _reloadScheduled) return;

    _reloadScheduled = true;

    Future.delayed(const Duration(milliseconds: 600), () {
      _reloadScheduled = false;
      if (mounted) _load();
    });
  }

  void _notYet(String what) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$what is not built yet.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final group = _group;

    // Watched, so a post finishing anywhere reaches this screen. The
    // check runs after the frame because it can schedule a reload, and
    // setState during build is an error.
    final uploads = context.watch<UploadPostProvider>().uploads;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUploads(uploads);
    });

    if (_failed) {
      return Scaffold(
        backgroundColor: theme.backgroundColor,
        appBar: AppBar(backgroundColor: theme.backgroundColor),
        body: const Center(child: Text('That group could not be loaded.')),
      );
    }

    if (group == null) {
      // The page's own shape, not a spinner in the middle of nothing:
      // the header, the tab bar and a feed are all coming, and laying
      // them out now means nothing jumps when they land.
      return Scaffold(
        backgroundColor: theme.backgroundColor,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
                child: Row(
                  children: [
                    _circleBack(theme),
                    const SizedBox(width: 10),
                    const GroupShimmer(
                      child: Row(
                        children: [
                          GroupBlock(width: 36, height: 36, radius: 8),
                          SizedBox(width: 10),
                          GroupBlock(width: 150, height: 18),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const GroupShimmer(
                      child: GroupBlock(width: 86, height: 42, radius: 21),
                    ),
                  ],
                ),
              ),
              const GroupShimmer(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      GroupBlock(width: 60, height: 16),
                      SizedBox(width: 22),
                      GroupBlock(width: 78, height: 16),
                      SizedBox(width: 22),
                      GroupBlock(width: 62, height: 16),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: theme.dividerColor),
              const Expanded(
                child: SingleChildScrollView(
                  physics: NeverScrollableScrollPhysics(),
                  child: GroupFeedSkeleton(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(theme, group),
            // No Divider after this any more: GroupTabBar carries its
            // own rule top and bottom, and the one that used to sit
            // here would be a second line directly under the first.
            _tabBar(theme, group),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _latestTab(theme, group),
                  _garagesTab(theme),
                  _spotsTab(theme),
                  _eventsTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────

  Widget _header(ThemeProvider theme, GlobalGroup group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
      child: Row(
        children: [
          _circleBack(theme),
          const SizedBox(width: 10),

          _headerLogo(theme, group),

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
                    // 17, matching the club header. 21 competed with
                    // the tab labels directly beneath it, and left
                    // nothing for a long marque name beside the logo
                    // and the Join pill.
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: theme.textColor,
                  ),
                ),

                // Every group is a draft while this is being tested and
                // the endpoint is deliberately serving them. Without
                // this a test build looks exactly like a live one.
                if (group.status != 'published')
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      group.status.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        color: Color(0xFFAE9159),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 10),
          _joinPill(theme, group),
        ],
      ),
    );
  }

  /// The group's mark, between the back button and the name.
  ///
  /// Prefers the logo over the cover: a logo is made to be small and
  /// square, while a cover photo cropped to 36px is usually an
  /// unreadable scrap of bodywork. Falls back to the cover only
  /// because a scrap is still better than a grey square, and to an
  /// icon when there is neither.
  ///
  /// Takes no space at all when the group has no images, rather than
  /// leaving a placeholder gap — most groups have none yet.
  Widget _headerLogo(ThemeProvider theme, GlobalGroup group) {
    final url = (group.logo ?? '').isNotEmpty
        ? group.logo
        : (group.coverImage ?? '');

    if ((url ?? '').isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36,
          child: CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Container(
              color: theme.cardColor,
              child: Icon(
                Icons.groups_outlined,
                size: 19,
                color: theme.subtextColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleBack(ThemeProvider theme) {
    return Material(
      color: theme.cardColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.maybePop(context),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.arrow_back_ios_new,
            size: 17,
            color: theme.textColor,
          ),
        ),
      ),
    );
  }

  /// Join or leave. The one thing on this screen that writes.
  ///
  /// Optimistic, and it puts itself back if the server disagreed —
  /// showing "Joined" for a membership that does not exist would send
  /// somebody away believing they are in a group they are not.
  Widget _joinPill(ThemeProvider theme, GlobalGroup group) {
    final joined = _joinedOverride ?? group.isMember;

    return OutlinedButton(
      onPressed: _joining ? null : () => _toggleJoin(group, joined),
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: theme.dividerColor),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        foregroundColor: theme.textColor,
        backgroundColor: joined ? null : theme.textColor,
        disabledForegroundColor: theme.subtextColor,
      ),
      child: _joining
          ? SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: joined ? theme.textColor : theme.textColorSecondary,
              ),
            )
          : Text(
              joined ? 'Joined' : 'Join',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: joined ? theme.textColor : theme.textColorSecondary,
              ),
            ),
    );
  }

  Future<void> _toggleJoin(GlobalGroup group, bool joined) async {
    // Ask before leaving, never before joining — leaving loses a
    // membership and stops the group being suggested again, while
    // joining is undone by the same button.
    if (joined && !await _confirmLeave(group)) return;

    setState(() {
      // No optimistic flip: the pill shows a spinner and changes only
      // when the server has agreed. Flipping first made a slow request
      // look finished, and a failed one look successful.
      _joining = true;
    });

    final ok = joined
        ? await GlobalGroupsApi.leave(group.slug)
        : await GlobalGroupsApi.join(group.slug);

    if (!mounted) return;

    if (!ok) {
      // Nothing to roll back: the pill never claimed the new state.
      setState(() => _joining = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            joined
                ? 'Could not leave ${group.title}.'
                : 'Could not join ${group.title}.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _joining = false;
      _joinedOverride = !joined;
    });

    // Reload: joining puts this person's matching cars into the
    // group's garage, so the Garages tab and its count are both stale
    // the moment the server says yes.
    await _load();
  }

  /// "Leave this group?"
  ///
  /// Names the two consequences that are not obvious from the button:
  /// the member's cars come out of the group's garage, and the group
  /// stops being suggested to them afterwards.
  Future<bool> _confirmLeave(GlobalGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leave ${group.title}?'),
        content: const Text(
          'Your vehicles will be removed from this group, and it will '
          'stop being suggested to you. You can join again at any time.',
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

  // ─── Tabs ──────────────────────────────────────────────────────────

  Widget _tabBar(ThemeProvider theme, GlobalGroup group) {
    return GroupTabBar(
      controller: _tabs,
      theme: theme,
      tabs: [
        // No count on Latest: a number there would be a post count
        // nobody asked for.
        const GroupTab('Latest'),
        GroupTab('Garages', group.garageCount),
        GroupTab('Spots', group.spotCount),
        GroupTab('Events', group.eventCount),
      ],
    );
  }

  // ─── Latest ────────────────────────────────────────────────────────

  /// The next page of the feed.
  ///
  /// The next page of the feed.
  ///
  /// The page number is held in a counter rather than derived from how
  /// much is on screen. Deriving it was the cheaper-looking option and
  /// the reason this tab could load for ever: see [_latestPage].
  ///
  /// A counter can go stale where a derived number cannot, so the one
  /// thing it has to do is reset — [_load] puts it back to 1 along with
  /// the list it counts, so a pull-to-refresh cannot leave it pointing
  /// past the end.
  Future<void> _loadMoreLatest() async {
    if (_latestLoadingMore || !_latestHasMore) return;

    setState(() => _latestLoadingMore = true);

    final next = _latestPage + 1;

    final page = await GlobalGroupsApi.fetchActivity(
      widget.slug,
      page: next,
      perPage: _latestPerPage,
    );

    if (!mounted) return;

    setState(() {
      _latestLoadingMore = false;

      // Recorded whether or not anything came back, so a page that
      // hydrated to nothing is a page we move past rather than one we
      // ask for again.
      _latestPage = next;

      if (page.items.isEmpty) {
        // The total said there was more and there was not - rows
        // removed between two fetches, or a whole page of them that
        // hydrated to nothing. Believe what arrived and stop, rather
        // than asking again on every scroll.
        //
        // Clamped to the pages FETCHED, not to _latest.length: hasMore
        // is now counted in pages, and a card count would not end it.
        _latestTotal = (next - 1) * _latestPerPage;
        return;
      }

      // Guard against a duplicate: the feed is ordered by date, so a post
      // created between two page fetches shifts everything down one and
      // can hand back a row that is already on screen. PostCard is keyed
      // by id and Flutter throws on two widgets with the same key.
      // Keyed by kind AND id. The feed is mixed, and a garage id and a
      // post id are both small integers from different tables — so an id
      // on its own would drop a real vehicle because a post happens to
      // share its number. The same reason the widget keys are prefixed.
      String key(Map<String, dynamic> row) =>
          '${row['group_item_type'] ?? 'post'}-${row['id']}';

      final seen = _latest.map(key).toSet();

      _latest = [
        ..._latest,
        ...page.items.where((row) => !seen.contains(key(row))),
      ];

      if (page.total > 0) _latestTotal = page.total;
    });
  }

  /// One row of the Latest feed, with the divider under it.
  ///
  /// The same hairline the home feed uses, and added here for the same
  /// reason: only the list knows which row is last, and a separator
  /// under the final one is a line with nothing beneath it.
  ///
  /// The air goes UNDER the line rather than around it, because the
  /// cards do not provide it evenly — above is the end of a card, below
  /// is a header that starts almost immediately.
  Widget _latestRow(
    ThemeProvider theme,
    Map<String, dynamic> item,
    bool isLast,
  ) {
    final isActivity = const [
      'vehicle',
      'gallery',
      'garage_photo',
    ].contains(item['group_item_type']);

    // The home feed's card, not a second one.
    //
    // Both feeds draw the same events, so they should draw them the same
    // way — full-bleed photographs, the caption under them, a grid where
    // there is a set of them. The group endpoint now sends the field
    // names this reads, so a change to the card lands in both places
    // rather than in one and being forgotten in the other.
    //
    // It navigates itself, from target_type and target_id, which is why
    // there is no onTap — and why _openActivity has gone. Two places
    // deciding where a gallery card opens is two places to disagree.
    final card = isActivity
        ? HomeActivityCard(
            // Keyed by kind as well as id: a garage id, a gallery id and
            // a post id are all small integers from different tables, so
            // ValueKey(id) alone can collide between them and Flutter
            // throws on a duplicate key.
            key: ValueKey('${item['group_item_type']}-${item['id']}'),
            item: item,
            theme: theme,
          )
        : PostCard(
            key: ValueKey('post-${item['id']}'),
            post: item,
            // The avatar and the username in a post's header both call
            // this, so an empty callback left the whole header dead in
            // this feed — the taps registered and went nowhere.
            onTapProfile: () => Navigator.pushNamed(
              context,
              AppRoutes.viewProfile,
              arguments: {
                'userId': item['user_id'],
                'username': (item['username'] ?? '').toString(),
              },
            ),
            onLikeChanged: (isLiked) {
              setState(() {
                item['is_liked'] = isLiked;
                item['likes_count'] =
                    ((item['likes_count'] as int?) ?? 0) + (isLiked ? 1 : -1);
              });
            },
            onDelete: _load,
          );

    if (isLast) return card;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        card,
        const FeedDivider(),
      ],
    );
  }

  Widget _latestTab(ThemeProvider theme, GlobalGroup group) {
    return RefreshIndicator(
      // Without these it draws Material blue, in an app that is black
      // and gold.
      color: theme.primaryColor,
      backgroundColor: theme.backgroundColor,
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        // Fetches before the bottom is reached, so the next posts are
        // usually already there by the time the scroll gets to them.
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 900) _loadMoreLatest();
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            _composer(theme, group),

            if (_garages.isNotEmpty) _latestGarages(theme),

            if (_loading && _latest.isEmpty)
              const GroupFeedSkeleton()
            else if (_latest.isEmpty)
              GroupEmptyNote(
                theme: theme,
                title: 'No activity yet',
                body: 'Check back soon for new content.',
              )
            else
              // The same widget a club feed uses. A group post and a club
              // post are the same thing presented the same way, and the
              // hand-rolled card this replaces had no caption, no
              // carousel, no comments and no like button — just a
              // picture that opened the post.
              // The feed is mixed: ce_group_activity indexes posts, spots
              // AND vehicles, and a vehicle has no caption, no comments and
              // nothing to like. Drawn as a post it would be a card with
              // every one of those parts empty, so it gets its own.
              //
              // Branching on group_item_type, which the endpoint stamps on
              // every row from the index.
              for (final entry in _latest.asMap().entries)
                _latestRow(
                  theme,
                  entry.value,
                  // The last row only when there is nothing more coming;
                  // otherwise the loading indicator follows it and the
                  // line belongs.
                  entry.key == _latest.length - 1 && !_latestHasMore,
                ),

            if (_latestHasMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: GroupFeedSkeleton(count: 1),
              ),
          ],
        ),
      ),
    );
  }

  /// The composer row. Live.
  Widget _composer(ThemeProvider theme, GlobalGroup group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
        decoration: BoxDecoration(
          // A grey you can actually see. theme.cardColor is all but
          // white against a white feed, so the box had no edges and
          // the row read as loose text with a button after it rather
          // than as something to tap.
          color: const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            // The signed-in user's own photo, like the club composer —
            // it is their post being invited, so it should be their
            // face. listen: false because the avatar does not change
            // while this row is on screen, and rebuilding the whole
            // feed when the provider ticks would be wasteful.
            GroupAvatar(
              url: Provider.of<UserProvider>(
                context,
                listen: false,
              ).user?.profileImage,
              radius: 19,
              theme: theme,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                'Post to ${group.title}…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15.5, color: theme.subtextColor),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _composeToGroup(group),
              icon: const Icon(Icons.add, size: 19),
              label: const Text('Post'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.textColor,
                foregroundColor: theme.textColorSecondary,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _latestGarages(ThemeProvider theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              Expanded(
                // The same heading the home page uses for Upcoming
                // events and Get involved — this was a 15pt uppercase
                // Text, which read as a label on the rail rather than
                // as a section of the page.
                child: DlHeading(
                  'Latest garages',
                  fontSize: 22,
                  color: theme.textColor,
                ),
              ),
              GestureDetector(
                onTap: () => _tabs.animateTo(1),
                child: const Text(
                  'View all',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFAE9159),
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(
          // Taller than the 196 it was. The card is a bordered box now,
          // so the title and the owner's name sit INSIDE it with their
          // own padding rather than floating under a loose photograph —
          // and that padding has to come from somewhere.
          height: 232,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _garages.length > 10 ? 10 : _garages.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: 196,
              child: GroupGarageCard(
                vehicle: _garages[i],
                theme: theme,
                compact: true,
                onTap: () => _openVehicle(_garages[i].id),
              ),
            ),
          ),
        ),

        const SizedBox(height: 18),
        Divider(height: 1, color: theme.dividerColor),
      ],
    );
  }

  // ─── Garages ───────────────────────────────────────────────────────

  /// The next page of the garage.
  ///
  /// Page number comes from what is already loaded rather than a counter,
  /// so a refresh that resets the list cannot leave a stale page index
  /// behind and skip a page.
  Future<void> _loadMoreGarages() async {
    if (_garagesLoadingMore || !_garagesHasMore) return;

    setState(() => _garagesLoadingMore = true);

    final next = _garagePage + 1;

    final page = await GlobalGroupsApi.fetchVehicles(
      widget.slug,
      page: next,
      perPage: _garagesPerPage,
    );

    if (!mounted) return;

    setState(() {
      _garagesLoadingMore = false;
      _garagePage = next;

      if (page.items.isEmpty) {
        // Nothing came back when the total said there should be. Trust
        // what arrived over what was promised, rather than asking again
        // on every scroll for the rest of the session.
        _garageTotal = (next - 1) * _garagesPerPage;
        return;
      }

      _garages = [..._garages, ...page.items];

      // The total can move between pages — somebody joins, somebody
      // leaves — so it is taken from the newest answer.
      if (page.total > 0) _garageTotal = page.total;
    });
  }

  Widget _garagesTab(ThemeProvider theme) {
    if (_loading && _garages.isEmpty) {
      return const SingleChildScrollView(child: GroupGarageGridSkeleton());
    }

    if (_garages.isEmpty) {
      return ListView(
        // Explicit: a ListView with padding: null adopts
        // MediaQuery.padding, drawing the status-bar inset as a blank
        // band under the header.
        padding: EdgeInsets.zero,
        children: [
          GroupEmptyNote(
            theme: theme,
            title: 'No Vehicles matched yet',
            body: 'Check back soon for new content.',
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: theme.primaryColor,
      backgroundColor: theme.backgroundColor,
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        // Fetches a page ahead of the bottom, so the next cards are
        // usually there before the scroll reaches where they go.
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 600) _loadMoreGarages();
          return false;
        },
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          // One extra row's worth of slots for the footer, which is
          // either a spinner or the "that is all" line.
          itemCount: _garages.length + (_garagesHasMore ? 2 : 0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (_, i) {
            // The footer slots. One shimmering tile each, not
            // GroupGarageGridSkeleton — that is itself a GridView and
            // would nest one inside a cell of this one.
            if (i >= _garages.length) {
              return GroupShimmer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }

            return GroupGarageCard(
              vehicle: _garages[i],
              theme: theme,
              onTap: () => _openVehicle(_garages[i].id),
            );
          },
        ),
      ),
    );
  }

  // ─── Spots ─────────────────────────────────────────────────────────

  /// The next page of spots.
  Future<void> _loadMoreSpots() async {
    if (_spotsLoadingMore || !_spotsHasMore) return;

    setState(() => _spotsLoadingMore = true);

    final next = _spotPage + 1;

    final page = await GlobalGroupsApi.fetchSpots(
      widget.slug,
      page: next,
      perPage: _spotsPerPage,
    );

    if (!mounted) return;

    setState(() {
      _spotsLoadingMore = false;
      _spotPage = next;

      if (page.items.isEmpty) {
        _spotTotal = (next - 1) * _spotsPerPage;
        return;
      }

      final seen = _spots.map((spot) => spot.postId).toSet();

      _spots = [
        ..._spots,
        ...page.items.where((spot) => !seen.contains(spot.postId)),
      ];

      if (page.total > 0) _spotTotal = page.total;
    });
  }

  Widget _spotsTab(ThemeProvider theme) {
    if (_loading && _spots.isEmpty) {
      return const SingleChildScrollView(child: GroupSpotGridSkeleton());
    }

    if (_spots.isEmpty) {
      return ListView(
        // Explicit: a ListView with padding: null adopts
        // MediaQuery.padding, drawing the status-bar inset as a blank
        // band under the header.
        padding: EdgeInsets.zero,
        children: [
          GroupEmptyNote(
            theme: theme,
            title: 'No Spots yet',
            body: 'Check back soon for new content.',
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: theme.primaryColor,
      backgroundColor: theme.backgroundColor,
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 600) _loadMoreSpots();
          return false;
        },
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
          // A row of placeholders while the next page is on its way.
          itemCount: _spots.length + (_spotsHasMore ? 3 : 0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemBuilder: (_, i) {
            if (i >= _spots.length) {
              return GroupShimmer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              );
            }

            return GroupSpotTile(
              spot: _spots[i],
              theme: theme,
              onTap: () => _openPost(_spots[i].postId),
            );
          },
        ),
      ),
    );
  }

  // ─── Events ────────────────────────────────────────────────────────

  Widget _eventsTab(ThemeProvider theme) {
    if (_events.isEmpty) {
      return ListView(
        // Explicit: a ListView with padding: null adopts
        // MediaQuery.padding, drawing the status-bar inset as a blank
        // band under the header.
        padding: EdgeInsets.zero,
        children: [
          GroupEmptyNote(
            theme: theme,
            title: 'No Events yet',
            body: 'Check back soon for new content.',
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: _events.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: theme.dividerColor, indent: 76),
      itemBuilder: (_, i) => _eventRow(theme, _events[i]),
    );
  }

  Widget _eventRow(ThemeProvider theme, GlobalGroupEvent event) {
    final date = event.startsAt;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              date == null ? '' : _month(date).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: theme.subtextColor,
              ),
            ),
            Text(
              date == null ? '?' : '${date.day}',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: theme.textColor,
              ),
            ),
          ],
        ),
      ),
      title: Text(
        event.title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: theme.textColor,
        ),
      ),
      subtitle: (event.location ?? '').isEmpty
          ? null
          : Text(
              event.location!,
              style: TextStyle(fontSize: 14, color: theme.subtextColor),
            ),
      trailing: Icon(Icons.chevron_right, color: theme.subtextColor),
      onTap: () => _notYet('Group events'),
    );
  }

  // ─── Shared bits ───────────────────────────────────────────────────

  void _openPost(int postId) {
    if (postId <= 0) return;

    Navigator.pushNamed(
      context,
      AppRoutes.postDetail,
      arguments: {'postId': postId},
    );
  }

  void _openVehicle(int garageId) {
    if (garageId <= 0) return;

    Navigator.pushNamed(
      context,
      AppRoutes.vehicleDetail,
      // A STRING. The route passes garageId straight through to
      // VehicleDetailScreen without coercing it, unlike postDetail
      // which calls toString() — and every existing caller sends a
      // string, so an int here would be a type error at the far end.
      arguments: {'garageId': '$garageId'},
    );
  }

  String _month(DateTime when) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return months[when.month - 1];
  }
}
