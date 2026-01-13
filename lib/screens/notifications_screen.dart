import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/notifications_api.dart';
import '../widgets/profile_avatar.dart';
import '../services/auth_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final AuthService _auth = AuthService();

  List<dynamic> _allNotifications = [];
  Map<String, List<dynamic>> _groupedNotifications = {};
  bool _loading = true;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications({bool loadOld = false}) async {
    if (!mounted) return;

    setState(() => _loading = true);

    final response = await NotificationsAPI.getUserNotifications(
      loadOldNotifications: loadOld,
    );

    if (!mounted) return;

    if (response != null) {
      final data = response['data'] ?? response;

      final List<dynamic> notifications = [
        ...(data['recent'] ?? []),
        ...(data['last_week'] ?? []),
        ...(data['last_30_days'] ?? []),
      ];

      setState(() {
        _allNotifications = notifications;
        _groupedNotifications = _groupNotificationsByTime(notifications);
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

  // ✅ Group notifications by time periods
  Map<String, List<dynamic>> _groupNotificationsByTime(
    List<dynamic> notifications,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final Map<String, List<dynamic>> grouped = {
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'This Month': [],
      'Earlier': [],
    };

    for (final notification in notifications) {
      try {
        final dateStr = notification['date'] ?? '';
        final date = DateTime.parse(dateStr);
        final dateOnly = DateTime(date.year, date.month, date.day);

        final daysDifference = today.difference(dateOnly).inDays;

        if (daysDifference == 0) {
          // Today
          grouped['Today']!.add(notification);
        } else if (daysDifference == 1) {
          // Yesterday
          grouped['Yesterday']!.add(notification);
        } else if (daysDifference >= 2 && daysDifference <= 7) {
          // This Week (2-7 days ago)
          grouped['This Week']!.add(notification);
        } else if (daysDifference > 7 && daysDifference <= 30) {
          // This Month (8-30 days ago)
          grouped['This Month']!.add(notification);
        } else {
          // Earlier (more than 30 days ago)
          grouped['Earlier']!.add(notification);
        }
      } catch (e) {
        print('Error parsing notification date: $e');
        grouped['Earlier']!.add(notification);
      }
    }

    // Remove empty groups
    grouped.removeWhere((key, value) => value.isEmpty);

    return grouped;
  }

  Future<void> _refreshNotifications() async {
    await _loadNotifications();
  }

  String _buildNotificationMessage(Map<String, dynamic> notification) {
    final type = notification['type'];
    final initiatorData = notification['entity']?['initiator_data'] ?? {};
    final name = initiatorData['display_name'] ?? 'Someone';

    switch (type) {
      case 'follow':
        return '$name followed you';
      case 'like':
        return '$name liked your post';
      case 'comment':
        return '$name commented on your post';
      case 'mention':
        return '$name mentioned you';
      case 'tag':
        return '$name tagged you in a post';
      default:
        return '$name interacted with your content';
    }
  }

  String _formatTimeAgo(String dateStr) {
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

  Future<void> _handleFollowBack(int userId) async {
    // TODO: Implement follow user API
    print('Follow back user: $userId');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Image.asset('assets/logo-dark.png', height: 18),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : _allNotifications.isEmpty
          ? Center(
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
            )
          : RefreshIndicator(
              onRefresh: _refreshNotifications,
              color: theme.primaryColor,
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8),
                itemCount: _groupedNotifications.length,
                itemBuilder: (context, groupIndex) {
                  final groupName = _groupedNotifications.keys.elementAt(
                    groupIndex,
                  );
                  final groupNotifications = _groupedNotifications[groupName]!;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ Section Header
                      _buildSectionHeader(groupName),

                      // ✅ Notifications in this group
                      ...groupNotifications.asMap().entries.map((entry) {
                        final notification = entry.value;
                        final isLast =
                            entry.key == groupNotifications.length - 1;

                        return Column(
                          children: [
                            _buildNotificationTile(notification, theme),
                            if (!isLast)
                              const Divider(
                                height: 1,
                                indent: 68,
                                color: Color(0xFFEEEEEE),
                              ),
                          ],
                        );
                      }).toList(),

                      // Spacing after group
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
            ),
    );
  }

  // ✅ Section header widget
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

  Widget _buildNotificationTile(
    Map<String, dynamic> notification,
    ThemeProvider theme,
  ) {
    final entity = notification['entity'] ?? {};
    final initiatorData = entity['initiator_data'] ?? {};

    // ✅ entity_data can be Map or List (empty array)
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
    final postMedia = entityData['media']; // Now safe to access

    return InkWell(
      onTap: () => _handleNotificationTap(notification),
      child: Container(
        color: isRead ? Colors.white : const Color(0xFFF8F8F8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile avatar
            ProfileAvatar(
              imageUrl: profileImage,
              radius: 22,
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/view-profile',
                  arguments: {
                    'userId': initiatorData['id'],
                    'username': displayName,
                  },
                );
              },
            ),
            const SizedBox(width: 12),

            // Message content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                              TextSpan(
                                text:
                                    ' ${message.substring(displayName.length)}',
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

            // Right side: Follow button OR post thumbnail
            if (isFollow)
              ElevatedButton(
                onPressed: () => _handleFollowBack(initiatorData['id']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text(
                  'Follow',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              )
            else if (postMedia != null && postMedia.isNotEmpty)
              ClipRRect(
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
              ),
          ],
        ),
      ),
    );
  }
}
