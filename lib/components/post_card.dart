import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinch_zoom_release_unzoom/pinch_zoom_release_unzoom.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api/interactions_api.dart';
import '../screens/comments_bottom_sheet.dart';
import '../widgets/feed_video_player.dart';
import '../widgets/profile/profile_avatar.dart';

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTapProfile;
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
  int _likesCount = 0;
  bool _allowSwipe = true;
  bool _showHeart = false;

  @override
  void initState() {
    super.initState();

    _liked = widget.post['is_liked'] ?? false;
    _likesCount = (widget.post['likes_count'] ?? 0) as int;

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
  }

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

    if (maxHeight == 0) {
      maxHeight = screenW;
    }

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
    // Preload next image
    if (index + 1 < media.length) {
      final next = media[index + 1];
      if (next['media_type'] == 'image') {
        try {
          // Preload both blurred and full resolution
          if (next['blurred_url'] != null && next['blurred_url'].isNotEmpty) {
            CachedNetworkImageProvider(
              next['blurred_url'],
            ).resolve(ImageConfiguration());
          }
          if (next['media_url'] != null && next['media_url'].isNotEmpty) {
            CachedNetworkImageProvider(
              next['media_url'],
            ).resolve(ImageConfiguration());
          }
        } catch (e) {
          print('⚠️ Preload error (next): $e');
        }
      }
    }

    // Preload previous image
    if (index - 1 >= 0) {
      final prev = media[index - 1];
      if (prev['media_type'] == 'image') {
        try {
          if (prev['blurred_url'] != null && prev['blurred_url'].isNotEmpty) {
            CachedNetworkImageProvider(
              prev['blurred_url'],
            ).resolve(ImageConfiguration());
          }
          if (prev['media_url'] != null && prev['media_url'].isNotEmpty) {
            CachedNetworkImageProvider(
              prev['media_url'],
            ).resolve(ImageConfiguration());
          }
        } catch (e) {
          print('⚠️ Preload error (prev): $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    final media = (widget.post['media'] ?? []) as List<dynamic>;
    final hasMedia = media.isNotEmpty;
    final maxMediaHeight = hasMedia ? _calculateMaxHeight(context, media) : 0.0;

    return RepaintBoundary(
      child: Card(
        color: Colors.white,
        margin: EdgeInsets.zero,
        elevation: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----- Header -----
            ListTile(
              leading: ProfileAvatar(
                imageUrl: widget.post['user_profile_image'],
                onTap: widget.onTapProfile,
              ),
              title: GestureDetector(
                onTap: widget.onTapProfile,
                child: Row(
                  children: [
                    Text(
                      widget.post['username'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    if (widget.post['user_verified'] == true) ...[
                      SizedBox(width: 4),
                      Icon(
                        Icons.verified,
                        size: 16,
                        color: theme.primaryColor,
                      ), // ✅ After name
                    ],
                  ],
                ),
              ),
              subtitle: Text(
                formatPostDate(widget.post['post_date']),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),

            // ----- Media -----
            if (hasMedia)
              GestureDetector(
                onDoubleTap: _handleDoubleTap,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: maxMediaHeight,
                      child: PageView.builder(
                        physics: _allowSwipe
                            ? const PageScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                        itemCount: media.length,
                        onPageChanged: (i) {
                          if (!mounted) return;
                          setState(() => _currentPage = i);
                          _preloadMedia(media, i);
                        },
                        itemBuilder: (context, i) {
                          final item = media[i];
                          final isVideo = item['media_type'] == 'video';

                          final screenW = MediaQuery.of(context).size.width;
                          final imgW = _parseDouble(item['media_width']);
                          final imgH = _parseDouble(item['media_height']);
                          final aspect = (imgW > 0 && imgH > 0)
                              ? imgW / imgH
                              : 1.0;

                          final naturalH = screenW / aspect;
                          final itemHeight = naturalH > maxMediaHeight
                              ? maxMediaHeight
                              : naturalH;
                          final blurredUrl = item['blurred_url'];
                          final mediaUrl = item['media_url'];

                          // ✅ Validate media URL to prevent crashes
                          if (mediaUrl == null || mediaUrl.isEmpty) {
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
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              // ✅ Layer 1: Gray background (no more white flash)
                              Container(color: Colors.grey.shade200),

                              // ✅ Layer 2: Blurred background (loads instantly)
                              if (blurredUrl != null && blurredUrl.isNotEmpty)
                                Positioned.fill(
                                  child: CachedNetworkImage(
                                    imageUrl: blurredUrl,
                                    fit: BoxFit.cover,
                                    fadeInDuration: Duration.zero,
                                    fadeOutDuration: Duration.zero,
                                    errorWidget: (_, __, ___) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),

                              // ✅ Layer 3: Main content with download progress
                              Center(
                                child: SizedBox(
                                  width: screenW,
                                  height: itemHeight,
                                  child: PinchZoomReleaseUnzoomWidget(
                                    fingersRequiredToPinch: 2,
                                    twoFingersOn: () {
                                      if (!mounted) return;
                                      setState(() => _allowSwipe = false);
                                    },
                                    twoFingersOff: () => Future.delayed(
                                      PinchZoomReleaseUnzoomWidget
                                          .defaultResetDuration,
                                      () {
                                        if (mounted) {
                                          setState(() => _allowSwipe = true);
                                        }
                                      },
                                    ),
                                    child: isVideo
                                        ? FeedVideoPlayer(
                                            url: mediaUrl,
                                            isActive: _currentPage == i,
                                            fit: BoxFit.cover,
                                          )
                                        : CachedNetworkImage(
                                            imageUrl: mediaUrl,
                                            fit: BoxFit.contain,
                                            fadeInDuration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            // ✅ Show download progress (Instagram-style)
                                            progressIndicatorBuilder:
                                                (context, url, progress) {
                                                  return Center(
                                                    child: CircularProgressIndicator(
                                                      value: progress
                                                          .progress, // Shows actual download %
                                                      color: Colors.white
                                                          .withOpacity(0.9),
                                                      backgroundColor: Colors
                                                          .white
                                                          .withOpacity(0.2),
                                                      strokeWidth: 3,
                                                    ),
                                                  );
                                                },
                                            // ✅ Show 0% progress if image fails to load (prevents crash)
                                            errorWidget: (context, url, error) {
                                              print(
                                                '❌ Image load error: $error',
                                              );
                                              return Center(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    CircularProgressIndicator(
                                                      value: 0, // 0% progress
                                                      color: Colors.white
                                                          .withOpacity(0.5),
                                                      backgroundColor: Colors
                                                          .white
                                                          .withOpacity(0.1),
                                                      strokeWidth: 3,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'Failed to load',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withOpacity(0.7),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                            // ✅ Add memory cache config to prevent crashes from large images
                                            memCacheHeight: 1000,
                                            memCacheWidth: 1000,
                                            maxHeightDiskCache: 1000,
                                            maxWidthDiskCache: 1000,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    // Heart overlay
                    if (_showHeart)
                      AnimatedBuilder(
                        animation: _heartController,
                        builder: (_, child) {
                          final opacity =
                              (1 - (_heartController.value - 0.7).clamp(0, 1))
                                  .toDouble();
                          return Opacity(
                            opacity: opacity,
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

                    // Page indicators
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

            // ----- Actions -----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
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
                    onTap: _sharePost,
                    child: const Icon(
                      Icons.send_outlined,
                      color: Colors.black,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),

            // ----- Likes -----
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

            // ----- Caption + comments -----
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
          RichText(
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
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        if (caption.isNotEmpty)
          GestureDetector(
            onTap: () {
              if (!mounted) return;
              setState(() => _expanded = !_expanded);
            },
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
