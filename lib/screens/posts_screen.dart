import 'package:drivelife/widgets/feed_video_player.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  bool showFollowing = false; // current tab state

  @override
  void initState() {
    super.initState();
    fetchPosts(); // load Latest initially
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !isLoading) {
      fetchPosts(); // fetch more based on active tab
    }
  }

  Future<void> fetchPosts({bool refresh = false}) async {
    if (isLoading) return;

    setState(() => isLoading = true);

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    final token = await _auth.getToken();

    if (user == null || token == null) {
      setState(() => isLoading = false);
      return;
    }

    final followingOnly = showFollowing ? 1 : 0;

    // Which feed are we updating?
    int currentPage = showFollowing ? followingPage : latestPage;

    // Refresh handling
    if (refresh) {
      currentPage = 1;
      if (showFollowing) {
        followingPosts.clear();
        hasMoreFollowing = true;
      } else {
        latestPosts.clear();
        hasMoreLatest = true;
      }
    }

    final newPosts = await PostsAPI.getPosts(
      token: token,
      userId: user['id'],
      page: currentPage,
      limit: 10,
      followingOnly: followingOnly,
    );

    final sampleVideos = [
      'https://videodelivery.net/c2b98b8485461a046d6fc867d57b6782/manifest/video.m3u8',
      'https://videodelivery.net/c2b98b8485461a046d6fc867d57b6782/manifest/video.m3u8',
      'https://videodelivery.net/f2c5e16577b2dbfc2b629b9ebedba218/manifest/video.m3u8',
      'https://videodelivery.net/7116846f5aeadfaba0968bd512268038/manifest/video.m3u8',
      'https://videodelivery.net/7116846f5aeadfaba0968bd512268038/manifest/video.m3u8',
      'https://videodelivery.net/7116846f5aeadfaba0968bd512268038/manifest/video.m3u8',
      'https://videodelivery.net/7116846f5aeadfaba0968bd512268038/manifest/video.m3u8',
    ];

    for (var post in newPosts) {
      if (post['media'] is List && post['media'].isNotEmpty) {
        // 60% chance to convert 1 media item into a "video"
        if (post.hashCode % 2 == 0) {
          final randomVideo = sampleVideos[post.hashCode % sampleVideos.length];
          post['media'][0] = {'media_url': randomVideo, 'media_type': 'video'};

          // remove other media items for simplicity
          post['media'] = [post['media'][0]];
        }
      }
    }

    setState(() {
      if (showFollowing) {
        followingPosts.addAll(newPosts);
        followingPage++;
        hasMoreFollowing = newPosts.isNotEmpty;
      } else {
        latestPosts.addAll(newPosts);
        latestPage++;
        hasMoreLatest = newPosts.isNotEmpty;
      }
      isLoading = false;
    });
  }

  void _switchTab(bool following) {
    setState(() => showFollowing = following);

    // Only fetch once per tab, unless it’s empty
    if (following && followingPosts.isEmpty) {
      fetchPosts();
    } else if (!following && latestPosts.isEmpty) {
      fetchPosts();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _flattenMedia(List<dynamic> posts) {
    final List<Map<String, dynamic>> mediaList = [];

    for (var post in posts) {
      if (post['media'] is List) {
        for (var m in post['media']) {
          mediaList.add({
            'media_url': m['media_url'],
            'blurred_url': m['blurred_url'],
            'media_type': m['media_type'], // image/video
          });
        }
      }
    }
    return mediaList;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Pick which feed to show
    final posts = showFollowing ? followingPosts : latestPosts;
    final hasMore = showFollowing ? hasMoreFollowing : hasMoreLatest;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // --- Tabs ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _tabButton('Latest', !showFollowing, () => _switchTab(false)),
                const SizedBox(width: 12),
                _tabButton('Following', showFollowing, () => _switchTab(true)),
              ],
            ),
          ),

          // Expanded(
          //   child: RefreshIndicator(
          //     color: Colors.black,
          //     onRefresh: () => fetchPosts(refresh: true),
          //     child: ListView.builder(
          //       itemCount: posts.length,
          //       itemBuilder: (context, index) {
          //         return PostCard(
          //           key: ValueKey(posts[index]['id']),
          //           post: posts[index],
          //           onTapProfile: () {},
          //           onLikeChanged: (isLiked) {
          //             setState(() {
          //               final p = posts[index];
          //               final current = p['likes_count'] ?? 0;

          //               p['is_liked'] = isLiked;
          //               p['likes_count'] = isLiked
          //                   ? current + 1
          //                   : (current - 1).clamp(0, 9999999);
          //             });
          //           },
          //         );
          //       },
          //     ),
          //   ),
          // ),
          // --- Feed ---
          Expanded(
            child: RefreshIndicator(
              color: Colors.black,
              onRefresh: () => fetchPosts(refresh: true),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: posts.length + (hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == posts.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  return PostCard(
                    key: ValueKey(posts[index]['id']), // helps element reuse
                    post: posts[index],
                    onTapProfile: () {
                      // Navigate to profile screen
                      // Navigator.pushNamed(
                      //   context,
                      //   '/view-profile',
                      //   arguments: {
                      //     'userId': posts[index]['user']['id'],
                      //     'username': posts[index]['user']['username'],
                      //   },
                      // );
                    },
                    onLikeChanged: (isLiked) {
                      setState(() {
                        final p = posts[index];
                        final current = p['likes_count'] ?? 0;

                        p['is_liked'] = isLiked;
                        p['likes_count'] = isLiked
                            ? current + 1
                            : (current - 1).clamp(0, 9999999);
                      });
                    },
                  );
                },
              ),
            ),
          ),
          // --- Feed ---
        ],
      ),
    );
  }

  Widget _tabButton(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFD5B56B) : Colors.grey[200],
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
