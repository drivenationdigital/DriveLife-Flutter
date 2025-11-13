import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinch_zoom_release_unzoom/pinch_zoom_release_unzoom.dart';
import 'package:share_plus/share_plus.dart';
import '../api/interactions_api.dart';
import '../screens/comments_bottom_sheet.dart';
import '../widgets/feed_video_player.dart';

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTapProfile;

  /// Notify parent so it can persist to posts[index]
  final ValueChanged<bool>? onLikeChanged;

  const PostCard({
    super.key,
    required this.post,
    this.onTapProfile,
    this.onLikeChanged,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartController;
  late Animation<double> _heartScale;

  int _currentPage = 0;
  bool _liked = false;
  bool _allowSwipe = true;
  bool _showHeart = false;
  double _currentMediaHeight = 300; // default temporary height

  @override
  void initState() {
    super.initState();

    _liked = widget.post['is_liked'] ?? false;

    _heartController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _heartScale = TweenSequence([
      // Pop out fast
      TweenSequenceItem(
        tween: Tween(
          begin: 0.2,
          end: 1.4,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 40,
      ),
      // Squish down a bit
      TweenSequenceItem(
        tween: Tween(
          begin: 1.4,
          end: 0.9,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      // Bounce to final size
      TweenSequenceItem(
        tween: Tween(
          begin: 0.9,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
    ]).animate(_heartController);
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final updatedLiked = widget.post['is_liked'] ?? false;
    if (updatedLiked != _liked) {
      setState(() => _liked = updatedLiked);
    }
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() async {
    if (!_liked) _optimisticLike();

    setState(() => _showHeart = true);

    _heartController.forward(from: 0);

    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _showHeart = false);
  }

  Future<void> _optimisticLike() async {
    // UI feedback immediately
    setState(() => _liked = true);
    widget.onLikeChanged?.call(true);

    final res = await InteractionsAPI.maybeLikePost(widget.post['id']);

    if (res == null) {
      if (!mounted) return;
      // revert
      setState(() => _liked = false);
      widget.onLikeChanged?.call(false);
    }
  }

  Future<void> _toggleUnlike() async {
    if (!_liked) return;

    setState(() => _liked = false);
    widget.onLikeChanged?.call(false);

    final res = await InteractionsAPI.maybeLikePost(widget.post['id']);
    if (res == null) {
      if (!mounted) return;
      // revert
      setState(() => _liked = true);
      widget.onLikeChanged?.call(true);
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
      await InteractionsAPI.markPostShared(postId);
    } catch (e) {
      debugPrint('Error sharing post: $e');
    }
  }

  String formatPostDate(String dateStr) {
    try {
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
    } catch (_) {
      return '';
    }
  }

  double _controllerAspectOrFallback(Map<String, dynamic> mediaItem) {
    try {
      // If FeedVideoPlayer stored its controller, use it — but since we don’t expose it,
      // we fallback to metadata if provided.
      final w =
          double.tryParse(mediaItem['media_width']?.toString() ?? '') ?? 1;
      final h =
          double.tryParse(mediaItem['media_height']?.toString() ?? '') ?? 1;
      if (w > 0 && h > 0) return w / h;
    } catch (_) {}

    // Fallback to square
    return 1.0;
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

  // --- Media helpers ---
  double _parseDouble(dynamic v, {double fallback = 1}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  /// Returns a bounded height for media (~65% of screen).
  double _maxFeedHeight(BuildContext context) =>
      MediaQuery.of(context).size.height * 0.65;

  @override
  Widget build(BuildContext context) {
    final media = (widget.post['media'] ?? []) as List<dynamic>;

    return Card(
      color: Colors.white,
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Header
          ListTile(
            leading: GestureDetector(
              onTap: () => widget.onTapProfile?.call(),
              child: CircleAvatar(
                backgroundImage: NetworkImage(
                  widget.post['user_profile_image'] ?? '',
                ),
              ),
            ),
            title: GestureDetector(
              onTap: () => widget.onTapProfile?.call(),
              child: Text(
                widget.post['username'] ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
            subtitle: Text(
              formatPostDate(widget.post['post_date']),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),

          /// Media (Images / Videos)
          if (media.isNotEmpty)
            GestureDetector(
              onDoubleTap: _handleDoubleTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  /// MAIN MEDIA (the PageView)
                  SizedBox(
                    width: double.infinity,
                    height: _currentMediaHeight,
                    child: PageView.builder(
                      physics: _allowSwipe
                          ? const PageScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: media.length,
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      itemBuilder: (context, i) {
                        final item = media[i];
                        final isVideo = item['media_type'] == 'video';

                        final screenW = MediaQuery.of(context).size.width;
                        final screenH = MediaQuery.of(context).size.height;

                        final imgW = _parseDouble(item['media_width']);
                        final imgH = _parseDouble(item['media_height']);
                        final aspect = (imgW > 0 && imgH > 0)
                            ? imgW / imgH
                            : 1.0;

                        final isWide = aspect > 1.3; // horizontal video

                        double naturalHeight = screenW / aspect;
                        double maxHeight = screenH * 0.65;
                        double displayHeight = naturalHeight > maxHeight
                            ? maxHeight
                            : naturalHeight;

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_currentMediaHeight != displayHeight) {
                            setState(() => _currentMediaHeight = displayHeight);
                          }
                        });

                        return PinchZoomReleaseUnzoomWidget(
                          fingersRequiredToPinch: 2,
                          twoFingersOn: () =>
                              setState(() => _allowSwipe = false),
                          twoFingersOff: () => Future.delayed(
                            PinchZoomReleaseUnzoomWidget.defaultResetDuration,
                            () => setState(() => _allowSwipe = true),
                          ),
                          child: isVideo
                              ? FeedVideoPlayer(
                                  url: item['media_url'],
                                  isActive: _currentPage == i,
                                  fit: isWide ? BoxFit.contain : BoxFit.cover,
                                )
                              : Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      item['blurred_url'],
                                      fit: BoxFit.cover,
                                    ),
                                    CachedNetworkImage(
                                      imageUrl: item['media_url'],
                                      fit: naturalHeight > maxHeight
                                          ? BoxFit.cover
                                          : BoxFit.fitWidth,
                                      alignment: Alignment.center,
                                      fadeInDuration: const Duration(
                                        milliseconds: 250,
                                      ),
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
                  ),

                  /// HEART OVERLAY
                  if (_showHeart)
                    AnimatedBuilder(
                      animation: _heartController,
                      builder: (_, child) {
                        return Opacity(
                          opacity:
                              (1 - (_heartController.value - 0.7).clamp(0, 1)),
                          child: Transform.scale(
                            scale: _heartScale.value,
                            child: child,
                          ),
                        );
                      },
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 110,
                      ),
                    ),

                  /// SWIPE DOTS
                  if (media.length > 1)
                    Positioned(
                      bottom: 12,
                      child: Row(
                        children: List.generate(
                          media.length,
                          (i) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _currentPage == i
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

          /// Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick(); // subtle tap
                    _liked ? _toggleUnlike() : _optimisticLike();
                  },
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
                  onTap: () =>
                      Share.share(widget.post['media'][0]['media_url']),
                  child: const Icon(
                    Icons.send_outlined,
                    color: Colors.black,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),

          /// Likes
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

          // Caption + comments
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: _PostCaptionSection(
              username: widget.post['username'] ?? '',
              caption: widget.post['caption'] ?? '',
              commentsCount: widget.post['comments_count'] ?? 0,
              onViewComments: () => _openComments(context),
            ),
          ),
          const SizedBox(height: 10),
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
        if (caption.isNotEmpty)
          GestureDetector(
            onTap: () {
              // TODO: go to profile
            },
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: username,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const TextSpan(text: "  "),
                  TextSpan(
                    text: caption,
                    style: const TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ],
              ),
              maxLines: _expanded ? null : _maxLines,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
          ),
        if (caption.isNotEmpty)
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

        const SizedBox(height: 6),

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
