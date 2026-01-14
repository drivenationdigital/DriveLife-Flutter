import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/posts_service.dart';
import '../../components/post_card.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final PostsService _postsService = PostsService();
  Map<String, dynamic>? _post;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  Future<void> _loadPost({bool forceRefresh = false}) async {
    // Data should already be preloaded/cached, so this will be instant
    final response = await _postsService.getPostById(
      postId: widget.postId,
      forceRefresh: forceRefresh,
    );

    if (!mounted) return;

    setState(() {
      // API returns raw JSON, so just use it directly
      if (response != null) {
        _post = response; // Already in correct format for PostCard
      }
      _isLoading = false;
    });
  }

  Future<void> _refreshPost() async {
    await _loadPost(forceRefresh: true);

    if (!mounted) return;

    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Post refreshed'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    // Show skeleton with app bar while loading
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.black),
            iconSize: 38,
            onPressed: () => Navigator.of(context).pop(),
          ),
          centerTitle: true,
          title: Image.asset(
            'assets/logo-dark.png',
            height: 18,
            alignment: Alignment.center,
          ),
        ),
        body: _buildPostSkeleton(),
      );
    }

    if (_post == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.black),
            iconSize: 38,
            onPressed: () => Navigator.of(context).pop(),
          ),
          centerTitle: true,
          title: Image.asset(
            'assets/logo-dark.png',
            height: 18,
            alignment: Alignment.center,
          ),
        ),
        body: const Center(
          child: Text('Post not found', style: TextStyle(color: Colors.black)),
        ),
      );
    }

    // ✅ Reuse PostCard component
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black),
          iconSize: 38,
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Image.asset(
          'assets/logo-dark.png',
          height: 18,
          alignment: Alignment.center,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.black),
            onPressed: () {
              // TODO: Show post options
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshPost,
        color: theme.primaryColor,
        child: SingleChildScrollView(
          physics:
              const AlwaysScrollableScrollPhysics(), // ✅ Allows pull-to-refresh even if content fits
          child: PostCard(
            post: _post!,
            onTapProfile: () {
              Navigator.pushNamed(
                context,
                '/view-profile',
                arguments: {
                  'userId': _post!['user_id'],
                  'username': _post!['username'],
                },
              );
            },
            onLikeChanged: (isLiked) {
              if (!mounted) return;
              setState(() {
                _post!['is_liked'] = isLiked;
                _post!['likes_count'] += isLiked ? 1 : -1;
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPostSkeleton() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header skeleton
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 100,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 60,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Media skeleton
          Container(height: 400, color: Colors.grey.shade300),

          // Actions skeleton
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),

          // Likes skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: 60,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Caption skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 200,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
