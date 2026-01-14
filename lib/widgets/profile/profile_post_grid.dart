import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/post_model.dart';
import '../../services/posts_service.dart';
import 'post_detail_screen.dart';
import '../../utils/navigation_helper.dart';

class ProfilePostGrid extends StatefulWidget {
  final int userId;
  final bool isTagged;

  const ProfilePostGrid({
    super.key,
    required this.userId,
    this.isTagged = false,
  });

  @override
  State<ProfilePostGrid> createState() => _ProfilePostGridState();
}

class _ProfilePostGridState extends State<ProfilePostGrid>
    with AutomaticKeepAliveClientMixin {
  final PostsService _postsService = PostsService();
  final ScrollController _scrollController = ScrollController();

  List<Post> _posts = [];
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isInitialLoad = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadPosts();
      }
    }
  }

  Future<void> _loadPosts({bool forceRefresh = false}) async {
    if (_isLoading || !mounted) return;

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await _postsService.getUserPosts(
        userId: widget.userId,
        page: _currentPage,
        limit: 9,
        tagged: widget.isTagged,
      );

      if (!mounted) return;

      if (response != null) {
        setState(() {
          _totalPages = response.totalPages;
          _posts.addAll(response.data);

          // ✅ Preload post details in background (with cache or force refresh)
          _preloadPostDetails(response.data, forceRefresh: forceRefresh);

          if (response.data.isEmpty) {
            _hasMore = false;
          } else if (_currentPage >= _totalPages) {
            _hasMore = false;
          } else {
            _currentPage++;
          }

          _isLoading = false;
          _isInitialLoad = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isInitialLoad = false;
            _hasMore = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialLoad = false;
        });
      }
      print('Error loading posts: $e');
    }
  }

  // ✅ Preload post details in background for instant loading
  // Uses cache if available (10 min), fetches if not
  void _preloadPostDetails(List<Post> posts, {bool forceRefresh = false}) {
    for (final post in posts) {
      _postsService
          .getPostById(postId: post.id, forceRefresh: forceRefresh)
          .catchError((e) {
            print('Background preload failed for post ${post.id}: $e');
          });
    }
  }

  Future<void> _refreshPosts() async {
    if (!mounted) return;

    setState(() {
      _posts.clear();
      _currentPage = 1;
      _totalPages = 0;
      _hasMore = true;
      _isInitialLoad = true;
    });

    // Force refresh on pull-to-refresh
    await _loadPosts(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Provider.of<ThemeProvider>(context);

    if (_isInitialLoad) {
      return Center(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Center(
            child: CircularProgressIndicator(color: theme.primaryColor),
          ),
        ),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.isTagged
                  ? Icons.label_outline
                  : Icons.photo_library_outlined,
              size: 64,
              color: theme.subtextColor,
            ),
            const SizedBox(height: 16),
            Text(
              widget.isTagged ? 'No tagged posts yet' : 'No posts yet',
              style: TextStyle(color: theme.subtextColor, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshPosts,
      color: theme.primaryColor,
      backgroundColor: theme.cardColor,
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
                childAspectRatio: 1,
              ),
              itemCount: _posts.length,
              itemBuilder: (context, index) {
                final post = _posts[index];
                return _buildPostTile(post, theme);
              },
            ),
          ),
          if (_isLoading && !_isInitialLoad)
            Container(
              padding: const EdgeInsets.all(16),
              child: CircularProgressIndicator(
                color: theme.primaryColor,
                strokeWidth: 2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPostTile(Post post, ThemeProvider theme) {
    final hasMultipleMedia = post.media.length > 1;
    final hasVideo = post.hasVideo;

    return GestureDetector(
      onTap: () {
        if (!mounted) return;
        NavigationHelper.navigateTo(context, PostDetailScreen(postId: post.id));
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              image: post.thumbnailUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(post.thumbnailUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: post.thumbnailUrl.isEmpty
                ? Center(
                    child: Icon(
                      Icons.image_not_supported,
                      color: theme.subtextColor,
                      size: 32,
                    ),
                  )
                : null,
          ),

          // Keep existing overlay icons...
          Positioned(
            top: 4,
            right: 4,
            child: Row(
              children: [
                if (hasMultipleMedia)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.collections,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                if (hasVideo) ...[
                  if (hasMultipleMedia) const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
