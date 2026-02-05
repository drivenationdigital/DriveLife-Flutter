import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/services/user_service.dart';
import 'package:drivelife/widgets/formatted_text.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../api/notifications_api.dart';
import '../widgets/profile/profile_avatar.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _allNotifications = [];
  Map<String, List<dynamic>> _groupedNotifications = {};
  bool _loading = true;
  bool _hasMore = true;
  String? _errorMessage;

  final UserService _userService = UserService();

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications({
    bool loadOld = false,
    bool isRefresh = false,
  }) async {
    if (!mounted) return;

    if (!isRefresh) {
      setState(() {
        _loading = true;
        _errorMessage = null; // ✅ ADD THIS
      });
    }

    final response = await NotificationsAPI.getUserNotifications(
      loadOldNotifications: loadOld,
    );

    if (!mounted) return;

    if (response != null && response?['success'] != false) {
      final data = response['data'] ?? response;

      final List<dynamic> notifications = [
        ...(data['recent'] ?? []),
        ...(data['last_week'] ?? []),
        ...(data['last_30_days'] ?? []),
      ];
      setState(() {
        _allNotifications = notifications;
        _groupedNotifications = _groupNotificationsFromBuckets(data);
        _hasMore = data['has_more_notifications'] ?? false;
        _loading = false;
      });

      if (notifications.isNotEmpty) {
        NotificationsAPI.markMultipleNotificationsAsRead();
      }
    } else {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Map<String, List<dynamic>> _groupNotificationsFromBuckets(
    Map<String, dynamic> notifications,
  ) {
    List<dynamic> safeList(dynamic v) => v is List ? v : <dynamic>[];

    final recent = safeList(notifications['recent']);
    final lastWeek = safeList(notifications['last_week']);
    final last30 = safeList(notifications['last_30_days']);

    final grouped = <String, List<dynamic>>{
      if (recent.isNotEmpty) 'Recent': recent,
      if (lastWeek.isNotEmpty) 'This Week': lastWeek,
      if (last30.isNotEmpty) 'Last 30 Days': last30,
    };

    return grouped;
  }

  Future<void> _refreshNotifications() async {
    await _loadNotifications(isRefresh: true);
  }

  void _handleNotificationTap(Map<String, dynamic> notification) {
    final entity = notification['entity'];
    final entityType = entity?['entity_type'];
    final entityId = entity?['entity_id'];
    final userId = entity?['user_id'];
    final initiatorData = entity?['initiator_data'] ?? {};

    if (entityType == 'post' && entityId != null) {
      // Navigate to post detail
      Navigator.pushNamed(
        context,
        '/post-detail',
        arguments: {'postId': entityId.toString()},
      );
    } else if (entityType == 'user' || notification['type'] == 'follow') {
      // Navigate to user profile
      Navigator.pushNamed(
        context,
        '/view-profile',
        arguments: {
          'userId': initiatorData['id'],
          'username': initiatorData['display_name'] ?? '',
        },
      );
    }
  }

  Future<void> _handleFollowBack(int userId, bool wasFollowing) async {
    if (!mounted) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUserId = userProvider.user?.id;

    if (currentUserId == null) return;

    bool success;
    try {
      success = await _userService.followUser(userId, currentUserId);
    } catch (e) {
      success = false;
    }

    if (!mounted) return;

    if (success) {
      // Update UserProvider's following list
      if (!wasFollowing) {
        // Optimistic update
        userProvider.addFollowing(userId.toString());
      } else {
        userProvider.removeFollowing(userId.toString());
      }

      _refreshNotifications();

      // SUCCESS TOAST
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasFollowing ? 'Unfollowed successfully' : 'Followed successfully',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // ERROR TOAST
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final sessionUserFollowing =
        Provider.of<UserProvider>(context, listen: false).user?.following
            as List<dynamic>?;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Image.asset('assets/logo-dark.png', height: 18),
      ),
      body: _loading
          ? const _NotificationSkeleton() // ✅ SKELETON LOADER
          : _errorMessage != null
          ? _buildErrorState() // ✅ ERROR STATE
          : _allNotifications.isEmpty
          ? _buildEmptyState() // ✅ EMPTY STATE
          : _buildNotificationsList(theme, sessionUserFollowing),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _loadNotifications(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsList(
    ThemeProvider theme,
    List<dynamic>? sessionUserFollowing,
  ) {
    return RefreshIndicator(
      onRefresh: _refreshNotifications,
      color: theme.primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8),
        itemCount: _groupedNotifications.length,
        itemBuilder: (context, groupIndex) {
          final groupName = _groupedNotifications.keys.elementAt(groupIndex);
          final groupNotifications = _groupedNotifications[groupName]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(groupName),
              ...groupNotifications.asMap().entries.map((entry) {
                final notification = entry.value;
                final isLast = entry.key == groupNotifications.length - 1;

                return Column(
                  children: [
                    _NotificationTile(
                      notification: notification,
                      theme: theme,
                      sessionUserFollowing: sessionUserFollowing,
                      onTap: () => _handleNotificationTap(notification),
                      onFollowBack: _handleFollowBack,
                    ),
                    if (!isLast)
                      const Divider(
                        height: 1,
                        indent: 68,
                        color: Color(0xFFEEEEEE),
                      ),
                  ],
                );
              }),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF8F8F8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _NotificationSkeleton extends StatelessWidget {
  const _NotificationSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar skeleton
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),

                // Content skeleton
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Container(width: 150, height: 14, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(width: 80, height: 12, color: Colors.white),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Thumbnail skeleton
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;
  final ThemeProvider theme;
  final List<dynamic>? sessionUserFollowing;
  final VoidCallback onTap;
  final Function(int userId, bool wasFollowing) onFollowBack;

  const _NotificationTile({
    required this.notification,
    required this.theme,
    required this.sessionUserFollowing,
    required this.onTap,
    required this.onFollowBack,
  });

  @override
  Widget build(BuildContext context) {
    final entity = notification['entity'] ?? {};
    final initiatorData = entity['initiator_data'] ?? {};
    final entityDataRaw = entity['entity_data'];
    final Map<String, dynamic> entityData =
        entityDataRaw is Map<String, dynamic> ? entityDataRaw : {};

    final profileImage = initiatorData['profile_image'];
    final displayName = initiatorData['display_name'] ?? 'Unknown';
    final isVerified = initiatorData['user_verified'] == true;
    final message = _buildNotificationMessage(notification);
    final timeAgo = _formatTimeAgo(notification['date'] ?? '');
    final isRead = notification['is_read'] == '1';
    final isFollow = notification['type'] == 'follow';
    final postMedia = entityData['media'];

    final userId = initiatorData['id'] is int
        ? initiatorData['id'] as int
        : int.tryParse(initiatorData['id']?.toString() ?? '') ?? 0;

    final following = _isFollowing(userId);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isRead ? Colors.white : const Color(0xFFF8F8F8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(
              imageUrl: profileImage,
              radius: 22,
              onTap: () =>
                  _navigateToProfile(context, initiatorData, displayName),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMessageContent(
                    context,
                    displayName,
                    isVerified,
                    message,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeAgo,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildRightWidget(isFollow, following, userId, postMedia),
          ],
        ),
      ),
    );
  }

  bool _isFollowing(int userId) {
    if (sessionUserFollowing == null) return false;
    return sessionUserFollowing!.any((id) {
      if (id is int) return id == userId;
      if (id is String) return int.tryParse(id) == userId;
      return false;
    });
  }

  void _navigateToProfile(
    BuildContext context,
    Map initiatorData,
    String displayName,
  ) {
    Navigator.pushNamed(
      context,
      '/view-profile',
      arguments: {'userId': initiatorData['id'], 'username': displayName},
    );
  }

  Widget _buildMessageContent(
    BuildContext context,
    String displayName,
    bool isVerified,
    String message,
  ) {
    return Row(
      children: [
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: displayName,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (isVerified) ...[
                  const WidgetSpan(child: SizedBox(width: 4)),
                  WidgetSpan(
                    child: Icon(
                      Icons.verified,
                      size: 14,
                      color: theme.primaryColor,
                    ),
                  ),
                ],
                if (notification['type'] != 'comment') ...[
                  const WidgetSpan(child: SizedBox(width: 6)),
                  TextSpan(
                    text: message.substring(displayName.length),
                    style: const TextStyle(color: Colors.black87, fontSize: 14),
                  ),
                ] else ...[
                  const TextSpan(text: ' ', style: TextStyle(fontSize: 14)),
                  WidgetSpan(
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width - 140,
                      child: FormattedText(
                        text: message.substring(displayName.length),
                        showAllText: false,
                        maxTextLength: 100,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRightWidget(
    bool isFollow,
    bool following,
    int userId,
    dynamic postMedia,
  ) {
    if (isFollow) {
      return ElevatedButton(
        onPressed: () => onFollowBack(userId, following),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(
          following ? 'Following' : 'Follow',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      );
    } else if (postMedia != null && postMedia.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          postMedia,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 50,
            height: 50,
            color: Colors.grey.shade300,
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // ✅ OPTIMIZE - Cache these helper methods
  static String _buildNotificationMessage(Map<String, dynamic> notification) {
    final type = notification['type']?.toString() ?? '';
    final entity = (notification['entity'] is Map)
        ? Map<String, dynamic>.from(notification['entity'])
        : <String, dynamic>{};
    final initiator = (entity['initiator_data'] is Map)
        ? Map<String, dynamic>.from(entity['initiator_data'])
        : <String, dynamic>{};
    final name =
        (initiator['display_name']?.toString().trim().isNotEmpty ?? false)
        ? initiator['display_name'].toString()
        : 'User';
    final entityType = entity['entity_type']?.toString();
    final rawEntityData = entity['entity_data'];
    final Map<String, dynamic> entityData = rawEntityData is Map
        ? Map<String, dynamic>.from(rawEntityData)
        : <String, dynamic>{};

    String ellipsis(String s, int max) =>
        s.length <= max ? s : '${s.substring(0, max)}...';

    String typeLabel(String? t) {
      switch (t) {
        case 'comment':
          return 'comment';
        case 'car':
          return 'car';
        case 'post':
        case 'tag':
          return 'post';
        default:
          return 'post';
      }
    }

    switch (type) {
      case 'like':
        final comment = entityData['comment']?.toString();
        final base = '$name liked your ${typeLabel(entityType)}';
        return comment != null && comment.trim().isNotEmpty
            ? '$base: "$comment"'
            : base;

      case 'comment':
        final comment = entityData['comment']?.toString() ?? '';
        final snippet = ellipsis(comment, 50);
        return snippet.isEmpty
            ? '$name commented on your post'
            : '$name commented on your post: "$snippet"';

      case 'follow':
        return '$name followed you';

      case 'mention':
        final comment = entityData['comment']?.toString();
        final base = '$name mentioned you in a ${typeLabel(entityType)}';
        return comment != null && comment.trim().isNotEmpty
            ? '$base: "$comment"'
            : base;

      case 'post':
        final taggedTarget = entityType == 'car' ? 'your car' : 'you';
        return '$name has tagged $taggedTarget in a post';

      case 'tag':
        return entityType == 'car'
            ? '$name tagged your car in a post'
            : '$name tagged you in a post';

      default:
        return '$name interacted with your content';
    }
  }

  static String _formatTimeAgo(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays > 365) {
        final years = (diff.inDays / 365).floor();
        return '${years}y ago';
      } else if (diff.inDays > 30) {
        final months = (diff.inDays / 30).floor();
        return '${months}mo ago';
      } else if (diff.inDays > 0) {
        return '${diff.inDays}d ago';
      } else if (diff.inHours > 0) {
        return '${diff.inHours}h ago';
      } else if (diff.inMinutes > 0) {
        return '${diff.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }
}
