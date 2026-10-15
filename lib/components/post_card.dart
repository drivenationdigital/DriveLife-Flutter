import 'package:drivelife/screens/create-post/edit_post_tags_screen.dart';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/components/news_article_screen.dart';
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

/// Decode widths for images in the feed, in physical pixels.
///
/// Flutter decodes a network image at its SOURCE size unless told otherwise,
/// and holds the decoded bitmap in memory — four bytes a pixel. A 2000×1500
/// photo is 12MB decoded, so a feed scrolling through a dozen of them is
/// measured in hundreds of megabytes before anything has gone wrong.
///
/// These are the two that were uncapped. The main image already caps itself
/// at 1400, which is about a phone's screen width in physical pixels.

/// The blurred backdrop behind a post's image.
///
/// Deliberately tiny: it is blurred by 18 sigma before it reaches the screen,
/// so detail is destroyed by design. 64px costs about 16KB decoded against
/// roughly 12MB for the same photo at source — and the blur has far less to
/// chew through, which shows up in scroll smoothness, not just memory.
const int _blurDecodeWidth = 64;

/// A 44pt avatar on a 3x screen.
const int _avatarDecodeWidth = 132;

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

  /// True when this post is a club post with no media — render as an
  /// announcement-style card (caption-first, prominent typography).
  bool get _isClubAnnouncement {
    final isClubPost =
        widget.post['is_club_post'] == true || widget.post['club_id'] != null;
    return isClubPost && !_hasMedia;
  }

  bool get _isVenueAnnouncement {
    final isVenuePost =
        widget.post['is_venue_post'] == true || widget.post['venue_id'] != null;
    return isVenuePost && !_hasMedia;
  }

  int _currentPage = 0;
  bool _liked = false;
  int _likesCount = 0;
  bool _allowSwipe = true;
  bool _showHeart = false;

  @override
  void initState() {
    super.initState();

    _liked = widget.post['is_liked'] ?? false;
    _likesCount = _asCount(widget.post['likes_count']) ?? 0;

    // Curated posts show "Featured" in place of the timestamp, so a post the
    // team picked weeks ago doesn't read as stale in the For You tab.
    if (widget.post['is_event'] == true || widget.post['is_featured'] == true) {
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

    // Plain assignment, NOT setState.
    //
    // didUpdateWidget runs while the parent is building, and setState there
    // marks this element dirty mid-frame — "setState() or markNeedsBuild()
    // called during build". Liking a post makes the feed rebuild every
    // visible card, so a double tap walked straight into it.
    //
    // There is nothing to schedule anyway: the framework rebuilds this
    // widget immediately after this returns.
    _liked = widget.post['is_liked'] ?? _liked;
    _likesCount = _asCount(widget.post['likes_count']) ?? _likesCount;
  }

  /// A string from JSON, or null when there is nothing in it.
  ///
  /// PHP sends an absent field as null and an empty one as "", and both mean
  /// the same thing to a reader: do not draw it.
  static String? _str(dynamic value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  /// A like count from JSON, whatever shape it arrives in.
  ///
  /// `as int` was used in three places and throws on anything else — and this
  /// comes from PHP, which is perfectly happy to send "12" or 12.0 for the
  /// same field depending on the endpoint. Null when it cannot be read, so
  /// callers keep the count they already had rather than showing a wrong one.
  static int? _asCount(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
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
        // false, not true. Reporting a success here left the feed's own copy
        // of the count one higher every time a like failed, and the card and
        // the feed then disagreed for the rest of the session.
        widget.onLikeChanged?.call(false);
      }
      return; // Skip post like API for events
    }

    final res = await InteractionsAPI.maybeLikePost('${widget.post['id']}');

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

    final res = await InteractionsAPI.maybeLikePost('${widget.post['id']}');

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
    final postUrl = 'https://app.mydrivelife.com/post/$postId?ref=share';
    final shareText =
        'Check out this post on DriveLife by @$postUser.\n\n$postDescription\n\n$postUrl';

    if (widget.post['is_event'] == true) {
      final eventId = widget.post['id'];
      final eventUrl = 'https://app.mydrivelife.com/event/$eventId?ref=share';

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

  /// Whether this post lives on another site and only passes through the
  /// feed — DriveLife news. There is no row to like, comment on or bookmark.
  bool get _isExternal => widget.post['is_external'] == true;

  /// Opens the article.
  ///
  /// One method, because two things lead here: the "Read more" button and
  /// the picture above it. Building the route in both places would be the
  /// kind of duplication that drifts the first time a field is added.
  void _openArticle() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewsArticleScreen(
          title: _str(widget.post['caption']) ?? 'News',
          htmlContent: _str(widget.post['news_content']) ?? '',
          date: _str(widget.post['post_date']) ?? '',
          imageUrls: _media
              .map((m) => '${m['media_url'] ?? ''}')
              .where((url) => url.isNotEmpty)
              .toList(),
          username: _str(widget.post['username']),
          isVerified: widget.post['user_verified'] == true,
          postUserId: _str(widget.post['user_id']),
          category: _str(widget.post['news_category']),
          excerpt: _str(widget.post['news_excerpt']),
          imageCaption: _str(widget.post['news_image_caption']),
          readMinutes: _asCount(widget.post['news_read_minutes']),
          articleUrl: _str(widget.post['news_url']),
        ),
      ),
    );
  }

  /// The "Read more" button on a news card.
  ///
  /// Built here rather than inside _PostActions because everything it needs
  /// is already on widget.post. Passing a dozen article fields down into the
  /// actions row only to hand them straight back to a sheet was indirection
  /// for its own sake.
  Widget _buildReadMore() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: _openArticle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFAE9159),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFAE9159).withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Read more',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleDoubleTap() async {
    // Hiding the like button was not enough: a double tap reaches the same
    // code by another route, and on an external post it sent a like for an
    // id that is not in ce_social_posts.
    if (_isExternal) return;

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
              leading: const Icon(
                Icons.local_offer_outlined,
                color: Colors.black,
              ),
              title: const Text('Edit User Tags'),
              // Tagging used to be available only while composing, so a wrong
              // tag or a missed person stayed that way for good.
              onTap: () async {
                Navigator.pop(context);

                final changed = await Navigator.push(
                  scaffoldContext,
                  MaterialPageRoute(
                    builder: (_) => EditPostTagsScreen(
                      postId: int.tryParse('${widget.post['id']}') ?? 0,
                      authorId: int.tryParse('${widget.post['user_id']}') ?? 0,
                    ),
                  ),
                );

                if (changed == true) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    scaffoldContext,
                  ).showSnackBar(const SnackBar(content: Text('Tags updated')));
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
              location: {
                'name': widget.post['location'] ?? '',
                'lat': widget.post['lat'] ?? 0.0,
                'lng': widget.post['lng'] ?? 0.0,
              },
              currentUserId: user?.id,
              postUserId: widget.post['user_id'],
              isExternal: _isExternal,
              onTapProfile: widget.onTapProfile,
              onSettings: _showPostOptions,
              primaryColor: theme.primaryColor,
            ),
          ),

          // ── ANNOUNCEMENT LAYOUT ──────────────────────────────────
          // if club or venue announcement (no media), show caption first with more spacing and larger font, then actions
          if (_isClubAnnouncement || _isVenueAnnouncement) ...[
            // Caption — large, plain, generous spacing
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _PostCaptionSection(
                commentsEnabled: false,
                username: '',
                caption: widget.post['caption'] ?? '',
                commentsCount: 0,
                onViewComments: () => _openComments(context),
                isEvent: false,
                eventEndDate: null,
                eventLocation: null,
                eventStartDate: null,
                eventDescription: '',
              ),
            ),

            // Slim divider, like the line between tweets
            Container(
              height: 1,
              color: Colors.grey.shade100,
              margin: const EdgeInsets.symmetric(horizontal: 16),
            ),

            // Action row
            RepaintBoundary(
              child: _PostActions(
                liked: _liked,
                onLikeTap: () {
                  HapticFeedback.heavyImpact();
                  _liked ? _toggleUnlike() : _optimisticLike();
                },
                onCommentTap: () => _openComments(context),
                onShareTap: _sharePost,
                isNews: false,
                isEvent: false,
                eventId: null,
                username: widget.post['username'] ?? '',
                isVerified: widget.post['user_verified'] == true,
                postUserId: widget.post['user_id'],
                asc_link_type: widget.post['asc_link_type'],
                asc_link_url: widget.post['asc_link'],
              ),
            ),

            // No like count on an external post. DriveLife news lives on
            // another site and has no row to like, so the only number it
            // could ever show is nought — which reads as "nobody liked
            // this" rather than "this cannot be liked".
            if (!_isExternal)
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

            // A poll on this post, directly under the likes. Without it the
            // only sign that a post asked you something was opening the
            // comments on the off-chance.
            _PollPrompt(
              summary: widget.post['poll_summary'],
              onTap: () => _openComments(context),
            ),
          ]
          // ── REGULAR POST LAYOUT (unchanged) ──────────────────────
          else ...[
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
                  // The picture is the biggest thing on a news card and the
                  // likeliest thing to be aimed at, so it opens the article
                  // rather than doing nothing.
                  onTap: widget.post['is_news'] == true ? _openArticle : null,
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
                isNews: widget.post['is_news'] == true,
                isExternal: widget.post['is_external'] == true,
                isEvent: widget.post['is_event'] == true,
                eventId: widget.post['is_event'] == true
                    ? widget.post['id']
                    : null,
                username: widget.post['username'] ?? '',
                isVerified: widget.post['user_verified'] == true,
                postUserId: widget.post['user_id'],
                asc_link_type: widget.post['asc_link_type'],
                asc_link_url: widget.post['asc_link'],
              ),
            ),

            // No like count on an external post. DriveLife news lives on
            // another site and has no row to like, so the only number it
            // could ever show is nought — which reads as "nobody liked
            // this" rather than "this cannot be liked".
            if (!_isExternal)
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

            // A poll on this post, directly under the likes. Without it the
            // only sign that a post asked you something was opening the
            // comments on the off-chance.
            _PollPrompt(
              summary: widget.post['poll_summary'],
              onTap: () => _openComments(context),
            ),
            // ✅ Caption - Wrapped in RepaintBoundary
            RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: _PostCaptionSection(
                  // if not news or event, show caption as normal
                  commentsEnabled:
                      widget.post['is_news'] != true &&
                      widget.post['is_event'] != true,
                  isNews: widget.post['is_news'] == true,
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

            // Under the caption, not in the actions row.
            //
            // It is the one thing to do with a news card, so it reads as the
            // end of the card rather than as one control among several — and
            // in the row it sat to the right of icons that do not apply to
            // news, which left it looking like an afterthought.
            if (widget.post['is_news'] == true) _buildReadMore(),

            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// ✅ Extracted header as stateless widget
class _PostHeader extends StatelessWidget {
  /// True for a post that lives on another site and only passes through the
  /// feed. It cannot be owned, edited or deleted from here.
  final bool isExternal;

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
  final Map<String, dynamic>? location;
  final void Function(dynamic userId)? onUserTap;

  const _PostHeader({
    this.isExternal = false,
    required this.profileImage,
    required this.username,
    required this.isVerified,
    required this.date,
    required this.currentUserId,
    required this.postUserId,
    required this.onTapProfile,
    required this.onSettings,
    required this.primaryColor,
    this.location,
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

  String _shortenLocationName(String full) {
    if (full.isEmpty) return full;

    // Strip the country if it's the last segment
    // ("Hardwick Hall, Sedgefield, UK" → "Hardwick Hall, Sedgefield")
    final parts = full.split(',').map((s) => s.trim()).toList();

    // Keep only first 2 parts — usually "Place name, City"
    // This drops postcodes, regions, countries
    if (parts.length > 2) {
      return '${parts[0]}, ${parts[1]}';
    }

    return full;
  }

  Widget _buildSubtitle(BuildContext context) {
    final hasLocation =
        location != null && (location!['name']?.toString() ?? '').isNotEmpty;

    if (!hasLocation) {
      return Text(
        date,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
      );
    }

    return GestureDetector(
      onTap: () => _showLocationSheet(context),
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _shortenLocationName(location!['name'].toString()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0B0B0B),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 2.5,
            height: 2.5,
            decoration: BoxDecoration(
              color: Colors.grey.shade500,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            date,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  void _showLocationSheet(BuildContext context) {
    final name = location?['name']?.toString() ?? '';
    final lat = double.tryParse(location?['lat']?.toString() ?? '');
    final lng = double.tryParse(location?['lng']?.toString() ?? '');
    final hasCoords = lat != null && lng != null && (lat != 0.0 || lng != 0.0);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Location preview header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.10),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.location_on,
                      color: primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0B0B0B),
                          ),
                        ),
                        if (hasCoords) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),

            // Actions
            ListTile(
              leading: const Icon(Icons.map_outlined, color: Color(0xFF0B0B0B)),
              title: const Text(
                'Open in Maps',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _launchMaps(name, lat, lng);
              },
            ),
            if (hasCoords) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(
                  Icons.directions_outlined,
                  color: Color(0xFF0B0B0B),
                ),
                title: const Text(
                  'Get directions',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _launchDirections(lat, lng);
                },
              ),
            ],
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(
                Icons.copy_outlined,
                color: Color(0xFF0B0B0B),
              ),
              title: const Text(
                'Copy address',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
              ),
              onTap: () {
                Clipboard.setData(ClipboardData(text: name));
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Address copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _launchMaps(String name, double? lat, double? lng) async {
    final Uri uri;
    if (lat != null && lng != null && (lat != 0.0 || lng != 0.0)) {
      // Apple Maps on iOS, Google Maps on Android — generic geo: works on both
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
    } else {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}',
      );
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchDirections(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // Never your own, however the ids line up.
    //
    // DriveLife news is attributed to the drivelife account, so for whoever
    // is signed in as that account these would otherwise come out as their
    // own posts — with an edit-and-delete menu acting on an article that has
    // no row here to edit or delete.
    final isOwnPost =
        !isExternal && postUserId.toString() == currentUserId.toString();

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
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (location != null &&
                      (location!['name']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: _buildSubtitle(context),
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
                  _buildSubtitle(context),
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
      subtitle: _buildSubtitle(context),
      trailing: isOwnPost
          ? GestureDetector(
              onTap: onSettings,
              child: const Icon(
                Icons.more_horiz,
                color: Colors.black,
                size: 24,
              ),
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

  /// A single tap, when there is somewhere for it to go. Null on an ordinary
  /// post, where tapping a photo does nothing and should keep doing nothing.
  final VoidCallback? onTap;
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
    this.onTap,
    required this.onSwipeChanged,
  });

  double _parseDouble(dynamic v, {double fallback = 1}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  void _showTagsBottomSheet(BuildContext context, List<dynamic> tags) {
    // Group tags by type
    final grouped = <String, List<dynamic>>{};
    for (final tag in tags) {
      final type = tag['type']?.toString() ?? 'unknown';
      grouped.putIfAbsent(type, () => []).add(tag);
    }

    // Display order — people first, then vehicles, then events, then anything else
    const typeOrder = ['user', 'car', 'event'];
    final orderedKeys = [
      ...typeOrder.where(grouped.containsKey),
      ...grouped.keys.where((k) => !typeOrder.contains(k)),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tagged',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B0B0B),
                      ),
                    ),
                  ),
                  Text(
                    '${tags.length} ${tags.length == 1 ? "tag" : "tags"}',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Sections
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final key in orderedKeys) ...[
                      _buildTagSection(
                        context: sheetContext,
                        type: key,
                        items: grouped[key]!,
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagSection({
    required BuildContext context,
    required String type,
    required List<dynamic> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Icon(
                _iconForType(type),
                size: 14,
                color: const Color(0xFFC4A062),
              ),
              const SizedBox(width: 6),
              Text(
                _labelForType(type, items.length),
                style: const TextStyle(
                  color: Color(0xFF8A8A8A),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),

        // Items
        for (final tag in items) _buildTagTile(context, tag),
      ],
    );
  }

  Widget _buildTagTile(BuildContext context, dynamic tag) {
    final entity = tag['entity'];
    if (entity == null) return const SizedBox.shrink();

    final type = tag['type']?.toString() ?? '';
    final name = entity['name']?.toString() ?? 'Unknown';
    final image = entity['image']?.toString();

    // Subtitle text per type
    String? subtitle;
    if (type == 'user') {
      subtitle = entity['username'] != null ? '@${entity['username']}' : null;
    } else if (type == 'car') {
      // The plate under the car, where there is a car to put it under. On a
      // tag that is only ever a plate, the plate is already the title and
      // repeating it says nothing.
      final registration = '${entity['registration'] ?? ''}'.trim();
      subtitle = (registration.isEmpty || registration == name)
          ? 'Vehicle'
          : registration;
    } else if (type == 'event') {
      subtitle = 'Event';
    }

    // A plate matching no garage has no page behind it, so the row is shown
    // but not tappable rather than opening an empty vehicle screen.
    final entityId = int.tryParse('${entity['id']}') ?? 0;
    final opens = type != 'car' || entityId > 0;

    return InkWell(
      onTap: opens
          ? () {
              Navigator.pop(context);
              _navigateToEntity(context, type, entity);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Avatar/image — square with rounded corners for events, circle for people/cars
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: type == 'event' ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: type == 'event' ? BorderRadius.circular(8) : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: image != null && image.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.cover,
                      // Image.network before: no disk cache, so every avatar
                      // was fetched again each time it scrolled back into
                      // view, and decoded at whatever size it was uploaded
                      // at to fill 44 logical pixels.
                      memCacheWidth: _avatarDecodeWidth,
                      errorWidget: (_, __, ___) => Icon(
                        _iconForType(type),
                        color: Colors.grey.shade500,
                        size: 22,
                      ),
                    )
                  : Icon(
                      _iconForType(type),
                      color: Colors.grey.shade500,
                      size: 22,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFF0B0B0B),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'user':
        return Icons.person_outline;
      case 'car':
        return Icons.directions_car_outlined;
      case 'event':
        return Icons.calendar_today_outlined;
      default:
        return Icons.tag;
    }
  }

  String _labelForType(String type, int count) {
    switch (type) {
      case 'user':
        return count == 1 ? 'USER' : 'USERS';
      case 'car':
        return count == 1 ? 'VEHICLE' : 'VEHICLES';
      case 'event':
        return count == 1 ? 'EVENT' : 'EVENTS';
      default:
        return type.toUpperCase();
    }
  }

  void _navigateToEntity(BuildContext context, String type, dynamic entity) {
    switch (type) {
      case 'user':
        Navigator.pushNamed(
          context,
          '/view-profile',
          arguments: {'userId': entity['id']},
        );
        break;
      case 'car':
        Navigator.pushNamed(
          context,
          '/vehicle-detail',
          arguments: {'garageId': entity['id']},
        );
        break;
      case 'event':
        Navigator.pushNamed(
          context,
          '/event-detail',
          arguments: {
            'event': {'id': entity['id'], 'name': entity['name']},
          },
        );
        break;
    }
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
      onTap: onTap,
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
                          // Decoded tiny on purpose. This is a backdrop that
                          // is blurred before anybody sees it, so resolution
                          // buys nothing — and a feed holding several
                          // full-size decodes for images nobody can make out
                          // is the fastest way to run a phone out of memory.
                          memCacheWidth: _blurDecodeWidth,
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
                            // Same image as the one on top, decoded again for
                            // the backdrop — so without a cap every post in
                            // the feed costs its full decode twice. Blurring
                            // it afterwards makes the detail unrecoverable
                            // anyway, and a small source makes the blur
                            // itself cheaper to draw.
                            memCacheWidth: _blurDecodeWidth,
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
                                  // ONLY width — never both. ResizeImage
                                  // defaults to ResizeImagePolicy.exact, which
                                  // clamps each axis independently: a 1365x2048
                                  // photo with both set to 1400 decodes as
                                  // 1365x1400, i.e. squashed. One dimension
                                  // makes Flutter scale proportionally.
                                  memCacheWidth: 1400,
                                  // The disk resize is aspect-safe (single
                                  // uniform factor), so it can bound both.
                                  maxHeightDiskCache: 2048,
                                  maxWidthDiskCache: 2048,
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

  /// True for a post that lives on another site and only passes through this
  /// feed — DriveLife news. It has no row in ce_social_posts, so there is
  /// nothing to like, comment on or bookmark.
  final bool isExternal;

  final bool isEvent;
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
    this.isExternal = false,
    this.isEvent = false,
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
          // Not on an external post. DriveLife news is read live from
          // drive-life.com and has no row in ce_social_posts to like — the
          // tap would write against an id that does not exist there.
          if (!isExternal)
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
              child: SvgPicture.asset(
                'assets/app-icons/comment.svg',
                width: 25,
                height: 25,
                colorFilter: const ColorFilter.mode(
                  Colors.black,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ],
          // Not on an external post. Sharing builds an
          // app.mydrivelife.com/post/<id> deep link, and a DriveLife news
          // article has no post of that kind to open — the link resolves to
          // nothing. The article's own URL is shared from the reader instead.
          if (!isExternal) ...[
            const SizedBox(width: 16),
            GestureDetector(
              onTap: onShareTap,
              child: SvgPicture.asset(
                'assets/app-icons/share.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Colors.black,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ],

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
        ],
      ),
    );
  }
}

// Caption section remains the same
class _PostCaptionSection extends StatefulWidget {
  /// True on a news card, where the caption is the article's headline.
  ///
  /// It is set as the heading in place of the author's name rather than
  /// under it: the name is already in the byline at the top of the card, and
  /// a story is found by its headline, not by who filed it.
  final bool isNews;

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
    this.isNews = false,
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
          if (username.isNotEmpty && !widget.isNews)
            Text(
              username,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),

          // The headline, where an ordinary post has its author's name.
          if (widget.isNews && caption.isNotEmpty)
            Text(
              caption,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.3,
              ),
            )
          else if (caption.isNotEmpty) ...[
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

/// "This post has a poll" — the line under the likes.
///
/// Renders nothing at all when the post has no poll, which is every post that
/// existed before polls did. The summary comes from the feed (see
/// dl_poll_attach); tapping opens the comments, which is where the poll is
/// actually answered.
class _PollPrompt extends StatelessWidget {
  static const Color _gold = Color(0xFFAE9159);

  /// The `poll_summary` from the post, straight off the API. Dynamic because
  /// the card works in untyped post maps throughout.
  final dynamic summary;
  final VoidCallback onTap;

  const _PollPrompt({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (summary is! Map) return const SizedBox.shrink();

    final map = Map<String, dynamic>.from(summary as Map);
    final question = '${map['question'] ?? ''}'.trim();
    final voted = map['has_voted'] == true;
    final closed = map['is_closed'] == true;
    final votes = int.tryParse('${map['total_votes']}') ?? 0;

    // A poll with no question is not a poll worth announcing.
    if (question.isEmpty) return const SizedBox.shrink();

    // Closed comes first: once voting is over, whether this reader answered
    // is no longer the useful thing to say about it.
    final label = closed
        ? 'See result'
        : voted
        ? 'You voted · ${votes == 1 ? '1 vote' : '$votes votes'}'
        : 'Tap to vote';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(
                closed
                    ? Icons.how_to_vote_outlined
                    : voted
                    ? Icons.check_circle_outline
                    : Icons.poll_outlined,
                size: 15,
                color: (voted || closed) ? Colors.grey.shade600 : _gold,
              ),
              const SizedBox(width: 6),
              // The question itself, because "there is a poll" is not a
              // reason to open anything — the question is.
              Expanded(
                child: Text(
                  question,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: (voted || closed)
                        ? Colors.grey.shade700
                        : Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: (voted || closed) ? Colors.grey.shade600 : _gold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
