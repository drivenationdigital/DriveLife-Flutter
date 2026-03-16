import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/components/news_blog.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/create-post/edit_post_screen.dart';
import 'package:drivelife/screens/hashtag_posts_screen.dart';
import 'package:drivelife/widgets/feed/likes_modal.dart';
import 'package:drivelife/widgets/formatted_text.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinch_zoom_release_unzoom/pinch_zoom_release_unzoom.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
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
  final bool? openCommentsOnLoad; // New parameter to open comments immediately

  const PostCard({
    super.key,
    required this.post,
    this.onTapProfile,
    this.onLikeChanged,
    this.onDelete,
    this.onEdit,
    this.openCommentsOnLoad = false,
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

    if (widget.post['is_event'] == true) {
      _formattedDate = 'Featured';
    } else {
      // ✅ Cache values that don't change
      _formattedDate = _formatPostDate(widget.post['post_date']);
    }

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

    // ✅ Open comments if flag is set
    if (widget.openCommentsOnLoad == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openComments(context);
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

    if (widget.post['is_event'] == true) {
      final success = await EventsAPI.toggleEventLike(
        eventId: widget.post['id'].toString(),
      );

      if (!mounted) return;

      if (!success) {
        setState(() {
          _liked = false;
          _likesCount = (_likesCount - 1).clamp(0, 9999999);
        });
        widget.onLikeChanged?.call(true);
      }
      return; // Skip post like API for events
    }

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

    if (widget.post['is_event'] == true) {
      final success = await EventsAPI.toggleEventLike(
        eventId: widget.post['id'].toString(),
      );

      if (!mounted) return;

      if (!success) {
        setState(() {
          _liked = true;
          _likesCount += 1;
        });
        widget.onLikeChanged?.call(true);
      }
      return; // Skip post like API for events
    }

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

    if (widget.post['is_event'] == true) {
      final eventId = widget.post['id'];
      final eventUrl =
          'https://app.mydrivelife.com?dl-event=$eventId&ref=share';
      final eventText =
          'Check out this event on DriveLife by @$postUser.\n\n$postDescription\n\n$eventUrl';

      try {
        await Share.share(eventText, subject: postDescription);
      } catch (e) {
        debugPrint('Error sharing event: $e');
      }
      return;
    }

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
    HapticFeedback.heavyImpact();
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
    if (!mounted) return;

    // ✅ Only preload next image (not previous to reduce memory)
    if (index + 1 < media.length) {
      final next = media[index + 1];
      if (next['media_type'] == 'image') {
        final nextUrl = next['media_url'];
        if (nextUrl != null && nextUrl.isNotEmpty) {
          precacheImage(
            CachedNetworkImageProvider(nextUrl),
            context,
            onError: (e, stack) {},
          );
        }
      }
    }
  }

  void _showPostOptions() {
    final scaffoldContext = context; // ✅ Store PostCard's context

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
              onTap: () async {
                Navigator.pop(context);
                final response = await Navigator.push(
                  scaffoldContext,
                  MaterialPageRoute(
                    builder: (_) => EditPostScreen(post: widget.post),
                  ),
                );

                if (response == true) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                    const SnackBar(
                      content: Text('Post updated successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  widget.onEdit?.call();
                }
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
      final theme = Provider.of<ThemeProvider>(context, listen: false);
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
          builder: (_) => Center(
            child: CircularProgressIndicator(color: theme.primaryColor),
          ),
        );
      }

      final success = await PostsAPI.deletePost(
        postId: widget.post['id'].toString(),
        userId: user.id.toString(),
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

  // Add this helper wherever you build the post card:
  List<Map<String, dynamic>> _getTaggedUsers() {
    final media = widget.post['media'] as List<dynamic>? ?? [];
    final seen = <String>{};
    final users = <Map<String, dynamic>>[];

    for (final item in media) {
      final tags = item['tags'] as List<dynamic>? ?? [];
      for (final tag in tags) {
        if (tag['type'] == 'user') {
          final entity = tag['entity'] as Map<String, dynamic>?;
          if (entity == null) continue;
          final id = entity['id'].toString();
          if (seen.contains(id)) continue;
          seen.add(id);

          // ↓ Extract username from "Display Name (username)" format
          final fullName = entity['name'] as String? ?? '';
          final usernameMatch = RegExp(r'\(([^)]+)\)').firstMatch(fullName);
          final username =
              entity['username'] ?? usernameMatch?.group(1) ?? fullName;

          users.add({
            'id': entity['id'],
            'name': username, // ← just the username
            'profile_image': entity['image'],
            'approved': tag['approved'],
          });
        }
      }
    }
    return users;
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
              isEvent: widget.post['is_event'] == true,
              eventOrganisers: widget.post['is_event'] == true
                  ? (widget.post['event_organisers'] as List<dynamic>? ?? [])
                  : null,
              isVerified: widget.post['user_verified'] == true,
              // ↓ pass tagged users for regular posts
              taggedUsers: widget.post['is_event'] != true
                  ? _getTaggedUsers()
                  : null,
              onUserTap: (userId) {
                Navigator.pushNamed(
                  context,
                  '/view-profile',
                  arguments: {'userId': userId},
                );
              },
              date: _formattedDate,
              currentUserId: user?.id,
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
                HapticFeedback.heavyImpact();
                _liked ? _toggleUnlike() : _optimisticLike();
              },
              onCommentTap: () => _openComments(context),
              onShareTap: _sharePost,
              newsTitle: widget.post['is_news'] == true
                  ? widget.post['caption'] ?? 'News'
                  : null,
              isNews: widget.post['is_news'] == true,
              isEvent: widget.post['is_event'] == true,
              eventId: widget.post['is_event'] == true
                  ? widget.post['id']
                  : null,
              newsContent: widget.post['news_content'], // HTML from ACF
              newsDate: widget.post['post_date'],
              newsImageUrls: _media
                  .map((m) => m['media_url'])
                  .whereType<String>()
                  .toList(),
              creatorProfileImage: widget.post['user_profile_image'],
              username: widget.post['username'] ?? '',
              isVerified: widget.post['user_verified'] == true,
              postUserId: widget.post['user_id'],
              asc_link_type: widget.post['asc_link_type'],
              asc_link_url: widget.post['asc_link'],
            ),
          ),

          GestureDetector(
            onTap: (_likesCount > 0 && widget.post['is_event'] != true)
                ? () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => LikesModal(postId: widget.post['id']),
                    );
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '$_likesCount likes',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          // ✅ Caption - Wrapped in RepaintBoundary
          RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: _PostCaptionSection(
                // if not news or event, show caption as normal
                commentsEnabled:
                    widget.post['is_news'] != true &&
                    widget.post['is_event'] != true,
                username: widget.post['username'] ?? '',
                caption: widget.post['caption'] ?? '',
                commentsCount: widget.post['comments_count'] ?? 0,
                onViewComments: () => _openComments(context),
                isEvent: widget.post['is_event'] == true,
                eventEndDate: widget.post['event_end_date'],
                eventLocation: widget.post['event_location'],
                eventStartDate: widget.post['event_start_date'],
                eventDescription: widget.post['event_description'] ?? '',
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
  final List<dynamic>? eventOrganisers; // ← change type from Map to List
  final bool isEvent;
  final List<Map<String, dynamic>>? taggedUsers;
  final void Function(dynamic userId)? onUserTap;

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
    this.onUserTap,
    this.taggedUsers,
    this.eventOrganisers,
    this.isEvent = false,
  });

  // ── Overlapping avatar stack ─────────────────────────────────
  Widget _buildCollabAvatars(List<dynamic> orgs) {
    // ↓ Filter first, then work only with approved
    final approved = orgs.where((o) {
      final org = o as Map<String, dynamic>;
      return org['approved'] != false;
    }).toList();

    final displayCount = approved.length.clamp(1, 3); // ← use approved count
    final stackWidth = (displayCount - 1) * 14.0 + 36.0;

    if (approved.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: stackWidth,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(displayCount, (i) {
          final org =
              approved[i] as Map<String, dynamic>; // ← use approved list
          final isFirst = i == 0;
          return Positioned(
            left: i * 14.0,
            top: 0,
            child: GestureDetector(
              onTap: isFirst ? onTapProfile : () => onUserTap?.call(org['id']),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: ProfileAvatar(
                  imageUrl: org['profile_image'],
                  radius: 16,
                ),
              ),
            ),
          );
        }).reversed.toList(),
      ),
    );
  }

  Widget _buildCollabTitle(BuildContext context, List<dynamic> orgs) {
    // ↓ Filter upfront — no mid-loop skipping
    final approved = orgs.where((o) {
      final org = o as Map<String, dynamic>;
      return org['approved'] != false;
    }).toList();

    if (approved.isEmpty) {
      return GestureDetector(
        onTap: onTapProfile,
        child: Text(
          username,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      );
    }

    const int maxDisplay = 2;
    final displayOrgs = approved.take(maxDisplay).toList(); // ← from approved
    final extraCount = approved.length - maxDisplay; // ← from approved
    final nameWidgets = <Widget>[];

    for (int i = 0; i < displayOrgs.length; i++) {
      final org = displayOrgs[i] as Map<String, dynamic>;
      final name = (org['name'] ?? '') as String;
      final isFirst = i == 0;
      final isLast = i == displayOrgs.length - 1;
      final isSecondLast = i == displayOrgs.length - 2;

      nameWidgets.add(
        GestureDetector(
          onTap: isFirst ? onTapProfile : () => onUserTap?.call(org['id']),
          child: Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.black,
              fontSize: 14.5,
            ),
          ),
        ),
      );

      if (!isLast) {
        nameWidgets.add(
          Text(
            isSecondLast && extraCount == 0 ? ' and ' : ', ',
            style: const TextStyle(fontSize: 13.5, color: Colors.black87),
          ),
        );
      }
    }

    if (extraCount > 0) {
      nameWidgets.add(
        GestureDetector(
          onTap: () =>
              _showAllTagsModal(context, approved), // ← pass approved only
          child: Text(
            ' and $extraCount more',
            style: const TextStyle(fontSize: 13.5, color: Colors.black87),
          ),
        ),
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: nameWidgets,
    );
  }

  void _showAllTagsModal(BuildContext context, List<dynamic> orgs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Tagged Users',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ),
            const Divider(height: 1),
            // List all users
            ...orgs.map((o) {
              final org = o as Map<String, dynamic>;
              final name = org['name'] ?? '';
              final isFirst = orgs.indexOf(o) == 0;
              return ListTile(
                leading: ClipOval(
                  child: ProfileAvatar(
                    imageUrl: org['profile_image'],
                    radius: 20,
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (isFirst) {
                    onTapProfile?.call();
                  } else {
                    onUserTap?.call(org['id']);
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwnPost = postUserId.toString() == currentUserId.toString();

    // ── Event collab layout ──────────────────────────────────────
    if (isEvent && eventOrganisers != null && eventOrganisers!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 3, 8),
        child: Row(
          children: [
            _buildCollabAvatars(eventOrganisers!),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: onTapProfile,
                    child: _buildCollabTitle(context, eventOrganisers!),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Featured',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── Tagged users collab layout ───────────────────────────────
    if (taggedUsers != null && taggedUsers!.isNotEmpty) {
      // Merge post author + tagged users into one collab list
      final collabList = <Map<String, dynamic>>[
        {'name': username, 'profile_image': profileImage},
        ...taggedUsers!,
      ];

      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 3, 8),
        child: Row(
          children: [
            _buildCollabAvatars(collabList),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: onTapProfile,
                    child: _buildCollabTitle(context, collabList),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            if (isOwnPost)
              GestureDetector(
                onTap: onSettings,
                child: const Icon(
                  Icons.more_vert,
                  color: Colors.black,
                  size: 24,
                ),
              ),
          ],
        ),
      );
    }

    // ── Standard post layout (unchanged) ────────────────────────
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
              if (entity == null) return const SizedBox.shrink();

              final type = tag['type'];
              final name = entity['name'] ?? 'Unknown';
              final image = entity['image'];

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey.shade300,
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

  bool _isCfBlurredUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    // Cloudflare image variants contain these patterns
    return url.contains('/blur') ||
        url.contains('variant=blur') ||
        url.contains('blurred');
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

                // if blurred url is not cloudflare image, then its not blurred, so blur it

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

                    // ── Blurred background ───────────────────────────────────────
                    if (blurredUrl != null &&
                        blurredUrl.isNotEmpty &&
                        _isCfBlurredUrl(blurredUrl))
                      // Real CF blur variant — use as-is
                      Positioned.fill(
                        child: CachedNetworkImage(
                          imageUrl: blurredUrl,
                          fit: BoxFit.cover,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      )
                    else
                      // Not a CF blur (event image, AWS, etc.) — blur the main image manually
                      Positioned.fill(
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: CachedNetworkImage(
                            imageUrl: mediaUrl,
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),

                    // // ── Dim overlay on top of either blur type ───────────────────
                    // Positioned.fill(
                    //   child: Container(color: Colors.black.withOpacity(0.15)),
                    // ),
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
                                  postId: item['id'].toString(),
                                  url: mediaUrl,
                                  // isActive: currentPage == i,
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
  final bool isNews;
  final bool isEvent;
  final String? newsTitle;
  final String? newsContent;
  final String? newsDate;
  final List<String> newsImageUrls; // pass your media urls
  final String? creatorProfileImage;
  final String? username;
  final bool? isVerified;
  final dynamic postUserId;
  final dynamic eventId;
  final String? asc_link_type;
  final String? asc_link_url;

  const _PostActions({
    required this.liked,
    required this.onLikeTap,
    required this.onCommentTap,
    required this.onShareTap,
    this.isNews = false,
    this.isEvent = false,
    this.newsTitle,
    this.newsContent,
    this.newsDate,
    this.newsImageUrls = const [],
    this.creatorProfileImage,
    this.username,
    this.isVerified,
    this.postUserId,
    this.eventId,
    this.asc_link_type,
    this.asc_link_url,
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
          if (!isNews && !isEvent) ...[
            const SizedBox(width: 16),
            GestureDetector(
              onTap: onCommentTap,
              child: const Icon(
                Icons.mode_comment_outlined,
                color: Colors.black,
                size: 22,
              ),
            ),
          ],
          const SizedBox(width: 16),
          GestureDetector(
            onTap: onShareTap,
            child: const Icon(
              Icons.send_outlined,
              color: Colors.black,
              size: 22,
            ),
          ),

          // ↓ News Read More button
          if (isEvent) ...[
            const Spacer(),
            GestureDetector(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.eventDetail,
                  arguments: {
                    'event': {'id': eventId},
                  },
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFAE9159),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFAE9159).withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Text(
                  'View Event',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],

          if (asc_link_type != null &&
              (asc_link_url != null && asc_link_url!.trim().isNotEmpty)) ...[
            const Spacer(),
            GestureDetector(
              onTap: () {
                if (asc_link_url != null && asc_link_url!.trim().isNotEmpty) {
                  var raw = asc_link_url!.trim();
                  // Ensure there's a scheme — default to https if missing
                  if (!raw.startsWith('http://') &&
                      !raw.startsWith('https://')) {
                    raw = 'https://$raw';
                  }

                  final uri = Uri.tryParse(raw);

                  if (uri != null && uri.hasScheme) {
                    launchUrl(uri, mode: LaunchMode.platformDefault);
                  } else {
                    debugPrint('Invalid URL, skipping launch: $raw');
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFAE9159),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFAE9159).withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  asc_link_type == 'video' ? 'Watch Video' : 'See More',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
          if (isNews) ...[
            const Spacer(),
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true, // full height
                  backgroundColor: Colors.transparent,
                  useSafeArea: true,
                  builder: (_) => NewsReaderSheet(
                    title: newsTitle ?? '',
                    htmlContent: newsContent ?? '',
                    date: newsDate ?? '',
                    imageUrls: newsImageUrls,
                    creatorProfileImage: creatorProfileImage,
                    username: username,
                    isVerified: isVerified,
                    postUserId: postUserId,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFAE9159),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFAE9159).withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Text(
                  'Read More',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
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
  final bool commentsEnabled;
  final bool isEvent;
  final String? eventStartDate;
  final String? eventEndDate;
  final String? eventLocation;
  final String? eventDescription;

  const _PostCaptionSection({
    required this.username,
    required this.caption,
    required this.commentsCount,
    required this.onViewComments,
    this.commentsEnabled = true,
    this.isEvent = false,
    this.eventStartDate,
    this.eventEndDate,
    this.eventLocation,
    this.eventDescription,
  });

  @override
  State<_PostCaptionSection> createState() => _PostCaptionSectionState();
}

class _PostCaptionSectionState extends State<_PostCaptionSection> {
  bool _showFullCaption = false;

  static const Color _gold = Color(0xFFAE9159);

  Widget _buildEventDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: _gold),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatStartDate(String start) {
    try {
      final parts = start.split(' ');
      if (parts.length >= 2) {
        return parts.first; // Return just the date portion
      }
      return start;
    } catch (_) {
      return start;
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.username;
    final caption = widget.caption.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Username + caption (non-event) ───────────────────────
        if (!widget.isEvent) ...[
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
              onSuffixPressed: () =>
                  setState(() => _showFullCaption = !_showFullCaption),
              suffix: _showFullCaption ? 'Show less' : 'Show more',
              onHashtagPressed: (hashtag) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HashtagPostsPage(hashtag: hashtag),
                  ),
                );
              },
              onUserTagPressed: (userId) {
                Navigator.pushNamed(
                  context,
                  '/view-profile',
                  arguments: {'userId': userId},
                );
              },
            ),
          ],
        ],

        // ── Event layout ─────────────────────────────────────────
        if (widget.isEvent) ...[
          // Organiser name
          Text(
            username,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 3),

          // Event name (caption = title)
          Text(
            caption,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),

          // Date
          if (widget.eventStartDate != null)
            _buildEventDetailRow(
              Icons.calendar_today_rounded,
              _formatStartDate(widget.eventStartDate!),
            ),

          // Time range — parse from start/end dates
          if (widget.eventStartDate != null && widget.eventEndDate != null)
            _buildEventDetailRow(
              Icons.access_time_rounded,
              _formatTimeRange(widget.eventStartDate!, widget.eventEndDate!),
            ),

          // Location
          if (widget.eventLocation != null && widget.eventLocation!.isNotEmpty)
            _buildEventDetailRow(
              Icons.location_on_rounded,
              widget.eventLocation!,
            ),

          // Description
          // if (widget.eventDescription != null &&
          //     widget.eventDescription!.isNotEmpty) ...[
          //   const SizedBox(height: 6),
          //   _HtmlDescription(
          //     html: widget.eventDescription!,
          //     maxLines: 3, // ← adjust to taste
          //   ),
          // ],
        ],

        const SizedBox(height: 6),
        if (widget.commentsCount > 0 && widget.commentsEnabled)
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

  /// Extracts just the time portion from "MM/dd/yyyy HH:mm" formatted strings
  String _formatTimeRange(String start, String end) {
    try {
      final startTime = start.contains(' ') ? start.split(' ').last : '';
      final endTime = end.contains(' ') ? end.split(' ').last : '';
      if (startTime.isNotEmpty && endTime.isNotEmpty) {
        return '$startTime – $endTime';
      }
      return startTime;
    } catch (_) {
      return start;
    }
  }
}

class _HtmlDescription extends StatefulWidget {
  final String html;
  final int maxLines;

  const _HtmlDescription({required this.html, this.maxLines = 3});

  @override
  State<_HtmlDescription> createState() => _HtmlDescriptionState();
}

class _HtmlDescriptionState extends State<_HtmlDescription> {
  bool _expanded = false;

  static const Color _gold = Color(0xFFAE9159);

  @override
  Widget build(BuildContext context) {
    final showToggle = _isLongContent();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: _expanded
                ? const BoxConstraints() // ← unconstrained when expanded
                : BoxConstraints(maxHeight: 1.6 * 15 * widget.maxLines + 8),
            child: ClipRect(
              child: Html(
                data: widget.html,
                style: {
                  "body": Style(
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                    fontSize: FontSize(15),
                    lineHeight: const LineHeight(1.6),
                    color: Colors.grey.shade700,
                  ),
                  "p": Style(margin: Margins.only(bottom: 12)),
                  "h1, h2, h3, h4, h5, h6": Style(
                    margin: Margins.only(top: 16, bottom: 8),
                    fontWeight: FontWeight.bold,
                  ),
                  "ul, ol": Style(margin: Margins.only(left: 16, bottom: 12)),
                  "li": Style(margin: Margins.only(bottom: 4)),
                  "a": Style(
                    color: const Color(0xFFAE9159),
                    textDecoration: TextDecoration.underline,
                  ),
                  "strong, b": Style(fontWeight: FontWeight.bold),
                  "em, i": Style(fontStyle: FontStyle.italic),
                },
                onLinkTap: (url, attributes, element) async {
                  if (url != null) {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  }
                },
              ),
            ),
          ),
        ),

        // Toggle button
        if (showToggle) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Show less' : 'Show more',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _gold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // Rough check — strip tags and see if plain text is long enough to truncate
  bool _isLongContent() {
    final plain = widget.html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
    // ~50 chars per line × maxLines
    return plain.length > 50 * widget.maxLines;
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
