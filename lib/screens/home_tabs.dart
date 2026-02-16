import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/cart_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/auth/account_switcher.dart';
import 'package:drivelife/screens/clubs/add_club_screen.dart';
import 'package:drivelife/screens/clubs/club_creation_screen.dart';
import 'package:drivelife/screens/clubs/my_clubs_screen.dart';
import 'package:drivelife/screens/events/add_event_screen.dart';
import 'package:drivelife/screens/create-post/create_post_screen.dart';
import 'package:drivelife/screens/events/events_screen.dart';
import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/screens/places/add_venue_screen.dart';
import 'package:drivelife/screens/places/places_screen.dart';
import 'package:drivelife/screens/store/shop_screen.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/widgets/shared_header_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'posts_screen.dart';
import 'profile/profile_screen.dart';

class HomeTabs extends StatefulWidget {
  const HomeTabs({super.key});

  @override
  State<HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<HomeTabs> {
  int _currentIndex = 0;

  // ============================================================================
  // GLOBAL KEY - Access posts screen state
  // ============================================================================
  final GlobalKey<PostsScreenState> _postsScreenKey =
      GlobalKey<PostsScreenState>();

  final _authService = AuthService();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();

    _screens = [
      PostsScreen(key: _postsScreenKey),
      EventsScreen(),
      VenuesScreen(),
      MyClubsScreen(),
      ShopScreen(),
      ProfileScreen(),
    ];
    _reloadUserData();
  }

  void _reloadUserData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadUser();
    });
  }

  // Show add menu popup
  void _showAddMenu(ThemeProvider theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
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
                  leading: Icon(Icons.photo, color: theme.primaryColor),
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
                  leading: Icon(
                    Icons.directions_car,
                    color: theme.primaryColor,
                  ),
                  title: const Text('Add Vehicle'),
                  onTap: () {
                    Navigator.pop(context);
                    NavigationHelper.navigateTo(
                      context,
                      const AddVehicleScreen(),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.event, color: theme.primaryColor),
                  title: const Text('Add Event'),
                  onTap: () {
                    Navigator.pop(context);
                    NavigationHelper.navigateTo(
                      context,
                      const AddEventScreen(),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.place_outlined,
                    color: theme.primaryColor,
                  ),
                  title: const Text('Add Venue'),
                  onTap: () {
                    Navigator.pop(context);
                    NavigationHelper.navigateTo(
                      context,
                      const CreateVenueScreen(),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.place_outlined,
                    color: theme.primaryColor,
                  ),
                  title: const Text('Add Club'),
                  onTap: () async {
                    Navigator.pop(context);

                    // Show bottom sheet first
                    final result =
                        await showModalBottomSheet<Map<String, dynamic>>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const ClubTypeSelectionSheet(),
                        );

                    // If club was created, navigate to edit screen
                    if (result != null && result['clubId'] != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CreateClubScreen(
                            existingClubId: result['clubId'],
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Default app bar for all tabs
  AppBar? _buildAppBar(ThemeProvider theme) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      leadingWidth: 96,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black),
            onPressed: () => _showAddMenu(theme),
          ),
          SharedHeaderIcons.qrCodeIcon(),
        ],
      ),
      title: Image.asset('assets/logo-dark.png', height: 18),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: Colors.black),
          onPressed: () {
            Navigator.pushNamed(context, AppRoutes.search);
          },
        ),
        // ✅ Using the actionIcons helper for multiple icons at once
        ...SharedHeaderIcons.actionIcons(
          iconColor: Colors.black,
          showQr: false, // Already shown in leading
          showNotifications: true,
        ),
      ],
    );
  }

  Widget _buildProfileIcon() {
    return Consumer<AccountManager>(
      builder: (context, accountManager, child) {
        final user = accountManager.activeUser;
        final url = user?.profileImage;
        final hasUrl = (url != null && url.trim().isNotEmpty);

        return GestureDetector(
          onLongPress: () => _showAccountSwitcher(),
          child: hasUrl
              ? CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.transparent,
                  backgroundImage: NetworkImage(url!),
                  onBackgroundImageError: (_, __) {},
                )
              : const Icon(Icons.person_outline),
        );
      },
    );
  }

  void _showAccountSwitcher() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const AccountSwitcherSheet(),
    );
  }

  Widget _buildBottomNav(ThemeProvider theme) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: theme.primaryColor,
      unselectedItemColor: Colors.grey,
      iconSize: 28,
      currentIndex: _currentIndex,
      onTap: (index) {
        // Special handling for profile tab (index 5)
        if (index == 5 && _currentIndex == 5) {
          _showAccountSwitcher();
          HapticFeedback.lightImpact();
          return;
        }

        // Home tab double-tap refresh
        if (index == 0 && _currentIndex == 0) {
          _postsScreenKey.currentState?.scrollToTopAndRefresh();
          HapticFeedback.lightImpact();
          return;
        }

        setState(() => _currentIndex = index);
      },
      items: [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.event), label: 'Events'),
        BottomNavigationBarItem(
          icon: Icon(Icons.place_outlined),
          label: 'Places',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.car_repair_outlined),
          label: 'Clubs',
        ),
        BottomNavigationBarItem(
          icon: Consumer<CartProvider>(
            builder: (context, cart, child) {
              final count = cart.itemCount;
              if (_currentIndex != 4 && count > 0) {
                return Badge(
                  backgroundColor: theme.primaryColor,
                  label: Text('$count'),
                  child: Icon(Icons.store_outlined),
                );
              }
              return Icon(Icons.store_outlined);
            },
          ),
          label: 'Store',
        ),
        BottomNavigationBarItem(icon: _buildProfileIcon(), label: 'Profile'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return PopScope(
      canPop: _currentIndex == 0, // Only allow pop if on home tab
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 0) {
          // If we didn't pop and we're not on home, go to home
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        //         Consumer<ThemeProvider>(
        //           builder: (context, themeProvider, child) {
        //             return ListTile(
        //               leading: Icon(
        //                 themeProvider.isDarkMode
        //                     ? Icons.dark_mode
        //                     : Icons.light_mode,
        //               ),
        //               title: const Text('Dark Mode'),
        //               trailing: Switch(
        //                 value: themeProvider.isDarkMode,
        //                 onChanged: (value) {
        //                   themeProvider.toggleTheme();
        //                 },
        //                 activeColor: theme.primaryColor,
        //               ),
        //             );
        //           },
        //         ),
        //
        appBar: _buildAppBar(theme),
        body: IndexedStack(index: _currentIndex, children: _screens),
        bottomNavigationBar: _buildBottomNav(theme),
      ),
    );
  }
}
