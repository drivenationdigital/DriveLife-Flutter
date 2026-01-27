import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/widgets/formatted_text.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinch_zoom_release_unzoom/pinch_zoom_release_unzoom.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api/interactions_api.dart';
import '../screens/comments_bottom_sheet.dart';
import '../widgets/feed/feed_video_player.dart';
import '../widgets/profile/profile_avatar.dart';

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTapProfile;
  final ValueChanged<bool>? onLikeChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const PostCard({
    super.key,
    required this.post,
    this.onTapProfile,
    this.onLikeChanged,
    this.onDelete,
    this.onEdit,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  // @override
  // bool get wantKeepAlive => true; // ✅ Keep state alive during scrolling

  late AnimationController _heartController;
  late Animation<double> _heartScale;

  // Cache computed values
  late final String _formattedDate;
  late final List<dynamic> _media;
  late final double _maxMediaHeight;
  late final bool _hasMedia;

  int _currentPage = 0;
  bool _liked = false;
  int _likesCount = 0;
  bool _allowSwipe = true;
  bool _showHeart = false;

  @override
  void initState() {
    super.initState();

    _liked = widget.post['is_liked'] ?? false;
    _likesCount = (widget.post['likes_count'] ?? 0) as int;

    // ✅ Cache values that don't change
    _formattedDate = _formatPostDate(widget.post['post_date']);
    _media = (widget.post['media'] ?? []) as List<dynamic>;
    _hasMedia = _media.isNotEmpty;

    _heartController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    _heartScale = TweenSequence([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.2,
          end: 1.4,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.4,
          end: 0.9,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.9,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
    ]).animate(_heartController);

    // ✅ Preload first media item
    if (_hasMedia) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _preloadMedia(_media, 0);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // ✅ Calculate height only once when dependencies are available
    if (_hasMedia && !_heightCalculated) {
      _maxMediaHeight = _calculateMaxHeight(context, _media);
      _heightCalculated = true;
    }
  }

  bool _heightCalculated = false;
  // double _maxMediaHeight = 0.0;

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final updatedLiked = widget.post['is_liked'] ?? _liked;
    final updatedLikesCount =
        (widget.post['likes_count'] ?? _likesCount) as int;

    if (updatedLiked != _liked || updatedLikesCount != _likesCount) {
      if (mounted) {
        setState(() {
          _liked = updatedLiked;
          _likesCount = updatedLikesCount;
        });
      }
    }
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  // ✅ Static method - no need to rebuild
  static String _formatPostDate(String? dateStr) {
    if (dateStr == null) return '';

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

  double _parseDouble(dynamic v, {double fallback = 1}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  double _calculateMaxHeight(BuildContext context, List<dynamic> media) {
    if (media.isEmpty) return 0;

    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final maxContainerH = screenH * 0.65;

    double maxHeight = 0;

    for (final item in media) {
      final imgW = _parseDouble(item['media_width']);
      final imgH = _parseDouble(item['media_height']);
      final aspect = (imgW > 0 && imgH > 0) ? imgW / imgH : 1.0;

      final naturalHeight = screenW / aspect;
      final displayHeight = naturalHeight > maxContainerH
          ? maxContainerH
          : naturalHeight;

      if (displayHeight > maxHeight) maxHeight = displayHeight;
    }

    if (maxHeight == 0) maxHeight = screenW;

    return maxHeight;
  }

  Future<void> _optimisticLike() async {
    if (_liked || !mounted) return;

    setState(() {
      _liked = true;
      _likesCount += 1;
    });
    widget.onLikeChanged?.call(true);

    final res = await InteractionsAPI.maybeLikePost(widget.post['id']);

    if (!mounted) return;

    if (res == null) {
      setState(() {
        _liked = false;
        _likesCount = (_likesCount - 1).clamp(0, 9999999);
      });
      widget.onLikeChanged?.call(false);
    }
  }

  Future<void> _toggleUnlike() async {
    if (!_liked || !mounted) return;

    setState(() {
      _liked = false;
      _likesCount = (_likesCount - 1).clamp(0, 9999999);
    });
    widget.onLikeChanged?.call(false);

    final res = await InteractionsAPI.maybeLikePost(widget.post['id']);

    if (!mounted) return;

    if (res == null) {
      setState(() {
        _liked = true;
        _likesCount += 1;
      });
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

  Future<void> _handleDoubleTap() async {
    if (!_liked) {
      await _optimisticLike();
    }

    if (!mounted) return;

    setState(() => _showHeart = true);
    _heartController.forward(from: 0);

    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      setState(() => _showHeart = false);
    }
  }

  void _preloadMedia(List media, int index) {
    // ✅ Only preload next image (not previous to reduce memory)
    if (index + 1 < media.length) {
      final next = media[index + 1];
      if (next['media_type'] == 'image') {
        final nextUrl = next['media_url'];
        if (nextUrl != null && nextUrl.isNotEmpty) {
          precacheImage(CachedNetworkImageProvider(nextUrl), context);
        }
      }
    }
  }

  void _showPostOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.black),
              title: const Text('Edit Post'),
              onTap: () {
                Navigator.pop(context);
                widget.onEdit?.call();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete Post',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmDeletePost();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeletePost() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePost();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePost() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );
      }

      final success = await PostsAPI.deletePost(
        postId: widget.post['id'].toString(),
        userId: user['id'].toString(),
      );

      if (!mounted) return;

      Navigator.pop(context);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onDelete?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete post'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // super.build(context); // ✅ Required for AutomaticKeepAliveClientMixin

    // ✅ Get providers once, use listen: false
    final theme = Provider.of<ThemeProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;

    return Card(
      color: Colors.white,
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Header - Wrapped in RepaintBoundary
          RepaintBoundary(
            child: _PostHeader(
              profileImage: widget.post['user_profile_image'],
              username: widget.post['username'] ?? '',
              isVerified: widget.post['user_verified'] == true,
              date: _formattedDate,
              currentUserId: user?['id'],
              postUserId: widget.post['user_id'],
              onTapProfile: widget.onTapProfile,
              onSettings: _showPostOptions,
              primaryColor: theme.primaryColor,
            ),
          ),

          // ✅ Media - Wrapped in RepaintBoundary
          if (_hasMedia)
            RepaintBoundary(
              child: _MediaCarousel(
                media: _media,
                maxHeight: _maxMediaHeight,
                currentPage: _currentPage,
                allowSwipe: _allowSwipe,
                showHeart: _showHeart,
                heartAnimation: _heartScale,
                heartController: _heartController,
                onPageChanged: (i) {
                  if (!mounted) return;
                  setState(() => _currentPage = i);
                  _preloadMedia(_media, i);
                },
                onDoubleTap: _handleDoubleTap,
                onSwipeChanged: (allow) {
                  if (mounted) setState(() => _allowSwipe = allow);
                },
              ),
            ),

          // ✅ Actions - Wrapped in RepaintBoundary
          RepaintBoundary(
            child: _PostActions(
              liked: _liked,
              onLikeTap: () {
                HapticFeedback.selectionClick();
                _liked ? _toggleUnlike() : _optimisticLike();
              },
              onCommentTap: () => _openComments(context),
              onShareTap: _sharePost,
            ),
          ),

          // ✅ Likes count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '$_likesCount likes',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),

          // ✅ Caption - Wrapped in RepaintBoundary
          RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: _PostCaptionSection(
                username: widget.post['username'] ?? '',
                caption: widget.post['caption'] ?? '',
                commentsCount: widget.post['comments_count'] ?? 0,
                onViewComments: () => _openComments(context),
              ),
            ),
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// ✅ Extracted header as stateless widget
class _PostHeader extends StatelessWidget {
  final String? profileImage;
  final String username;
  final bool isVerified;
  final String date;
  final dynamic currentUserId;
  final dynamic postUserId;
  final VoidCallback? onTapProfile;
  final VoidCallback onSettings;
  final Color primaryColor;

  const _PostHeader({
    required this.profileImage,
    required this.username,
    required this.isVerified,
    required this.date,
    required this.currentUserId,
    required this.postUserId,
    required this.onTapProfile,
    required this.onSettings,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final isOwnPost = postUserId.toString() == currentUserId.toString();

    return ListTile(
      leading: ProfileAvatar(imageUrl: profileImage, onTap: onTapProfile),
      title: GestureDetector(
        onTap: onTapProfile,
        child: Row(
          children: [
            Text(
              username,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            if (isVerified) ...[
              const SizedBox(width: 4),
              Icon(Icons.verified, size: 16, color: primaryColor),
            ],
          ],
        ),
      ),
      subtitle: Text(
        date,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: isOwnPost
          ? GestureDetector(
              onTap: onSettings,
              child: const Icon(Icons.more_vert, color: Colors.black, size: 24),
            )
          : null,
    );
  }
}

// ✅ Extracted media carousel as stateless widget
class _MediaCarousel extends StatelessWidget {
  final List<dynamic> media;
  final double maxHeight;
  final int currentPage;
  final bool allowSwipe;
  final bool showHeart;
  final Animation<double> heartAnimation;
  final AnimationController heartController;
  final Function(int) onPageChanged;
  final VoidCallback onDoubleTap;
  final Function(bool) onSwipeChanged;

  const _MediaCarousel({
    required this.media,
    required this.maxHeight,
    required this.currentPage,
    required this.allowSwipe,
    required this.showHeart,
    required this.heartAnimation,
    required this.heartController,
    required this.onPageChanged,
    required this.onDoubleTap,
    required this.onSwipeChanged,
  });

  double _parseDouble(dynamic v, {double fallback = 1}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  void _showTagsBottomSheet(BuildContext context, List<dynamic> tags) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Tagged',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ...tags.map((tag) {
              final entity = tag['entity'];
              final type = tag['type'];
              final name = entity['name'] ?? 'Unknown';
              final image = entity['image'];

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: image != null ? NetworkImage(image) : null,
                  child: image == null
                      ? Icon(
                          type == 'car' ? Icons.directions_car : Icons.person,
                        )
                      : null,
                ),
                title: Text(name),
                subtitle: Text(type == 'car' ? 'Vehicle' : 'User'),
                onTap: () {
                  Navigator.pop(context);
                  if (type == 'user') {
                    Navigator.pushNamed(
                      context,
                      '/view-profile',
                      arguments: {'userId': entity['id']},
                    );
                  } else if (type == 'car') {
                    Navigator.pushNamed(
                      context,
                      '/vehicle-detail',
                      arguments: {'garageId': entity['id']},
                    );
                  }
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            height: maxHeight,
            child: PageView.builder(
              physics: allowSwipe
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: media.length,
              onPageChanged: onPageChanged,
              itemBuilder: (context, i) {
                final item = media[i];
                final isVideo = item['media_type'] == 'video';
                final mediaUrl = item['media_url'];
                final blurredUrl = item['blurred_url'];

                if (mediaUrl == null || mediaUrl.isEmpty) {
                  return _buildErrorPlaceholder();
                }

                final screenW = MediaQuery.of(context).size.width;
                final imgW = _parseDouble(item['media_width']);
                final imgH = _parseDouble(item['media_height']);
                final aspect = (imgW > 0 && imgH > 0) ? imgW / imgH : 1.0;
                final naturalH = screenW / aspect;
                final itemHeight = naturalH > maxHeight ? maxHeight : naturalH;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.grey.shade200),

                    if (blurredUrl != null && blurredUrl.isNotEmpty)
                      Positioned.fill(
                        child: CachedNetworkImage(
                          imageUrl: blurredUrl,
                          fit: BoxFit.cover,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),

                    Center(
                      child: SizedBox(
                        width: screenW,
                        height: itemHeight,
                        child: PinchZoomReleaseUnzoomWidget(
                          fingersRequiredToPinch: 2,
                          twoFingersOn: () => onSwipeChanged(false),
                          twoFingersOff: () => Future.delayed(
                            PinchZoomReleaseUnzoomWidget.defaultResetDuration,
                            () => onSwipeChanged(true),
                          ),
                          child: isVideo
                              ? FeedVideoPlayer(
                                  url: mediaUrl,
                                  isActive: currentPage == i,
                                  fit: BoxFit.cover,
                                )
                              : CachedNetworkImage(
                                  imageUrl: mediaUrl,
                                  fit: BoxFit.contain,
                                  fadeInDuration: const Duration(
                                    milliseconds: 300,
                                  ),
                                  progressIndicatorBuilder:
                                      (context, url, progress) {
                                        return Center(
                                          child: CircularProgressIndicator(
                                            value: progress.progress,
                                            color: Colors.white.withOpacity(
                                              0.9,
                                            ),
                                            backgroundColor: Colors.white
                                                .withOpacity(0.2),
                                            strokeWidth: 3,
                                          ),
                                        );
                                      },
                                  errorWidget: (context, url, error) =>
                                      _buildErrorPlaceholder(),
                                  memCacheHeight: 1000,
                                  memCacheWidth: 1000,
                                  maxHeightDiskCache: 1000,
                                  maxWidthDiskCache: 1000,
                                ),
                        ),
                      ),
                    ),

                    if (item['tags'] != null &&
                        (item['tags'] as List).isNotEmpty)
                      _MediaTags(
                        tags: item['tags'] as List,
                        onTap: () =>
                            _showTagsBottomSheet(context, item['tags'] as List),
                      ),
                  ],
                );
              },
            ),
          ),

          if (showHeart)
            AnimatedBuilder(
              animation: heartController,
              builder: (_, child) {
                final opacity = (1 - (heartController.value - 0.7).clamp(0, 1))
                    .toDouble();
                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: heartAnimation.value,
                    child: child,
                  ),
                );
              },
              child: const Icon(Icons.favorite, color: Colors.white, size: 110),
            ),

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
                      color: currentPage == i ? Colors.white : Colors.white54,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              'Media unavailable',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ✅ Extracted actions as stateless widget
class _PostActions extends StatelessWidget {
  final bool liked;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;
  final VoidCallback onShareTap;

  const _PostActions({
    required this.liked,
    required this.onLikeTap,
    required this.onCommentTap,
    required this.onShareTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: onLikeTap,
            child: SvgPicture.asset(
              liked ? 'assets/svgs/heart_full.svg' : 'assets/svgs/heart.svg',
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                liked ? Colors.red : Colors.black,
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: onCommentTap,
            child: const Icon(
              Icons.mode_comment_outlined,
              color: Colors.black,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: onShareTap,
            child: const Icon(
              Icons.send_outlined,
              color: Colors.black,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

// Caption section remains the same
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
  bool _showFullCaption = false;

  @override
  Widget build(BuildContext context) {
    final username = widget.username;
    final caption = widget.caption.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          username,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 4),
          FormattedText(
            text: caption,
            showAllText: _showFullCaption,
            maxTextLength: 100,
            onSuffixPressed: () {
              setState(() => _showFullCaption = !_showFullCaption);
            },
            suffix: _showFullCaption ? 'Show less' : 'Show more',
            onUserTagPressed: (userId) {
              Navigator.pushNamed(
                context,
                '/view-profile',
                arguments: {'userId': userId},
              );
            },
          ),
        ],
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

class _MediaTags extends StatelessWidget {
  final List<dynamic> tags;
  final VoidCallback? onTap;

  const _MediaTags({required this.tags, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 12,
      bottom: 12,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_offer_outlined,
                color: Colors.white,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                '${tags.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
