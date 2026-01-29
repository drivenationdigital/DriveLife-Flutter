import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/widgets/upload_progress_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../api/posts_api.dart';
import '../providers/user_provider.dart';
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

  // Keys for each tab to maintain their state
  final GlobalKey<_PostsTabState> _latestKey = GlobalKey<_PostsTabState>();
  final GlobalKey<_PostsTabState> _followingKey = GlobalKey<_PostsTabState>();
  final GlobalKey<_PostsTabState> _newsKey = GlobalKey<_PostsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  Future<void> scrollToTopAndRefresh() async {
    // Get the current tab's state and call its refresh method
    final currentKey = _getCurrentTabKey();
    currentKey.currentState?.scrollToTopAndRefresh();
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
          // Custom Tab Bar
          _CustomTabBar(controller: _tabController, theme: theme),

          // TabBarView with separate tab widgets
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics:
                  const NeverScrollableScrollPhysics(), // Prevent swipe to avoid conflicts
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

// Enum for tab types
enum PostTabType { latest, following, news }

// Separate widget for each tab's content
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

  final ScrollController _scrollController = ScrollController();
  final AuthService _auth = AuthService();

  List<dynamic> _posts = [];
  int _page = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isInitialized = false;

  Timer? _scrollDebounce;
  Set<String> _completedUploads = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Delay initial load slightly to ensure widget is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchPosts();
      }
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

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    final token = await _auth.getToken();

    if (user == null || token == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (refresh) {
      _page = 1;
      _hasMore = true;
    }

    // Determine the followingOnly parameter based on tab type
    int followingOnly;
    switch (widget.tabType) {
      case PostTabType.following:
        followingOnly = 1;
        break;
      case PostTabType.news:
        // For news tab, you might want to add a specific API parameter
        // For now, using latest posts - modify as needed
        followingOnly = 0;
        break;
      default:
        followingOnly = 0;
    }

    try {
      final newPosts = await PostsAPI.getPosts(
        token: token,
        userId: user.id,
        page: _page,
        limit: 10,
        followingOnly: followingOnly,
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
      print('Error fetching posts for ${widget.tabType}: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialized = true;
        });
      }
    }
  }

  void _checkUploadCompletions(Map<String, UploadPostProgress> uploads) {
    if (!mounted) return;

    for (final entry in uploads.entries) {
      if (entry.value.status == UploadStatus.completed &&
          !_completedUploads.contains(entry.key)) {
        _completedUploads.add(entry.key);

        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _fetchPosts(refresh: true);
          }
        });
      }
    }

    _completedUploads.removeWhere((id) => !uploads.containsKey(id));
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
      child: PrimaryScrollController(
        controller: _scrollController,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          cacheExtent: 2000,
          slivers: [
            // Upload progress cards - only show on Latest tab
            if (widget.tabType == PostTabType.latest)
              Consumer<UploadPostProvider>(
                builder: (context, uploadProvider, _) {
                  final uploads = uploadProvider.uploads;
                  _checkUploadCompletions(uploads);

                  if (uploads.isEmpty) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }

                  return SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        ...uploads.entries.map((entry) {
                          return UploadProgressCard(
                            key: ValueKey(entry.key),
                            uploadId: entry.key,
                            progress: entry.value,
                          );
                        }),
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
            // Loading state (first load)
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
                    // Loading indicator at the end
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

                    return RepaintBoundary(
                      child: PostCard(
                        key: ValueKey(post['id']),
                        post: post,
                        onTapProfile: () {
                          if (!mounted) return;
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
                          post['is_liked'] = isLiked;
                          post['likes_count'] += isLiked ? 1 : -1;
                        },
                      ),
                    );
                  },
                  childCount: _posts.length + (_hasMore ? 1 : 0),
                  addAutomaticKeepAlives: true,
                  addRepaintBoundaries: false,
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
      case PostTabType.news:
        return 'No news posts yet';
      default:
        return 'No posts yet';
    }
  }
}

// Custom Tab Bar Widget
// Custom Tab Bar Widget
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
          const SizedBox(width: 8), // Gap between tabs
          Expanded(child: _buildTab(1, 'Following')),
          const SizedBox(width: 8), // Gap between tabs
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
