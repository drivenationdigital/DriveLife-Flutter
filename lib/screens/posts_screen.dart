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
  /// Told which way the feed is scrolling, so the shell can get its header
  /// and bottom bar out of the way. Null when nothing is listening.
  final ChromeVisibility? chrome;

  const PostsScreen({super.key, this.chrome});

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

  final GlobalKey<_PostsTabState> _forYouKey = GlobalKey<_PostsTabState>();
  final GlobalKey<_PostsTabState> _latestKey = GlobalKey<_PostsTabState>();
  final GlobalKey<_PostsTabState> _followingKey = GlobalKey<_PostsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // When the user switches tabs, reveal the pills again so they're never
    // stuck hidden on a tab that has nothing to scroll.
    // _tabController.addListener(() {
    // });
  }

  Future<void> scrollToTopAndRefresh() async {
    _getCurrentTabKey().currentState?.scrollToTopAndRefresh();
  }

  GlobalKey<_PostsTabState> _getCurrentTabKey() {
    switch (_tabController.index) {
      case 0:
        return _latestKey;
      case 1:
        return _followingKey;
      case 2:
        return _forYouKey;
      default:
        return _latestKey;
    }
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
      // Order must match _CustomTabBar._labels.
      children: [
        for (final tab in [
          (_latestKey, PostTabType.latest),
          (_followingKey, PostTabType.following),
          (_forYouKey, PostTabType.forYou),
        ])
          _PostsTab(
            key: tab.$1,
            tabType: tab.$2,
            selector: _CustomTabBar(controller: _tabController, theme: theme),
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

  const _PostsTab({super.key, required this.tabType, required this.selector});

  @override
  State<_PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<_PostsTab>
    with AutomaticKeepAliveClientMixin {
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
                        // FIX: Wrap mutation in setState so any widget listening
                        // to _posts gets a proper rebuild signal
                        setState(() {
                          post['is_liked'] = isLiked;
                          post['likes_count'] =
                              (post['likes_count'] as int) + (isLiked ? 1 : -1);
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

  const _CustomTabBar({required this.controller, required this.theme});

  /// "Featured" is the curated tab — same feed as the old "For You", renamed.
  /// Order must match the TabBarView children in [PostsScreenState.build].
  static const List<String> _labels = ['Latest', 'Following', 'Featured'];

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
              for (var i = 0; i < _labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _buildTab(i, _labels[i])),
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
