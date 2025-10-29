import 'package:flutter/material.dart';
import '../api/notifications_api.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? notifications;
  bool loading = true;

  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0), // Slide from right
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final data = await NotificationsAPI.getUserNotifications();
    setState(() {
      notifications = data;
      loading = false;
    });

    // Start the slide-in animation
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildSection(String title, List<dynamic> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        ...items.map(
          (n) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: CircleAvatar(
              backgroundImage: NetworkImage(n['sender_image'] ?? ''),
            ),
            title: Text(
              n['message'] ?? '',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              n['time_ago'] ?? '',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onTap: () {
              // TODO: handle notification click
            },
          ),
        ),
        const Divider(color: Colors.white10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.95),
      body: SlideTransition(
        position: _slideAnimation,
        child: SafeArea(
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Notifications',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (notifications == null)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 80),
                            child: Text(
                              'No notifications found',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        )
                      else ...[
                        _buildSection('Recent', notifications!['recent'] ?? []),
                        _buildSection(
                          'This Week',
                          notifications!['last_week'] ?? [],
                        ),
                        _buildSection(
                          'Last 30 Days',
                          notifications!['last_30_days'] ?? [],
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
