import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/widgets/feed/offers_banner.dart';
import 'package:drivelife/widgets/upload_progress_card.dart';
import 'package:flutter/material.dart';
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

  final GlobalKey<_PostsTabState> _latestKey = GlobalKey<_PostsTabState>();
  final GlobalKey<_PostsTabState> _followingKey = GlobalKey<_PostsTabState>();
  final GlobalKey<_PostsTabState> _newsKey = GlobalKey<_PostsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
          _CustomTabBar(controller: _tabController, theme: theme),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _PostsTab(key: _latestKey, tabType: PostTabType.latest),
                _PostsTab(key: _followingKey, tabType: PostTabType.following),
                _PostsTab(key: _newsKey, tabType: PostTabType.news),
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

  const _PostsTab({super.key, required this.tabType});

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
    });
  }

  void _onScroll() {
    if (!mounted) return;

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
          // Upload progress cards — Latest tab only
          if (widget.tabType == PostTabType.latest)
          const SliverToBoxAdapter(child: OffersBanner()),
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

class _CustomTabBar extends StatelessWidget {
  final TabController controller;
  final ThemeProvider theme;

  const _CustomTabBar({required this.controller, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          Expanded(child: _buildTab(0, 'Latest')),
          const SizedBox(width: 8),
          Expanded(child: _buildTab(1, 'Following')),
          const SizedBox(width: 8),
          Expanded(child: _buildTab(2, 'News')),

        ],
      ),
    );
  }

  Widget _buildTab(int index, String label) {
    return GestureDetector(
      onTap: () => controller.animateTo(index),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final isActive = controller.index == index;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            height: 38,
            decoration: BoxDecoration(
              color: isActive ? theme.primaryColor : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
