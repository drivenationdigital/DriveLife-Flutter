import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/components/post_card.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HashtagPostsPage extends StatefulWidget {
  final String hashtag;

  const HashtagPostsPage({Key? key, required this.hashtag}) : super(key: key);

  @override
  State<HashtagPostsPage> createState() => _HashtagPostsPageState();
}

class _HashtagPostsPageState extends State<HashtagPostsPage> {
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _fetchPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_loadingMore &&
        _page < _totalPages) {
      _fetchMore();
    }
  }

  Future<void> _fetchPosts() async {
    setState(() {
      _loading = true;
    });
    try {
      final result = await PostsAPI.getPostsByHashtag(
        hashtag: widget.hashtag,
        page: 1,
      );
      setState(() {
        _posts = result['data'] ?? [];
        _totalPages = result['total_pages'] ?? 1;
        _page = 1;
      });
    } catch (e) {
      debugPrint('Error fetching hashtag posts: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchMore() async {
    setState(() => _loadingMore = true);
    try {
      final result = await PostsAPI.getPostsByHashtag(
        hashtag: widget.hashtag,
        page: _page + 1,
      );
      setState(() {
        _posts.addAll(result['data'] ?? []);
        _page++;
      });
    } catch (e) {
      debugPrint('Error fetching more hashtag posts: $e');
    } finally {
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.hashtag,
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (!_loading)
              Text(
                '${_posts.length} posts',
                style: TextStyle(
                  color: theme.textColor.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : _posts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tag,
                    size: 48,
                    color: theme.textColor.withOpacity(0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No posts for ${widget.hashtag}',
                    style: TextStyle(color: theme.textColor.withOpacity(0.5)),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              color: theme.primaryColor,
              onRefresh: _fetchPosts,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _posts.length + (_loadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _posts.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: theme.primaryColor,
                        ),
                      ),
                    );
                  }
                  return PostCard(post: _posts[index]);
                },
              ),
            ),
    );
  }
}
