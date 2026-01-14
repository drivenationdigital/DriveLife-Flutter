import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/reels_screen.dart';
import 'package:drivelife/services/qr_scanner.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'posts_screen.dart';
import 'search_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';

class HomeTabs extends StatefulWidget {
  const HomeTabs({super.key});

  @override
  State<HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<HomeTabs> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    PostsScreen(),
    SearchScreen(),
    // ReelsScreen(),
    Scaffold(body: Center(child: Text('Add Post'))),
    Scaffold(body: Center(child: Text('Store'))),
    ProfileScreen(),
  ];

  void _goToTab(int idx) {
    setState(() => _currentIndex = idx);
    Navigator.pop(context); // close drawer after tap
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
        title: Image.asset(
          'assets/logo-dark.png',
          height: 18,
          alignment: Alignment.center,
        ),
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
            icon: Icon(Icons.qr_code, color: Colors.black),
          ),
          IconButton(
            onPressed: () {
              NavigationHelper.navigateTo(context, const NotificationsScreen());
            },
            icon: const Icon(Icons.notifications_none, color: Colors.black),
          ),
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
            icon: Icon(Icons.qr_code, color: Colors.black),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black),
            onPressed: () => NavigationHelper.navigateTo(
              context,
              const NotificationsScreen(),
            ),
          ),
        ],
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      // 👇 The Drawer (left sidebar)
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                margin: EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: Colors.black87),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'DriveLife',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                leading: const Icon(Icons.add_box_outlined),
                title: const Text('Add Post'),
                onTap: () => _goToTab(2),
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
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),

      appBar: _buildAppBar(),

      body: IndexedStack(index: _currentIndex, children: _screens),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            label: 'Discover',
          ),
          // BottomNavigationBarItem(
          //   icon: Icon(Icons.play_circle_outline),
          //   label: 'Reels',
          // ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            label: 'Add',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.store_outlined),
            label: 'Store',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
