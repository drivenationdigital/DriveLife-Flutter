import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/widgets/upload_progress_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';

import '../api/posts_api.dart';
import '../providers/user_provider.dart';
import '../services/auth_service.dart';
import '../components/post_card.dart';

class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScrollController _scrollController = ScrollController();
  final AuthService _auth = AuthService();

  // Separate lists for each tab
  List<dynamic> latestPosts = [];
  List<dynamic> followingPosts = [];

  int latestPage = 1;
  int followingPage = 1;

  bool isLoading = false;
  bool hasMoreLatest = true;
  bool hasMoreFollowing = true;

  bool showFollowing = false;

  // Track completed uploads to trigger refresh
  Set<String> _completedUploads = {};

  // Debounce timer for scroll events
  Timer? _scrollDebounce;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fetchPosts();
    });

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // Debounce scroll events to prevent excessive calls
    if (_scrollDebounce?.isActive ?? false) _scrollDebounce!.cancel();

    _scrollDebounce = Timer(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients &&
          _scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 500 &&
          !isLoading) {
        fetchPosts();
      }
    });
  }

  Future<void> fetchPosts({bool refresh = false}) async {
    if (isLoading) return;

    // Don't trigger setState if already loading
    if (!mounted) return;

    setState(() => isLoading = true);

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    final token = await _auth.getToken();

    if (user == null || token == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    final followingOnly = showFollowing ? 1 : 0;
    int currentPage = showFollowing ? followingPage : latestPage;

    if (refresh) {
      currentPage = 1;

      if (showFollowing) {
        followingPosts.clear();
        hasMoreFollowing = true;
        followingPage = 1;
      } else {
        latestPosts.clear();
        hasMoreLatest = true;
        latestPage = 1;
      }
    }

    try {
      final newPosts = await PostsAPI.getPosts(
        token: token,
        userId: user['id'],
        page: currentPage,
        limit: 10,
        followingOnly: followingOnly,
      );

      // Use addPostFrameCallback to avoid setState during build
      if (!mounted) return;

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        setState(() {
          if (showFollowing) {
            if (refresh) {
              followingPosts = newPosts;
            } else {
              followingPosts.addAll(newPosts);
            }
            followingPage++;
            hasMoreFollowing =
                newPosts.length >= 10; // If less than limit, no more
          } else {
            if (refresh) {
              latestPosts = newPosts;
            } else {
              latestPosts.addAll(newPosts);
            }
            latestPage++;
            hasMoreLatest = newPosts.length >= 10;
          }

          isLoading = false;
        });
      });
    } catch (e) {
      print('Error fetching posts: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _switchTab(bool following) {
    if (showFollowing == following) return; // Avoid unnecessary rebuilds

    setState(() => showFollowing = following);

    if (following && followingPosts.isEmpty) {
      fetchPosts();
    } else if (!following && latestPosts.isEmpty) {
      fetchPosts();
    }
  }

  void _checkUploadCompletions(Map<String, UploadPostProgress> uploads) {
    for (final entry in uploads.entries) {
      if (entry.value.status == UploadStatus.completed &&
          !_completedUploads.contains(entry.key)) {
        _completedUploads.add(entry.key);

        // Debounce refresh to avoid multiple rapid refreshes
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            fetchPosts(refresh: true);
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

    final posts = showFollowing ? followingPosts : latestPosts;
    final hasMore = showFollowing ? hasMoreFollowing : hasMoreLatest;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Tabs - Make const where possible
          _TabBar(showFollowing: showFollowing, onTabChanged: _switchTab),

          // Feed
          Expanded(
            child: RefreshIndicator(
              color: theme.primaryColor,
              backgroundColor: theme.backgroundColor,
              onRefresh: () => fetchPosts(refresh: true),
              // Separate Consumer to only rebuild upload section
              child: CustomScrollView(
                controller: _scrollController,
                physics:
                    const AlwaysScrollableScrollPhysics(), // For RefreshIndicator
                cacheExtent: 2000, // Increased cache for smoother scrolling
                slivers: [
                  // Upload progress cards - isolated in Consumer
                  Consumer<UploadPostProvider>(
                    builder: (context, uploadProvider, _) {
                      final uploads = uploadProvider.uploads;
                      _checkUploadCompletions(uploads);

                      if (uploads.isEmpty) {
                        return const SliverToBoxAdapter(
                          child: SizedBox.shrink(),
                        );
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

                  // Posts list - optimized with SliverList
                  if (posts.isEmpty && !isLoading)
                    const SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'No posts yet',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // Loading indicator at the end
                          if (index == posts.length) {
                            if (!hasMore) return const SizedBox.shrink();

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

                          final post = posts[index];

                          // Wrap each post in RepaintBoundary for better performance
                          return RepaintBoundary(
                            child: PostCard(
                              key: ValueKey(post['id']),
                              post: post,
                              onTapProfile: () {
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
                                // Update without setState for better performance
                                post['is_liked'] = isLiked;
                                post['likes_count'] += isLiked ? 1 : -1;
                              },
                            ),
                          );
                        },
                        childCount: posts.length + (hasMore ? 1 : 0),
                        addAutomaticKeepAlives: true, // Keep post state
                        addRepaintBoundaries:
                            false, // We're adding them manually
                        addSemanticIndexes: false,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Extracted tab bar as separate widget for better performance
class _TabBar extends StatelessWidget {
  final bool showFollowing;
  final Function(bool) onTabChanged;

  const _TabBar({required this.showFollowing, required this.onTabChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TabButton(
            label: 'Latest',
            active: !showFollowing,
            onTap: () => onTabChanged(false),
            theme: theme,
          ),
          const SizedBox(width: 12),
          _TabButton(
            label: 'Following',
            active: showFollowing,
            onTap: () => onTabChanged(true),
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ThemeProvider theme;

  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          height: 34,
          decoration: BoxDecoration(
            color: active ? theme.primaryColor : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
