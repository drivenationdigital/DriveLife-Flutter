import 'package:flutter/material.dart';
import '../models/post_model.dart';
import '../services/posts_service.dart';
import 'post_detail_screen.dart';

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

    if (_isInitialLoad) {
      return Center(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.orange),
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
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              widget.isTagged ? 'No tagged posts yet' : 'No posts yet',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // ✅ Use Column to show grid + loading spinner below
    return RefreshIndicator(
      onRefresh: _refreshPosts,
      color: Colors.orange,
      backgroundColor: const Color(0xFF2A2A2A),
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
                return _buildPostTile(post);
              },
            ),
          ),
          // ✅ Loading spinner below grid (full width, centered)
          if (_isLoading && !_isInitialLoad)
            Container(
              padding: const EdgeInsets.all(16),
              child: const CircularProgressIndicator(
                color: Colors.orange,
                strokeWidth: 2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPostTile(Post post) {
    final hasMultipleMedia = post.media.length > 1;
    final hasVideo = post.hasVideo;

    return GestureDetector(
      onTap: () {
        if (!mounted) return;

        // Navigate to post detail with slide animation
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                PostDetailScreen(postId: post.id),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  const begin = Offset(1.0, 0.0); // Slide from right
                  const end = Offset.zero;
                  const curve = Curves.easeInOut;

                  var tween = Tween(
                    begin: begin,
                    end: end,
                  ).chain(CurveTween(curve: curve));

                  return SlideTransition(
                    position: animation.drive(tween),
                    child: child,
                  );
                },
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              image: post.thumbnailUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(post.thumbnailUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: post.thumbnailUrl.isEmpty
                ? const Center(
                    child: Icon(
                      Icons.image_not_supported,
                      color: Colors.grey,
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

          // if (post.caption.isNotEmpty)
          //   Positioned(
          //     bottom: 0,
          //     left: 0,
          //     right: 0,
          //     child: Container(
          //       padding: const EdgeInsets.all(6),
          //       decoration: BoxDecoration(
          //         gradient: LinearGradient(
          //           begin: Alignment.bottomCenter,
          //           end: Alignment.topCenter,
          //           colors: [Colors.black.withOpacity(0.7), Colors.transparent],
          //         ),
          //       ),
          //       child: Text(
          //         post.caption,
          //         maxLines: 2,
          //         overflow: TextOverflow.ellipsis,
          //         style: const TextStyle(
          //           color: Colors.white,
          //           fontSize: 10,
          //           fontWeight: FontWeight.w500,
          //         ),
          //       ),
          //     ),
          //   ),
        ],
      ),
    );
  }
}
