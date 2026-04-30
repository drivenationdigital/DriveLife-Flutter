import 'package:drivelife/api/offers_api_service.dart';
import 'package:drivelife/main.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/screens/events/add_event_screen.dart';
import 'package:drivelife/screens/garage/garage_list_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/widgets/feed/offers_banner.dart';
import 'package:drivelife/widgets/upload_progress_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../api/posts_api.dart';
import '../services/auth_service.dart';
import '../components/post_card.dart';

class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

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
  final ValueNotifier<bool> _pillsVisible = ValueNotifier<bool>(true);

  final GlobalKey<_PostsTabState> _latestKey = GlobalKey<_PostsTabState>();
  final GlobalKey<_PostsTabState> _followingKey = GlobalKey<_PostsTabState>();
  final GlobalKey<_PostsTabState> _newsKey = GlobalKey<_PostsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // When the user switches tabs, reveal the pills again so they're never
    // stuck hidden on a tab that has nothing to scroll.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _pillsVisible.value = true;
    });
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
        return _newsKey;
      default:
        return _latestKey;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pillsVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Pills collapse on scroll-down, expand on scroll-up.
          ValueListenableBuilder<bool>(
            valueListenable: _pillsVisible,
            builder: (context, visible, _) {
              return ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  alignment: Alignment.bottomCenter,
                  child: visible
                      ? const _ActionPills()
                      : const SizedBox(height: 0, width: double.infinity),
                ),
              );
            },
          ),
          // Tab bar stays pinned.
          _CustomTabBar(controller: _tabController, theme: theme),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _PostsTab(
                  key: _latestKey,
                  tabType: PostTabType.latest,
                  pillsVisible: _pillsVisible,
                ),
                _PostsTab(
                  key: _followingKey,
                  tabType: PostTabType.following,
                  pillsVisible: _pillsVisible,
                ),
                _PostsTab(
                  key: _newsKey,
                  tabType: PostTabType.news,
                  pillsVisible: _pillsVisible,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum PostTabType { latest, following, news }

class _PostsTab extends StatefulWidget {
  final PostTabType tabType;
  final ValueNotifier<bool> pillsVisible; // NEW

  const _PostsTab({
    super.key,
    required this.tabType,
    required this.pillsVisible,
  });

  @override
  State<_PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<_PostsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // FIX: Single controller — no need for PrimaryScrollController wrapper
  final ScrollController _scrollController = ScrollController();
  final AuthService _auth = AuthService();

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
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final accountManager = Provider.of<AccountManager>(
        context,
        listen: false,
      );
      _currentUserId = accountManager.activeUser?.id;
      _fetchPosts();
      _fetchOffers();
    });
  }

  void _onScroll() {
    if (!mounted) return;

    // Pill visibility — immediate (not debounced).
    // Reverse = user dragging up (content scrolling down) → hide.
    // Forward = user dragging down (content scrolling up) → show.
    // Always show when at the very top.
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      if (pos.pixels <= 0) {
        widget.pillsVisible.value = true;
      } else {
        final dir = pos.userScrollDirection;
        if (dir == ScrollDirection.reverse) {
          widget.pillsVisible.value = false;
        } else if (dir == ScrollDirection.forward) {
          widget.pillsVisible.value = true;
        }
      }
    }

    // Pagination — debounced (unchanged behaviour).
    if (_scrollDebounce?.isActive ?? false) _scrollDebounce!.cancel();

    _scrollDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      if (_scrollController.hasClients &&
          _scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 500 &&
          !_isLoading &&
          _hasMore) {
        _fetchPosts();
      }
    });
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
      _fetchOffers();
    }

    int followingOnly;
    int newsOnly;

    switch (widget.tabType) {
      case PostTabType.following:
        followingOnly = 1;
        newsOnly = 0;
        break;
      case PostTabType.news:
        followingOnly = 0;
        newsOnly = 1;
        break;
      default:
        followingOnly = 0;
        newsOnly = 0;
    }

    try {
      final newPosts = await PostsAPI.getPosts(
        token: token,
        userId: user.id,
        page: _page,
        limit: 10,
        followingOnly: followingOnly,
        newsOnly: newsOnly,
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
      child: CustomScrollView(
        // FIX: Removed redundant PrimaryScrollController wrapper — passing the
        // controller directly is sufficient and avoids potential conflicts
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 2000,
        slivers: [
          // SliverToBoxAdapter(child: StoriesRow()),
          // Upload progress cards — Latest tab only
          if (widget.tabType == PostTabType.latest)
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
    );
  }

  String _getEmptyMessage() {
    switch (widget.tabType) {
      case PostTabType.following:
        return 'No posts from people you follow';
      case PostTabType.news:
        return 'No news posts yet';
      default:
        return 'No posts yet';
    }
  }
}

class _ActionPills extends StatelessWidget {
  const _ActionPills();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _PillButton(
              label: 'Find Events',
              icon: Icons.search,
              isPrimary: false,
              onTap: () {
                // Switch bottom nav to Events tab (index 1)
                context.read<BottomNavProvider>().setIndex(1);
              },
            ),
            const SizedBox(width: 8),
            _PillButton(
              label: 'Add Event',
              icon: Icons.calendar_today_outlined,
              isPrimary: false,
              onTap: () {
                NavigationHelper.navigateTo(context, const AddEventScreen());
              },
            ),
            const SizedBox(width: 8),
            _PillButton(
              label: 'Find Venues',
              icon: Icons.location_on_outlined,
              isPrimary: false,
              onTap: () {
                // Switch bottom nav to Venues/Places tab (index 2)
                context.read<BottomNavProvider>().setIndex(2);
              },
            ),
            const SizedBox(width: 8),
            _PillButton(
              label: 'Find Clubs',
              icon: Icons.groups_outlined,
              isPrimary: false,
              onTap: () {
                // Switch bottom nav to Clubs tab (index 3)
                context.read<BottomNavProvider>().setIndex(3);
              },
            ),
            const SizedBox(width: 8),
            _PillButton(
              label: 'Manage Garage',
              icon: Icons.build_outlined,
              isPrimary: false,
              onTap: () {
                NavigationHelper.navigateTo(context, const GarageListScreen());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final fg = isPrimary ? Colors.white : Colors.black;
    final bg = isPrimary ? Colors.black : theme.subtextColor.withOpacity(0.1);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(30),
            border: isPrimary
                ? null
                : Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: theme.primaryColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// UPDATED: Underline-style tab bar (Latest / Following / News)
// =====================================================================
class _CustomTabBar extends StatelessWidget {
  final TabController controller;
  final ThemeProvider theme;

  const _CustomTabBar({required this.controller, required this.theme});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(child: _buildTab(0, 'Latest')),
              Expanded(child: _buildTab(1, 'Following')),
              Expanded(child: _buildTab(2, 'News')),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTab(int index, String label) {
    final isActive = controller.index == index;

    return GestureDetector(
      onTap: () => controller.animateTo(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isActive ? Colors.black : Colors.grey,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            // Full-width underline; colour fades in/out on active state.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 2.5,
              width: double.infinity,
              color: isActive ? theme.primaryColor : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
