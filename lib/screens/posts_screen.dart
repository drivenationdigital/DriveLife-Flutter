import 'package:drivelife/main.dart' show BottomNavProvider;
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/api/activity_feed_api.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:drivelife/widgets/home/home_activity_card.dart';
import 'package:drivelife/widgets/nav/dl_bottom_nav.dart';
import 'package:drivelife/widgets/home/your_week.dart';
import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:drivelife/api/offers_api_service.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/search_screen.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/widgets/feed/offers_banner.dart';
import 'package:drivelife/widgets/upload_progress_card.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/widgets/nav/dl_haptics.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../api/posts_api.dart';
import '../services/auth_service.dart';
import '../components/post_card.dart';

class PostsScreen extends StatefulWidget {
  /// Told which way the feed is scrolling, so the shell can slide its
  /// bottom bar out of the way. Null when nothing is listening.
  ///
  /// Only the bottom bar uses this now. The top chrome is a sliver inside
  /// this screen's own scroll view — see [header] — which is what stopped it
  /// resizing the viewport mid-gesture.
  final ChromeVisibility? chrome;

  /// The shell's header and section tabs, rendered inside the feed.
  ///
  /// Given to this screen rather than stacked above it so the SCROLL moves
  /// it, not an animation. A collapsing widget above the feed changed the
  /// viewport's height on every frame, and a viewport that resizes during a
  /// drag has to keep correcting its own offset — which is what the heavy,
  /// stuttering feel at the top of the feed was.
  ///
  /// Null when the shell is drawing it itself, which it does for every
  /// destination that is not this one.
  final Widget? header;

  /// How tall [header] is. A sliver header has to declare its extent before
  /// layout, so this cannot be measured.
  final double headerHeight;

  const PostsScreen({
    super.key,
    this.chrome,
    this.header,
    this.headerHeight = 0,
  });

  @override
  State<PostsScreen> createState() => PostsScreenState();
}

class PostsScreenState extends State<PostsScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late TabController _tabController;

  // NEW: shared visibility flag for the pills row. Tabs flip it on scroll;
  // the parent rebuilds only the pills wrapper via ValueListenableBuilder.

  /// The feeds on offer, in the order they appear.
  ///
  /// Your week used to lead this list as a tab of its own. It is not a
  /// feed — it is the standing summary — and making it a tab put the
  /// thing a reader wants first behind a pill they had to notice. It is
  /// now the head of Latest, so the selector is the two feeds it always
  /// described.
  ///
  /// The selector, the TabController's length and the slivers below all
  /// read this, so none of them can disagree about how many tabs there
  /// are — which is the usual way a hidden tab turns into a crash.
  static const List<PostTabType> _visibleTabs = [
    PostTabType.latest,
    PostTabType.following,
  ];

  /// The feed's scroll, now that there is only one of them.
  ///
  /// It used to be one per tab, inside three separate scroll views. The
  /// header, the hot row and the feed selector were duplicated into each of
  /// those, so switching tab replaced all of it — the whole panel changed
  /// when only the posts should have.
  final ScrollController _scroll = ScrollController();

  /// Your week is a panel, not a feed, so it has its own key type. It is
  /// never a _PostsTab, which is why _keyFor still answers for it but
  /// _activeTab resolves to null while it is showing — nothing on this
  /// screen should try to page or fetch posts for it.
  final GlobalKey<YourWeekPanelState> _yourWeekPanelKey =
      GlobalKey<YourWeekPanelState>();

  final GlobalKey<_PostsTabState> _latestKey = GlobalKey<_PostsTabState>();
  final GlobalKey<_PostsTabState> _followingKey = GlobalKey<_PostsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _visibleTabs.length, vsync: this);
    attachTabHaptics(_tabController);
    // Swapping which feed is on show is this widget's job now that they
    // share one scroll view, so it has to rebuild when the index changes.
    _tabController.addListener(_onTabChanged);
  }

  /// Which feeds have been opened at least once.
  ///
  /// Slivers in one scroll view are all built, where a TabBarView built its
  /// pages lazily — so without this, opening the feed would fire a request
  /// for every tab at once, including ones the user may never look at. A
  /// feed joins the set when it is first selected and stays, which is what
  /// makes coming back to it free.
  late final Set<PostTabType> _opened = {_visibleTabs.first};

  void _onTabChanged() {
    if (!mounted) return;
    setState(() => _opened.add(_visibleTabs[_tabController.index]));
  }

  /// The feed currently on show.
  _PostsTabState? get _activeTab => _getCurrentTabKey().currentState;

  /// Takes the feed back to the top and reloads it.
  ///
  /// The scroll belongs to this screen now and the posts belong to the tab,
  /// so this does the first half and hands over the second.
  Future<void> scrollToTopAndRefresh() async {
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    await refreshActive();
  }

  /// Reload whichever tab is showing.
  ///
  /// Latest is now TWO things in one scroll view — the summary panel and
  /// the feed below it — and a pull on it has to reload both. Together,
  /// so the spinner lasts as long as the slower of them rather than
  /// vanishing when the first finishes.
  ///
  /// Both callers go through here, so there is no second place to forget
  /// that the panel is not part of the feed.
  Future<void> refreshActive() async {
    final showing = _visibleTabs[_tabController.index];

    await Future.wait([
      if (showing == PostTabType.latest)
        Future.value(_yourWeekPanelKey.currentState?.refresh()),
      Future.value(_activeTab?.refresh()),
    ]);
  }

  /// The summary panel, with whatever it needs about the signed-in user.
  ///
  /// Read from UserProvider rather than passed down: this screen is built
  /// by the shell before the profile has necessarily loaded, and the
  /// provider is the thing that rebuilds when it does.
  Widget _yourWeekSliver() {
    final user = context.watch<UserProvider>().user;

    if (user == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return YourWeekPanel(
      key: _yourWeekPanelKey,
      userId: user.id,
      // The greeting is a hello, not a formal address — "Hey, Mark",
      // never "Hey, Mark Jenkins".
      firstName: user.firstName,
      // The events endpoint returns coordinates but no distance, so the
      // panel works it out from here.
      from: user.lastLocation,
      // 1 is Events in _homeTabs. Going through the provider rather than
      // reaching for the shell is what lets anything in the app send the
      // user to a section by name.
      onSeeAllEvents: () =>
          context.read<BottomNavProvider>().openHomeSection(1),
    );
  }

  GlobalKey<_PostsTabState> _keyFor(PostTabType type) => switch (type) {
    PostTabType.latest => _latestKey,
    PostTabType.following => _followingKey,
  };

  GlobalKey<_PostsTabState> _getCurrentTabKey() {
    final index = _tabController.index.clamp(0, _visibleTabs.length - 1);
    return _keyFor(_visibleTabs[index]);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      // One listener for all three feeds: their notifications bubble up
      // through here, so the shell is told about whichever is showing
      // without each tab having to know the shell exists.
      body: NotificationListener<ScrollNotification>(
        onNotification: widget.chrome?.handle ?? (_) => false,
        child: _buildFeed(theme),
      ),
    );
  }

  Widget _buildFeed(ThemeProvider theme) {
    // One scroll view for all three feeds, not a TabBarView of three.
    //
    // Each tab used to carry its own copy of the header, the hot row and the
    // selector inside its own CustomScrollView, so switching feed slid the
    // entire page sideways and replaced every part of it. Only the posts
    // should change.
    //
    // So those three live here, once, and each feed contributes nothing but
    // its own posts. The feed that is not showing stays in the tree —
    // SliverOffstage does not lay it out, but its element is still mounted,
    // so its loaded posts and its paging survive a switch and coming back
    // costs nothing.
    //
    // Not a NestedScrollView, which is the usual way to share a header: its
    // coordinator asserts in _getMetrics when the viewport changes size
    // underneath it, and that is what crashed the earlier version of this
    // screen.
    final active =
        _visibleTabs[_tabController.index.clamp(0, _visibleTabs.length - 1)];

    return RefreshIndicator(
      color: theme.primaryColor,
      backgroundColor: theme.backgroundColor,
      // Awaited, not fired. `() async => f()` completes as soon as the
      // call is made, so the spinner vanished a frame after it appeared
      // rather than when the posts arrived.
      onRefresh: refreshActive,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // Vertical only: a carousel inside a post card would otherwise
          // page the feed sideways into loading more.
          if (notification.metrics.axis == Axis.vertical) {
            _activeTab?.onScroll(notification.metrics);
          }
          return false;
        },
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          // 600, down from 2000.
          //
          // cacheExtent is how far BEYOND the viewport children are
          // built, so 2000 was around two and a half extra screens of
          // PostCards — each allocating an AnimationController with its
          // own ticker in initState and decoding images at up to 1400px
          // wide, roughly 6MB of bitmap apiece. A hard fling asks for all
          // of it at once, and an app that stops answering gets signal 3
          // and a tombstone rather than a crash log.
          //
          // 600 still keeps most of a screen ready ahead of the scroll,
          // which is what the big number was reaching for.
          cacheExtent: 600,
          slivers: [
            // Floating, not pinned: it leaves as you read on and comes back
            // the moment you scroll up, without having to reach the top.
            //
            // Being a sliver is the whole point. The scroll moves it, so
            // there is no animation to run and no layout above the feed to
            // change — the viewport keeps exactly one size for the life of
            // the gesture.
            if (widget.header != null && widget.headerHeight > 0)
              SliverPersistentHeader(
                floating: true,
                delegate: FloatingChromeHeader(
                  height: widget.headerHeight,
                  vsync: this,
                  child: widget.header!,
                ),
              ),

            // Hidden, not deleted. The row of Find Events / Popular
            // Venues / Discover Groups / Your Garage cards was a
            // standing recommendation built on placeholder data, and
            // Your week now does the same job with real data.
            //
            // widgets/feed/hot_right_now.dart is untouched. To restore
            // it, import HotRightNow and put this line back:
            //
            //   const SliverToBoxAdapter(child: HotRightNow()),

            // Pins. This one IS navigation — losing it mid-feed would mean
            // scrolling back to the top to change feed.
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedSelector(
                child: _CustomTabBar(
                  controller: _tabController,
                  theme: theme,
                  tabs: _visibleTabs,
                ),
              ),
            ),

            for (final type in _visibleTabs)
              if (_opened.contains(type))
                SliverOffstage(
                  offstage: type != active,
                  // Your week heads Latest and nothing else. One
                  // group, so the panel scrolls away with the feed
                  // under it rather than sitting above as a second
                  // fixed thing to get past.
                  sliver: type == PostTabType.latest
                      ? SliverMainAxisGroup(
                          slivers: [
                            _yourWeekSliver(),
                            _PostsTab(key: _keyFor(type), tabType: type),
                          ],
                        )
                      : _PostsTab(key: _keyFor(type), tabType: type),
                ),
          ],
        ),
      ),
    );
  }
}

/// The two feeds.
///
/// [latest] is everything, newest first, with the network's activity
/// merged in and the Your week summary at its head. [following] is posts
/// from people the viewer chose, and nothing else — no activity, no
/// summary.
///
/// There was a third, [yourWeek], which was not a feed at all. It is now
/// part of Latest.
enum PostTabType { latest, following }

/// One feed's worth of posts, as slivers.
///
/// Builds a sliver, not a box: it is placed directly into the screen's shared
/// CustomScrollView, below the header and selector that all three feeds have
/// in common. It owns its posts, its paging and its refresh, and nothing
/// about the scroll — that belongs to the screen, because all three share it.
class _PostsTab extends StatefulWidget {
  final PostTabType tabType;

  const _PostsTab({super.key, required this.tabType});

  @override
  State<_PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<_PostsTab> {
  final AuthService _auth = AuthService();

  /// Which tab carries the offers banner and the "Hot right now" row.
  ///
  /// Named because it gates both the render and the fetch — move it and the
  /// other tabs stop making a request whose result they would never show.
  static const PostTabType _offersTab = PostTabType.latest;

  int? _currentUserId;

  List<dynamic> _posts = [];
  List<EventOffer> _offers = [];
  int _page = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isInitialized = false;

  /// How many pages the mixed feed says there are.
  ///
  /// Latest can no longer tell whether it has reached the end by counting
  /// what arrived: a page holds [_limit] POSTS plus however much activity
  /// fell in the same date range, so `length >= limit` is true on the
  /// last page as readily as the first and the feed would never stop
  /// asking.
  int _totalPages = 0;

  /// Where this page ended, to be sent back as the next page's cursor.
  ///
  /// The posts half of the feed pages by offset; the activity half pages
  /// by date, because a page's date RANGE leaves gaps between adjacent
  /// posts that no page would ever claim. The server works this out and
  /// hands it back rather than having the app derive it, so the two
  /// cannot disagree about where the page ended.
  String? _nextBefore;

  /// Posts per page. The mixed feed returns more rows than this.
  static const int _limit = 10;

  /// Whether this feed carries activity cards as well as posts.
  ///
  /// Latest only. Following is posts from people the viewer chose and
  /// should stay exactly that.
  bool get _isMixed => widget.tabType == PostTabType.latest;

  Timer? _scrollDebounce;

  /// Where the scroll was when we last heard about it.
  ///
  /// Read when the trigger fires rather than captured into the timer's
  /// closure: a snapshot taken at scheduling time is already up to the
  /// debounce stale, and on a retry it would be staler again.
  double _lastPixels = 0;
  double _lastExtent = 0;

  /// Every row already in [_posts], by the same key the widgets use.
  ///
  /// The posts half of the feed pages by offset, so a post created
  /// between two fetches shifts the window and comes back on the next
  /// page as well. Without this the feed shows it twice and two widgets
  /// claim one key.
  final Set<String> _seenKeys = {};

  // FIX: Track completed uploads to avoid double-refresh on same upload ID
  final Set<String> _completedUploads = {};
  // FIX: Guard so multiple simultaneous completions only trigger one refresh
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    // The scroll controller is attached in didChangeDependencies: it comes
    // from context and is not available this early.

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final accountManager = Provider.of<AccountManager>(
        context,
        listen: false,
      );
      _currentUserId = accountManager.activeUser?.id;
      _fetchPosts();
      if (widget.tabType == _offersTab) _fetchOffers();
    });
  }

  /// Loads the next page as the bottom comes into view.
  ///
  /// Driven by the scroll notification rather than by the controller. Each
  /// tab now has a controller of its own, so either would work — but the
  /// notification carries the metrics of the list that actually moved, which
  /// keeps this correct if these feeds are ever nested or shared again.
  /// Loads the next page as the end of the list comes into view.
  ///
  /// Called by the screen, which owns the only scroll view, and only for the
  /// feed currently on show — an offstage feed has no metrics worth acting on
  /// and would page itself on someone else's scrolling.
  void onScroll(ScrollMetrics metrics) {
    if (!mounted) return;

    _lastPixels = metrics.pixels;
    _lastExtent = metrics.maxScrollExtent;

    if (_scrollDebounce?.isActive ?? false) _scrollDebounce!.cancel();

    _scrollDebounce = Timer(const Duration(milliseconds: 200), _maybeLoadMore);
  }

  /// Load the next page if the end is in sight.
  ///
  /// RETRIES while a fetch is in flight rather than giving up. The old
  /// version checked `!_isLoading` and dropped the request if it was
  /// busy — but the debounce only fires once scrolling has stopped, so
  /// there was no second notification coming to schedule another
  /// attempt. One unlucky overlap and the feed stopped paging until the
  /// reader scrolled again.
  ///
  /// Chaining is bounded by the conditions, not by a counter: once a page
  /// lands, maxScrollExtent grows and the end is no longer within reach,
  /// and _hasMore ends it at the bottom of the feed. A reader parked at
  /// the end does keep pulling pages, which is what an endless feed is
  /// for.
  void _maybeLoadMore() {
    if (!mounted) return;

    // Before the first layout there is nothing to be near the end of.
    if (_lastExtent <= 0) return;

    if (_lastPixels < _lastExtent - 500 || !_hasMore) return;

    if (_isLoading) {
      _scrollDebounce = Timer(
        const Duration(milliseconds: 250),
        _maybeLoadMore,
      );
      return;
    }

    _fetchPosts();
  }

  /// A row's identity, matching the key its widget is given.
  ///
  /// Null ids are NOT de-duplicated. Two rows that cannot be told apart
  /// are better shown twice than silently collapsed into one, and an id
  /// is the only thing here that identifies anything.
  String? _rowKey(dynamic row) {
    if (row is! Map) return null;

    final id = row['id'];

    if (id == null || id.toString().isEmpty) return null;

    return '${row['feed_kind'] ?? 'post'}-$id';
  }

  /// What is new in a page, in order.
  List<dynamic> _fresh(List<dynamic> rows) {
    final out = <dynamic>[];

    for (final row in rows) {
      final key = _rowKey(row);

      if (key != null) {
        if (_seenKeys.contains(key)) continue;
        _seenKeys.add(key);
      }

      out.add(row);
    }

    return out;
  }

  /// Reloads this feed from the first page. The screen scrolls; this fetches.
  Future<void> refresh() => _fetchPosts(refresh: true);

  Future<void> _fetchPosts({bool refresh = false}) async {
    if (!mounted || _isLoading) return;

    setState(() => _isLoading = true);

    final accountManager = Provider.of<AccountManager>(context, listen: false);
    final user = accountManager.activeUser;
    final token = await _auth.getToken();

    if (user == null || token == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (refresh) {
      _page = 1;
      _hasMore = true;
      _nextBefore = null;
      _totalPages = 0;
      _seenKeys.clear();
      if (widget.tabType == _offersTab) _fetchOffers();
    }

    int followingOnly;
    int forYou;

    switch (widget.tabType) {
      case PostTabType.following:
        followingOnly = 1;
        forYou = 0;
        break;
      // The curated for_you=1 fetch that used to live here went with
      // the Featured tab. The backend parameter still exists if that
      // feed is ever wanted back.
      default:
        followingOnly = 0;
        forYou = 0;
    }

    try {
      if (_isMixed) {
        final page = await PostsAPI.getHomeFeed(
          token: token,
          userId: user.id,
          page: _page,
          limit: _limit,
          before: _nextBefore,
        );

        if (!mounted) return;

        final fresh = _fresh(page.items);

        setState(() {
          if (refresh) {
            _posts = fresh;
          } else {
            _posts.addAll(fresh);
          }

          _page++;
          _totalPages = page.totalPages;
          _nextBefore = page.nextBefore;

          // In pages, not in rows. An empty page ends it too: the
          // total can be stale by a page if something was deleted
          // between two fetches, and a feed that keeps asking for a
          // page that comes back empty is the skeleton that loads for
          // ever.
          _hasMore = page.items.isNotEmpty && _page <= _totalPages;
          _isLoading = false;
          _isInitialized = true;
        });

        return;
      }

      final newPosts = await PostsAPI.getPosts(
        token: token,
        userId: user.id,
        page: _page,
        limit: _limit,
        followingOnly: followingOnly,
        forYou: forYou,
      );

      if (!mounted) return;

      final fresh = _fresh(newPosts);

      setState(() {
        if (refresh) {
          _posts = fresh;
        } else {
          _posts.addAll(fresh);
        }
        _page++;
        // On what ARRIVED, not on what was new. A page entirely of rows
        // already on screen still means the server had a page to give,
        // so there is probably another behind it — judging by `fresh`
        // would end the feed on the first repeat.
        _hasMore = newPosts.length >= _limit;
        _isLoading = false;
        _isInitialized = true;
      });
    } catch (e) {
      // FIX: debugPrint is stripped in release builds; print is not
      debugPrint('Error fetching posts for ${widget.tabType}: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialized = true;
        });
      }
    }
  }

  Future<void> _fetchOffers() async {
    final result = await OffersApi.getPossibleEventOffers();

    if (!mounted) return;

    setState(() {
      _offers = result?.hasError ?? true ? [] : result?.offers ?? [];
    });
  }

  // FIX: No longer called from build — called via a Consumer listener callback.
  // Uses _refreshScheduled to coalesce multiple simultaneous completions into
  // a single refresh instead of firing once per completed upload.
  void _checkUploadCompletions(Map<String, UploadPostProgress> uploads) {
    if (!mounted) return;

    bool needsRefresh = false;

    for (final entry in uploads.entries) {
      if (entry.value.status == UploadStatus.completed &&
          !_completedUploads.contains(entry.key)) {
        _completedUploads.add(entry.key);
        needsRefresh = true;
      }
    }

    _completedUploads.removeWhere((id) => !uploads.containsKey(id));

    if (needsRefresh && !_refreshScheduled) {
      _refreshScheduled = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        _refreshScheduled = false;
        if (mounted) _fetchPosts(refresh: true);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final accountManager = Provider.of<AccountManager>(context, listen: false);
    final newUserId = accountManager.activeUser?.id;

    // FIX: Only re-fetch when the user ID actually changes, not on every
    // dependency rebuild. Guard also avoids running before first fetch.
    if (_isInitialized && newUserId != null && newUserId != _currentUserId) {
      _currentUserId = newUserId;
      _fetchPosts(refresh: true);
    }
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    // A group, so that several slivers can be handed to the screen's scroll
    // view as one — and so the whole feed can be taken offstage together
    // when another one is selected.
    return SliverMainAxisGroup(
      slivers: [
        // SliverToBoxAdapter(child: StoriesRow()),
        // Offers and "Hot right now" both head up Latest, the landing tab.
        // Following and Featured stay pure feeds.
        // Tiles are still hard-coded — see HotRightNow for the TODO.
        // HotRightNow has moved to the shell's header, above the feed
        // selector — it belongs to the screen now, not to this one tab.
        // The offers banner stays: it is part of the Latest feed and the
        // other two tabs have never shown it.
        if (widget.tabType == _offersTab)
          SliverToBoxAdapter(child: OffersBanner(offers: _offers)),
        Consumer<UploadPostProvider>(
          builder: (context, uploadProvider, _) {
            final uploads = uploadProvider.uploads;

            // FIX: Side effects moved OUT of build. Use post-frame callback
            // so we never mutate state or schedule work during paint.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _checkUploadCompletions(uploads);
            });

            if (uploads.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            return SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  ...uploads.entries.map(
                    (entry) => UploadProgressCard(
                      key: ValueKey(entry.key),
                      uploadId: entry.key,
                      progress: entry.value,
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        // Empty state
        if (_posts.isEmpty && !_isLoading && _isInitialized)
          SliverFillRemaining(
            child: Center(
              child: Text(
                _getEmptyMessage(),
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          )
        // Initial loading state
        else if (_posts.isEmpty && _isLoading)
          SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                color: theme.primaryColor,
                strokeWidth: 2.5,
              ),
            ),
          )
        // Posts list
        else ...[
          // The mockup's ACTIVITY heading, where the summary above ends
          // and the feed begins.
          //
          // Latest only. It marks the seam between Your week — which is
          // about you — and everything that has happened since, and
          // Following has no summary above it to be a seam from.
          //
          // Inside the else, so it is not left hanging over an empty
          // feed or a spinner.
          if (_isMixed)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: DlHeading(
                  'Activity',
                  fontSize: 22,
                  color: theme.textColor,
                ),
              ),
            ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == _posts.length) {
                  if (!_hasMore) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: theme.primaryColor,
                        strokeWidth: 2.5,
                      ),
                    ),
                  );
                }

                final post = _posts[index];

                // The grey band between items, Facebook-style.
                //
                // Wrapped around the card here rather than built into
                // each one, because a card does not know whether it is
                // the last in the list — and a separator under the final
                // item is a line with nothing beneath it.
                Widget separated(Widget card) {
                  final isLast = index == _posts.length - 1 && !_hasMore;

                  if (isLast) return card;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      card,
                      // A hairline, not a band. 8px of grey separated
                      // the cards and also cut the feed into strips;
                      // one pixel is enough to say "this ended, that
                      // began" and disappears once you are reading.
                      //
                      // The cards already carry their own bottom
                      // padding, so the line has air around it without
                      // needing to be thick itself.
                      const SizedBox(
                        height: 1,
                        width: double.infinity,
                        child: ColoredBox(color: Color(0xFFECECEC)),
                      ),

                      // Air UNDER the line, because the cards do not
                      // provide it evenly. What sits above the line is
                      // the end of a card — a PostCard's likes and
                      // comments block, with its own generous bottom
                      // padding. What sits below is the start of the
                      // next one, and PostCard's header is a ListTile
                      // that begins almost immediately.
                      //
                      // So the line looked tucked under the card
                      // beneath it. This is added by the list rather
                      // than by either card, so the gap is the same
                      // whichever kinds happen to meet here.
                      const SizedBox(height: 10),
                    ],
                  );
                }

                // An activity, not a post. Drawn as its own card: a car
                // going into a garage has no caption, no likes and no
                // comments, so a PostCard would be mostly empty boxes.
                if (post is Map && post['feed_kind'] == 'activity') {
                  return separated(
                    HomeActivityCard(
                      // Prefixed. An activity id and a post id are both
                      // small integers from different tables, and two
                      // widgets with the same key is a crash, not a
                      // glitch.
                      key: ValueKey('activity-${post['id']}'),
                      item: Map<String, dynamic>.from(post),
                      theme: theme,
                      // Teaches the interest profile. The card only draws
                      // the buttons on a RECOMMENDATION — something from
                      // somebody the reader already chose to follow is not
                      // a guess that needs correcting — so passing this
                      // unconditionally is what makes them appear on the
                      // half of the feed that is guessing.
                      //
                      // Fire and forget. A dropped rating is worth less
                      // than a spinner on a feed card, and the card has
                      // already said "More like this" by the time this
                      // returns.
                      onRespond: (activityId, response) {
                        ActivityFeedApi.respond(
                          activityId: activityId,
                          response: response,
                        );
                      },
                    ),
                  );
                }

                return separated(
                  PostCard(
                    key: ValueKey('post-${post['id']}'),
                    post: post,
                    onTapProfile: () {
                      if (!mounted) return;
                      if (post['is_event'] == true) return;
                      Navigator.pushNamed(
                        context,
                        '/view-profile',
                        arguments: {
                          'userId': post['user_id'],
                          'username': post['username'],
                        },
                      );
                    },
                    onLikeChanged: (isLiked) {
                      setState(() {
                        post['is_liked'] = isLiked;

                        // Parsed, not cast. `as int` threw on any endpoint
                        // that sent the count as a string or a double, and
                        // which endpoint filled a given post decided
                        // whether liking it crashed.
                        final current = switch (post['likes_count']) {
                          final int v => v,
                          final num v => v.toInt(),
                          final String v => int.tryParse(v.trim()) ?? 0,
                          _ => 0,
                        };

                        post['likes_count'] = (current + (isLiked ? 1 : -1))
                            .clamp(0, 9999999);
                      });
                    },
                    onDelete: refresh,
                  ),
                );
              },
              childCount: _posts.length + (_hasMore ? 1 : 0),
              // FIX: Let the framework manage RepaintBoundaries — removing
              // manual RepaintBoundary wrappers and enabling the delegate flag
              // is more efficient (avoids double boundaries)
              addAutomaticKeepAlives: true,
              addRepaintBoundaries: true,
              addSemanticIndexes: false,
            ),
          ),
        ],

        // Room for the floating bottom bar, which sits OVER this feed.
        //
        // At the end of the scroll, which is the only place it makes
        // sense: it used to live at the foot of the Your week panel,
        // from when that was a tab and was therefore the end of its own
        // scroll view. Now Your week heads this feed, so that padding
        // was a gap in the middle of the page and the last post still
        // ended up under the bar.
        //
        // Measured off DlBottomNav rather than typed by eye — its own
        // documentation notes that nothing outside it reads `height`,
        // which is why a taller bar would quietly cover things.
        SliverToBoxAdapter(
          child: SizedBox(
            height:
                DlBottomNav.height + 24 + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
  }

  String _getEmptyMessage() {
    switch (widget.tabType) {
      case PostTabType.following:
        return 'No posts from people you follow';
      default:
        return 'No posts yet';
    }
  }
}

// =====================================================================
// Pill-style feed selector (Latest / Following / Featured)
// =====================================================================
class _CustomTabBar extends StatelessWidget {
  final TabController controller;
  final ThemeProvider theme;

  /// Which feeds to offer, in order. Comes from the screen so the pills and
  /// the TabBarView cannot disagree about how many there are.
  final List<PostTabType> tabs;

  const _CustomTabBar({
    required this.controller,
    required this.theme,
    required this.tabs,
  });

  /// "Featured" is the curated tab — same feed as the old "For You", renamed.
  /// Order must match the TabBarView children in [PostsScreenState.build].
  /// What each feed is called on the pill.
  ///
  /// "Featured" is the curated tab — the same feed as the old "For You",
  /// renamed. It keeps its label even while hidden, so bringing the tab back
  /// needs no change here.
  static const Map<PostTabType, String> _labels = {
    PostTabType.latest: 'Latest',
    PostTabType.following: 'Following',
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 9),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _buildTab(i, _labels[tabs[i]] ?? '')),
              ],
              const SizedBox(width: 10),
              _searchButton(context),
            ],
          ),
        );
      },
    );
  }

  /// Search, moved off the bottom bar.
  ///
  /// A circle rather than a fourth pill: it is not one of the feeds, and
  /// giving it an Expanded share would make the three that ARE feeds
  /// narrower to accommodate something that is not. Fixed width, so the
  /// pills divide what is left.
  ///
  /// 44 square, matching the pills' height and the iOS minimum tap
  /// target.
  Widget _searchButton(BuildContext context) {
    return GestureDetector(
      // Pushed, not switched to. Search is something you do from where
      // you already are and come back from; the bottom bar made it a
      // place you went instead, and going back meant choosing a tab.
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFDDDDDD), width: 1.4),
        ),
        child: const Icon(Icons.search, size: 21, color: Color(0xFF111111)),
      ),
    );
  }

  Widget _buildTab(int index, String label) {
    final isActive = controller.index == index;

    const duration = Duration(milliseconds: 220);
    const curve = Curves.easeOutCubic;

    return GestureDetector(
      // index, not animateTo. There is no page to slide any more: the
      // feeds share one scroll view and only the posts below the selector
      // change, so an animation here would move nothing and just delay it.
      onTap: () => controller.index = index,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: duration,
        curve: curve,
        // 44, from 38. Also the iOS minimum tap target, which these
        // were four pixels under.
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Filled when selected, outlined when not. The border stays on the
          // selected pill too, in the same colour as its fill — otherwise the
          // two pills are different heights by a hairline and the row looks
          // misaligned.
          color: isActive ? const Color(0xFF111111) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive ? const Color(0xFF111111) : const Color(0xFFDDDDDD),
            width: 1.4,
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: duration,
          curve: curve,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF111111),
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            fontSize: 14,
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// Holds the feed selector at the top of the list once it is scrolled to.
///
/// A fixed height, declared up front: a persistent header must know its
/// extent before it is laid out, and the selector is a fixed-height row of
/// pills, so there is nothing to measure at run time.
class _PinnedSelector extends SliverPersistentHeaderDelegate {
  final Widget child;

  /// 44 for the pills, plus the 15/9 padding the selector carries.
  ///
  /// Was 60, with 7 above the pills. That sat them almost against the
  /// section tabs above, so the two rows of navigation ran together
  /// instead of reading as separate choices — which section of Home,
  /// then which feed within it.
  ///
  /// Declared, not measured: a persistent header has to know its extent
  /// before layout, so this and the selector's own sizes have to agree by
  /// hand. Change one and change the other.
  static const double _height = 68;

  const _PinnedSelector({required this.child});

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Opaque, always. Pinned over a scrolling feed, any transparency means
    // posts sliding visibly underneath the pills.
    return Material(color: Colors.white, child: child);
  }

  @override
  bool shouldRebuild(_PinnedSelector old) => old.child != child;
}
