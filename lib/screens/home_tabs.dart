import 'dart:async';

import 'package:drivelife/api/notifications_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/create_post_screen.dart';
import 'package:drivelife/screens/profile/edit_profile_settings_screen.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/services/qr_scanner.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/routes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'posts_screen.dart';
import 'search_screen.dart';
import 'profile/profile_screen.dart';
import 'notifications_screen.dart';

class HomeTabs extends StatefulWidget {
  const HomeTabs({super.key});

  @override
  State<HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<HomeTabs> {
  int _currentIndex = 0;
  String? _currentProfileImageUrl;
  int _notifCount = 0;
  bool _notifLoading = false;
  // Timer? _notifTimer;

  final _authService = AuthService();

  final List<Widget> _screens = const [
    PostsScreen(),
    SearchScreen(),
    SizedBox.shrink(), // Placeholder for add button (won't be shown)
    Scaffold(body: Center(child: Text('Store'))),
    ProfileScreen(),
  ];

  void _goToTab(int idx) {
    setState(() => _currentIndex = idx);
    Navigator.pop(context); // close drawer after tap
  }

  @override
  void initState() {
    super.initState();
    _loadProfileImage();
    _refreshNotificationCount();

    // _notifTimer = Timer.periodic(const Duration(minutes: 1), (_) {
    //   if (mounted) {
    //     _refreshNotificationCount();
    //   }
    // });
  }

  void _loadProfileImage() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (mounted && user != null && user['profile_image'] != null) {
      setState(() {
        _currentProfileImageUrl = user['profile_image'];
      });
    }
  }

  Future<void> _refreshNotificationCount() async {
    if (_notifLoading) return;
    _notifLoading = true;

    try {
      final res = await NotificationsAPI.getNotificationCount();
      if (!mounted) return;
      setState(() => _notifCount = res);
    } catch (_) {
      // ignore
    } finally {
      _notifLoading = false;
    }
  }

  Widget _notificationIconButton() {
    return IconButton(
      padding: const EdgeInsets.only(right: 12),
      iconSize: 24,
      onPressed: () async {
        await NavigationHelper.navigateTo(context, const NotificationsScreen());
        // refresh after coming back (so count updates after reading)
        if (mounted) _refreshNotificationCount();
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none, color: Colors.black),
          if (_notifCount > 0)
            Positioned(
              right: -5,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  _notifCount > 99 ? '99+' : '$_notifCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Show add menu popup
  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.post_add, color: Colors.blue),
                  title: const Text('Add Post'),
                  onTap: () {
                    Navigator.pop(context); // Close bottom sheet
                    NavigationHelper.navigateTo(
                      context,
                      const CreatePostScreen(),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.directions_car,
                    color: Colors.green,
                  ),
                  title: const Text('Add Vehicle'),
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navigate to add vehicle screen
                    // NavigationHelper.navigateTo(context, const AddVehicleScreen());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Add Vehicle - Coming soon!'),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.event, color: Colors.orange),
                  title: const Text('Add Event'),
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navigate to add event screen
                    // NavigationHelper.navigateTo(context, const AddEventScreen());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Add Event - Coming soon!')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleLogout() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      print('🚪 [HomeTabs] Logging out...');

      // Clear auth token
      await _authService.logout();

      // Clear user from provider
      if (mounted) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        userProvider.clearUser();
      }

      print('✅ [HomeTabs] Logout successful');

      // Navigate to login and clear navigation stack
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.login,
          (route) => false, // Remove all routes
        );
      }
    } catch (e) {
      print('❌ [HomeTabs] Logout error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  AppBar? _buildAppBar() {
    if (_currentIndex == 0) {
      // Home app bar
      return AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        // Use a Builder so Scaffold.of(context).openDrawer() has the right context
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.black),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        centerTitle: true, // 👈 ensures the title is centered
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          IconButton(
            onPressed: () async {
              final result = await QrScannerService.showScanner(context);
              if (result != null && mounted) {
                QrScannerService.handleScanResult(
                  context,
                  result,
                  onSuccess: (data) {
                    // Navigate based on entity type
                    if (data['entity_type'] == 'profile') {
                      Navigator.pushNamed(
                        context,
                        '/view-profile',
                        arguments: {'userId': data['entity_id']},
                      );
                    } else if (data['entity_type'] == 'vehicle') {
                      Navigator.pushNamed(
                        context,
                        '/vehicle-detail',
                        arguments: {'garageId': data['entity_id'].toString()},
                      );
                    }
                  },
                );
              }
            },
            icon: const Icon(Icons.qr_code, color: Colors.black),
          ),
          _notificationIconButton(),
        ],
      );
    } else if (_currentIndex == 4) {
      // Profile app bar (no hamburger, add QR icon)
      return AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.black),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          IconButton(
            onPressed: () async {
              final result = await QrScannerService.showScanner(context);
              if (result != null && mounted) {
                QrScannerService.handleScanResult(
                  context,
                  result,
                  onSuccess: (data) {
                    // Navigate based on entity type
                    if (data['entity_type'] == 'profile') {
                      Navigator.pushNamed(
                        context,
                        '/view-profile',
                        arguments: {'userId': data['entity_id']},
                      );
                    } else if (data['entity_type'] == 'vehicle') {
                      Navigator.pushNamed(
                        context,
                        '/vehicle-detail',
                        arguments: {'garageId': data['entity_id'].toString()},
                      );
                    }
                  },
                );
              }
            },
            icon: const Icon(Icons.qr_code, color: Colors.black),
          ),
          _notificationIconButton(),
        ],
      );
    }
    return null;
  }

  Widget _buildProfileIcon(String? url) {
    final hasUrl = (url != null && url.trim().isNotEmpty);

    if (!hasUrl) {
      return const Icon(Icons.person_outline);
    }

    return CircleAvatar(
      radius: 16,
      backgroundColor: Colors.transparent,
      backgroundImage: NetworkImage(url!),
      onBackgroundImageError: (_, __) {
        // Optional: fallback if URL fails
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      // 👇 The Drawer (left sidebar)
      drawer: Drawer(
        backgroundColor: theme.cardColor,
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: theme.cardColor),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset('assets/logo-dark.png', height: 24),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Home'),
                onTap: () => _goToTab(0),
              ),
              ListTile(
                leading: const Icon(Icons.explore_outlined),
                title: const Text('Discover'),
                onTap: () => _goToTab(1),
              ),
              ListTile(
                leading: const Icon(Icons.store_outlined),
                title: const Text('Store'),
                onTap: () => _goToTab(3),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Profile'),
                onTap: () => _goToTab(4),
              ),
              const Divider(),
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, child) {
                  return ListTile(
                    leading: Icon(
                      themeProvider.isDarkMode
                          ? Icons.dark_mode
                          : Icons.light_mode,
                    ),
                    title: const Text('Dark Mode'),
                    trailing: Switch(
                      value: themeProvider.isDarkMode,
                      onChanged: (value) {
                        themeProvider.toggleTheme();
                      },
                      activeColor: theme.primaryColor,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_none),
                title: const Text('Notifications'),
                onTap: () {
                  Navigator.pop(context);
                  NavigationHelper.navigateTo(
                    context,
                    const NotificationsScreen(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  NavigationHelper.navigateTo(
                    context,
                    const EditProfileSettingsScreen(),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => _handleLogout(),
              ),
            ],
          ),
        ),
      ),

      appBar: _buildAppBar(),

      body: IndexedStack(index: _currentIndex, children: _screens),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        backgroundColor: Colors.white,
        selectedItemColor: theme.primaryColor,
        unselectedItemColor: Colors.grey,
        iconSize: 28,
        currentIndex: _currentIndex,
        onTap: (index) {
          // If add button (index 2) is tapped, show menu instead of navigating
          if (index == 2) {
            _showAddMenu();
          } else {
            setState(() => _currentIndex = index);
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: ''),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            label: '',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.store_outlined), label: ''),
          BottomNavigationBarItem(
            icon: _buildProfileIcon(_currentProfileImageUrl),
            label: '',
          ),
        ],
      ),
    );
  }
}
