import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:flutter/rendering.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:drivelife/api/offers_api_service.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/widgets/feed/hot_right_now.dart';
import 'package:drivelife/widgets/feed/offers_banner.dart';
import 'package:drivelife/widgets/upload_progress_card.dart';
import 'package:flutter/material.dart';
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
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late TabController _tabController;

  // NEW: shared visibility flag for the pills row. Tabs flip it on scroll;
  // the parent rebuilds only the pills wrapper via ValueListenableBuilder.

  /// The feeds on offer, in the order they appear.
  ///
  /// Featured is hidden rather than removed: the tab, its fetch and its
  /// backend are all intact, and putting [PostTabType.forYou] back in this
  /// list is the only change needed to bring it back.
  ///
  /// The selector, the TabController's length and the TabBarView's children
  /// all read this, so none of them can disagree about how many tabs there
  /// are — which is the usual way a hidden tab turns into a crash.
  static const List<PostTabType> _visibleTabs = [
    PostTabType.latest,
    PostTabType.following,
    // PostTabType.forYou,
  ];

  final GlobalKey<_PostsTabState> _forYouKey = GlobalKey<_PostsTabState>();
  final GlobalKey<_PostsTabState> _latestKey = GlobalKey<_PostsTabState>();
  final GlobalKey<_PostsTabState> _followingKey = GlobalKey<_PostsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _visibleTabs.length, vsync: this);
    // When the user switches tabs, reveal the pills again so they're never
    // stuck hidden on a tab that has nothing to scroll.
    // _tabController.addListener(() {
    // });
  }

  Future<void> scrollToTopAndRefresh() async {
    _getCurrentTabKey().currentState?.scrollToTopAndRefresh();
  }

  GlobalKey<_PostsTabState> _keyFor(PostTabType type) => switch (type) {
    PostTabType.latest => _latestKey,
    PostTabType.following => _followingKey,
    PostTabType.forYou => _forYouKey,
  };

  GlobalKey<_PostsTabState> _getCurrentTabKey() {
    final index = _tabController.index.clamp(0, _visibleTabs.length - 1);
    return _keyFor(_visibleTabs[index]);
  }

  @override
  void dispose() {
    _tabController.dispose();
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
    // Three plain scroll views, not a NestedScrollView over a TabBarView.
    //
    // The nested version crashed. Its coordinator keeps outer and inner
    // scrolls in step and asserts in _getMetrics when the viewport changes
    // size underneath it — which is exactly what the collapsing header does,
    // on every scroll. It also needed SliverOverlapAbsorber/Injector to stop
    // the pinned selector jumping, and the whole arrangement existed only to
    // share one header between three tabs.
    //
    // Each tab now carries its own copy of that header. The hot row is
    // static cards and the selector is the same widget in the same place, so
    // all three look identical — and each tab keeps its own scroll position,
    // which is what a reader would expect anyway.
    return TabBarView(
      controller: _tabController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final type in _visibleTabs)
          _PostsTab(
            key: _keyFor(type),
            tabType: type,
            header: widget.header,
            headerHeight: widget.headerHeight,
            selector: _CustomTabBar(
              controller: _tabController,
              theme: theme,
              tabs: _visibleTabs,
            ),
          ),
      ],
    );
  }
}

/// [forYou] is the curated tab: hand-picked featured posts plus news items,
/// ordered by the backend. [latest] and [following] remain the chronological
/// feeds they always were.
enum PostTabType { forYou, latest, following }

class _PostsTab extends StatefulWidget {
  final PostTabType tabType;

  /// The feed selector, pinned inside this tab's own scroll view.
  ///
  /// Passed in rather than built here so all three tabs share one widget
  /// definition and one TabController — they differ only in which scroll
  /// view they happen to be pinned inside.
  final Widget selector;

  /// The shell's chrome, floating above the selector. Null when the shell is
  /// drawing it itself, which it does for every destination but this one.
  final Widget? header;

  /// How tall [header] is. A sliver header declares its extent before layout,
  /// so this cannot be measured.
  final double headerHeight;

  const _PostsTab({
    super.key,
    required this.tabType,
    required this.selector,
    this.header,
    this.headerHeight = 0,
  });

  @override
  State<_PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<_PostsTab>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  /// This feed's own scroll.
  ///
  /// Its own again now the NestedScrollView has gone: one controller, one
  /// position, no coordinator to keep in step and nothing to assert about.
  final ScrollController _scrollController = ScrollController();
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

  Timer? _scrollDebounce;

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
  bool _onScrollNotification(ScrollNotification notification) {
    if (!mounted) return false;

    // Only this list's own scrolling. A horizontal notification from a
    // carousel in a post would otherwise page the feed.
    if (notification.metrics.axis != Axis.vertical) return false;

    if (_scrollDebounce?.isActive ?? false) _scrollDebounce!.cancel();

    final metrics = notification.metrics;

    _scrollDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;

      if (metrics.pixels >= metrics.maxScrollExtent - 500 &&
          !_isLoading &&
          _hasMore) {
        _fetchPosts();
      }
    });

    return false;
  }

  Future<void> scrollToTopAndRefresh() async {
    if (!mounted) return;
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    await _fetchPosts(refresh: true);
  }

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
      if (widget.tabType == _offersTab) _fetchOffers();
    }

    int followingOnly;
    int forYou;

    switch (widget.tabType) {
      case PostTabType.following:
        followingOnly = 1;
        forYou = 0;
        break;
      case PostTabType.forYou:
        followingOnly = 0;
        forYou = 1;
        break;
      default:
        followingOnly = 0;
        forYou = 0;
    }

    try {
      final newPosts = await PostsAPI.getPosts(
        token: token,
        userId: user.id,
        page: _page,
        limit: 10,
        followingOnly: followingOnly,
        forYou: forYou,
      );

      if (!mounted) return;

      setState(() {
        if (refresh) {
          _posts = newPosts;
        } else {
          _posts.addAll(newPosts);
        }
        _page++;
        _hasMore = newPosts.length >= 10;
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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Provider.of<ThemeProvider>(context);

    return RefreshIndicator(
      color: theme.primaryColor,
      backgroundColor: theme.backgroundColor,
      onRefresh: () => _fetchPosts(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          cacheExtent: 2000,
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

            // Scrolls away: a standing recommendation, not navigation, so it
            // should not hold the top of the screen for ever.
            const SliverToBoxAdapter(child: HotRightNow()),

            // Pins. This one IS navigation — losing it mid-feed would mean
            // scrolling back to the top to change tab.
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedSelector(child: widget.selector),
            ),

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
            else
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

                    return PostCard(
                      key: ValueKey(post['id']),
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
                      onDelete: scrollToTopAndRefresh,
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
        ),
      ),
    );
  }

  String _getEmptyMessage() {
    switch (widget.tabType) {
      case PostTabType.following:
        return 'No posts from people you follow';
      case PostTabType.forYou:
        return 'Nothing featured right now';
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
    PostTabType.forYou: 'Featured',
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 7, 16, 9),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _buildTab(i, _labels[tabs[i]] ?? '')),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTab(int index, String label) {
    final isActive = controller.index == index;

    const duration = Duration(milliseconds: 220);
    const curve = Curves.easeOutCubic;

    return GestureDetector(
      onTap: () => controller.animateTo(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: duration,
        curve: curve,
        height: 38,
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

  /// 38 for the pills, plus the 7/9 padding the selector carries.
  ///
  /// Declared, not measured: a persistent header has to know its extent
  /// before layout, so this and the selector's own sizes have to agree by
  /// hand. Change one and change the other.
  static const double _height = 54;

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
