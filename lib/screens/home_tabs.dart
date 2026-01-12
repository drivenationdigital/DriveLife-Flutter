import 'package:drivelife/screens/reels_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
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
    ReelsScreen(),
    Scaffold(body: Center(child: Text('Add Post'))),
    Scaffold(body: Center(child: Text('Store'))),
    ProfileScreen(),
  ];

  void _goToTab(int idx) {
    setState(() => _currentIndex = idx);
    Navigator.pop(context); // close drawer after tap
  }

  @override
  Widget build(BuildContext context) {
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
              ListTile(
                leading: const Icon(Icons.notifications_none),
                title: const Text('Notifications'),
                onTap: () {
                  Navigator.pop(context);
                  NavigationHelper.navigateModal(
                    context,
                    const NotificationsScreen(),
                  );
                  // Navigator.of(context).push(
                  //   PageRouteBuilder(
                  //     opaque: false,
                  //     barrierColor: Colors.black54,
                  //     pageBuilder: (_, __, ___) => const NotificationsScreen(),
                  //     transitionsBuilder: (_, animation, __, child) =>
                  //         SlideTransition(
                  //           position:
                  //               Tween<Offset>(
                  //                 begin: const Offset(1, 0),
                  //                 end: Offset.zero,
                  //               ).animate(
                  //                 CurvedAnimation(
                  //                   parent: animation,
                  //                   curve: Curves.easeOutCubic,
                  //                 ),
                  //               ),
                  //           child: child,
                  //         ),
                  //   ),
                  // );
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

      appBar: _currentIndex == 0
          ? AppBar(
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
                  onPressed: () {
                    // Navigator.of(context).push(
                    //   PageRouteBuilder(
                    //     opaque: false,
                    //     barrierColor: Colors.black54,
                    //     pageBuilder: (_, __, ___) =>
                    //         const NotificationsScreen(),
                    //     transitionsBuilder: (_, animation, __, child) =>
                    //         SlideTransition(
                    //           position:
                    //               Tween<Offset>(
                    //                 begin: const Offset(1, 0),
                    //                 end: Offset.zero,
                    //               ).animate(
                    //                 CurvedAnimation(
                    //                   parent: animation,
                    //                   curve: Curves.easeOutCubic,
                    //                 ),
                    //               ),
                    //           child: child,
                    //         ),
                    //   ),
                    // );
                    NavigationHelper.navigateModal(
                      context,
                      const NotificationsScreen(),
                    );
                  },
                  icon: const Icon(
                    Icons.notifications_none,
                    color: Colors.black,
                  ),
                ),
              ],
            )
          : null,

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
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle_outline),
            label: 'Reels',
          ),
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
