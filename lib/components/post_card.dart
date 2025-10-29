import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../api/interactions_api.dart';
import '../screens/comments_bottom_sheet.dart';
import '../widgets/feed_video_player.dart';

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTapProfile;

  const PostCard({super.key, required this.post, this.onTapProfile});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  int _currentPage = 0;
  bool _liked = false;
  bool _showHeart = false;
  late AnimationController _heartController;

  @override
  void initState() {
    super.initState();
    _liked = widget.post['is_liked'] ?? false;
    _heartController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() async {
    // Only like if not already liked
    if (!_liked) {
      _optimisticLike();
    }

    // Always show the animation (every double-tap)
    setState(() {
      _showHeart = true;
      _heartController.forward(from: 0);
    });

    // Hide animation after a short delay
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) setState(() => _showHeart = false);
  }

  Future<void> _optimisticLike() async {
    final previousLikes = widget.post['likes_count'] ?? 0;

    setState(() {
      _liked = true;
      widget.post['likes_count'] = previousLikes + 1;
    });

    final res = await InteractionsAPI.maybeLikePost(widget.post['id']);

    if (res == null || res['success'] == false) {
      // Rollback if request failed
      if (mounted) {
        setState(() {
          _liked = false;
          widget.post['likes_count'] = previousLikes;
        });
      }
    }
  }

  Future<void> _toggleUnlike() async {
    final previousLikes = widget.post['likes_count'] ?? 0;

    setState(() {
      _liked = false;
      widget.post['likes_count'] = (previousLikes > 0) ? previousLikes - 1 : 0;
    });

    final res = await InteractionsAPI.maybeLikePost(widget.post['id']);

    if (res == null || res['success'] == false) {
      // Rollback if failed
      if (mounted) {
        setState(() {
          _liked = true;
          widget.post['likes_count'] = previousLikes;
        });
      }
    }
  }

  Future<void> _sharePost() async {
    final postId = widget.post['id'];
    final postUser = widget.post['username'] ?? 'DriveLifeUser';
    final postDescription = widget.post['caption'] ?? 'DriveLife post';
    final postUrl = 'https://app.mydrivelife.com?dl-postv=$postId&ref=share';

    final shareText =
        'Check out this post on DriveLife by @$postUser.\n\n$postDescription\n\n$postUrl';

    try {
      await Share.share(shareText, subject: postDescription);

      // Optionally notify backend (like your onPostShared)
      await InteractionsAPI.markPostShared(postId);
    } catch (e) {
      debugPrint('Error sharing post: $e');
    }
  }

  String formatPostDate(String dateStr) {
    final DateTime postDate = DateTime.parse(dateStr);
    final Duration diff = DateTime.now().difference(postDate);

    if (diff.inDays >= 30) {
      final months = (diff.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    } else if (diff.inDays >= 7) {
      final weeks = (diff.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else if (diff.inDays >= 1) {
      return diff.inDays == 1 ? '1 day ago' : '${diff.inDays} days ago';
    } else if (diff.inHours >= 1) {
      return diff.inHours == 1 ? '1 hour ago' : '${diff.inHours} hours ago';
    } else if (diff.inMinutes >= 1) {
      return diff.inMinutes == 1
          ? '1 minute ago'
          : '${diff.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }

  void _openComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => CommentsBottomSheet(
          scrollController: scrollController,
          postId: widget.post['id'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = (widget.post['media'] ?? []) as List<dynamic>;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      color: Colors.white,
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          ListTile(
            leading: GestureDetector(
              onTap: widget.onTapProfile,
              child: CircleAvatar(
                backgroundImage: NetworkImage(
                  widget.post['user_profile_image'] ?? '',
                ),
              ),
            ),
            title: Text(
              widget.post['username'] ?? '',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              formatPostDate(widget.post['post_date'] ?? 'N/A'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),

          // Media Carousel + Double Tap
          if (media.isNotEmpty)
            GestureDetector(
              onDoubleTap: _handleDoubleTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: PageView.builder(
                      itemCount: media.length,
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      itemBuilder: (context, i) {
                        final item = media[i];
                        final url = item['media_url'];
                        final maxHeight =
                            MediaQuery.of(context).size.height *
                            0.65; // ~65% screen

                        if (url.endsWith('.mp4')) {
                          // return FeedVideoPlayer(
                          //   url: url,
                          //   isActive: _currentPage == i,
                          // );
                          return Container(
                            constraints: BoxConstraints(maxHeight: maxHeight),
                            color: Colors.black,
                            child: FeedVideoPlayer(
                              url: url,
                              isActive: _currentPage == i,
                              fit: BoxFit.cover, // ✅ center crop video
                              alignment: Alignment.center,
                            ),
                          );
                        }

                        // return Image.network(url, fit: BoxFit.cover);
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(0),
                          child: FadeInImage(
                            placeholder: NetworkImage(
                              item['blurred_url'] ?? item['media_url'],
                            ),
                            image: NetworkImage(item['media_url']),
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 300),
                          ),
                        );
                      },
                    ),
                  ),
                  // Heart animation overlay
                  if (_showHeart)
                    AnimatedOpacity(
                      opacity: 1,
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.easeOut,
                      child: AnimatedBuilder(
                        animation: _heartController,
                        builder: (context, child) {
                          final scale = TweenSequence<double>([
                            // Pop up quickly
                            TweenSequenceItem(
                              tween: Tween(
                                begin: 0.8,
                                end: 1.3,
                              ).chain(CurveTween(curve: Curves.easeOutCubic)),
                              weight: 25,
                            ),
                            // Gentle bounce down
                            TweenSequenceItem(
                              tween: Tween(
                                begin: 1.3,
                                end: 1.15,
                              ).chain(CurveTween(curve: Curves.easeInOut)),
                              weight: 25,
                            ),
                            // Soft rebound
                            TweenSequenceItem(
                              tween: Tween(
                                begin: 1.15,
                                end: 1.25,
                              ).chain(CurveTween(curve: Curves.easeOutBack)),
                              weight: 25,
                            ),
                            // Settle back
                            TweenSequenceItem(
                              tween: Tween(
                                begin: 1.25,
                                end: 1.0,
                              ).chain(CurveTween(curve: Curves.easeIn)),
                              weight: 25,
                            ),
                          ]).evaluate(_heartController);

                          final rotation = TweenSequence<double>([
                            TweenSequenceItem(
                              tween: Tween(begin: -0.02, end: 0.02),
                              weight: 50,
                            ),
                            TweenSequenceItem(
                              tween: Tween(begin: 0.02, end: 0.0),
                              weight: 50,
                            ),
                          ]).evaluate(_heartController);

                          return Transform.rotate(
                            angle: rotation,
                            child: Transform.scale(
                              scale: scale,
                              child: const Icon(
                                Icons.favorite,
                                color: Colors.white,
                                size: 90,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  // Page indicators
                  if (media.length > 1)
                    Positioned(
                      bottom: 8,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          media.length,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3.0),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _currentPage == index
                                  ? Colors.white
                                  : Colors.white54,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _liked ? _toggleUnlike : _optimisticLike,
                  child: Icon(
                    _liked ? Icons.favorite : Icons.favorite_border,
                    color: _liked ? Colors.red : Colors.black,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => _openComments(context),
                  child: const Icon(
                    Icons.mode_comment_outlined,
                    color: Colors.black,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => _sharePost(),
                  child: const Icon(
                    Icons.send_outlined,
                    color: Colors.black,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),

          // Likes and caption
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${widget.post['likes_count']} likes',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _PostCaptionSection(
              username: widget.post['username'] ?? '',
              caption: widget.post['caption'] ?? '',
              commentsCount: widget.post['comments_count'] ?? 0,
              onViewComments: () => _openComments(context),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PostCaptionSection extends StatefulWidget {
  final String username;
  final String caption;
  final int commentsCount;
  final VoidCallback onViewComments;

  const _PostCaptionSection({
    required this.username,
    required this.caption,
    required this.commentsCount,
    required this.onViewComments,
  });

  @override
  State<_PostCaptionSection> createState() => _PostCaptionSectionState();
}

class _PostCaptionSectionState extends State<_PostCaptionSection> {
  bool _expanded = false;
  static const int _maxLines = 2;

  @override
  Widget build(BuildContext context) {
    final username = widget.username;
    final caption = widget.caption.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Username (own line)
        GestureDetector(
          onTap: () {
            // TODO: Navigate to user profile (optional)
          },
          child: Text(
            username,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 4),

        // Caption (collapsible)
        if (caption.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final tp = TextPainter(
                text: TextSpan(
                  text: caption,
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                ),
                textDirection: TextDirection.ltr,
                maxLines: _maxLines,
              )..layout(maxWidth: constraints.maxWidth);

              final isOverflowing = tp.didExceedMaxLines;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption,
                    style: const TextStyle(color: Colors.black87, fontSize: 14),
                    maxLines: _expanded ? null : _maxLines,
                    overflow: _expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  ),
                  if (isOverflowing)
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _expanded ? 'Show less' : 'Show more',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

        const SizedBox(height: 6),

        // View comments link
        if (widget.commentsCount > 0)
          GestureDetector(
            onTap: widget.onViewComments,
            child: Text(
              'View ${widget.commentsCount} comment${widget.commentsCount == 1 ? '' : 's'}',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}
