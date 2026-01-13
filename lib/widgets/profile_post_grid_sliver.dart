import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/widgets/post_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/post_model.dart';
import '../services/posts_service.dart';
import '../utils/navigation_helper.dart';

class ProfilePostGridSliver extends StatefulWidget {
  final int userId;
  final bool isTagged;

  const ProfilePostGridSliver({
    super.key,
    required this.userId,
    this.isTagged = false,
  });

  @override
  State<ProfilePostGridSliver> createState() => _ProfilePostGridSliverState();
}

class _ProfilePostGridSliverState extends State<ProfilePostGridSliver>
    with AutomaticKeepAliveClientMixin {
  final PostsService _postsService = PostsService();

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
  }

  Future<void> _loadPosts({bool forceRefresh = false}) async {
    if (_isLoading || !mounted) return;

    setState(() => _isLoading = true);

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
    }
  }

  void _preloadPostDetails(List<Post> posts, {bool forceRefresh = false}) {
    for (final post in posts) {
      _postsService
          .getPostById(postId: post.id, forceRefresh: forceRefresh)
          .catchError((e) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Provider.of<ThemeProvider>(context);

    if (_isInitialLoad) {
      return SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    if (_posts.isEmpty) {
      return SliverFillRemaining(
        child: Center(
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
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(2),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
          childAspectRatio: 1,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            // Load more when reaching end
            if (index == _posts.length - 3 && !_isLoading && _hasMore) {
              Future.microtask(() => _loadPosts());
            }

            if (index < _posts.length) {
              final post = _posts[index];
              return _buildPostTile(post, theme);
            } else {
              return const SizedBox.shrink();
            }
          },
          childCount:
              _posts.length + (_isLoading ? 3 : 0), // Add loading placeholders
        ),
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
