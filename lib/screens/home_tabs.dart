import 'package:drivelife/models/account_model.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/cart_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/auth/entity_switcher.dart';
// import 'package:drivelife/screens/clubs/add_club_screen.dart';
// import 'package:drivelife/screens/clubs/club_creation_screen.dart';
// import 'package:drivelife/screens/clubs/my_clubs_screen.dart';
import 'package:drivelife/screens/events/add_event_screen.dart';
import 'package:drivelife/screens/create-post/create_post_screen.dart';
import 'package:drivelife/screens/events/events_screen.dart';
import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/screens/places/add_venue_screen.dart';
import 'package:drivelife/screens/places/places_screen.dart';
import 'package:drivelife/screens/profile/my_club_profile_view.dart';
import 'package:drivelife/screens/store/shop_screen.dart';
import 'package:drivelife/screens/news/create_news_post_screen.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/widgets/shared_header_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  AccountType? _lastAccountType;

  // ============================================================================
  // GLOBAL KEY - Access posts screen state
  // ============================================================================
  final GlobalKey<PostsScreenState> _postsScreenKey =
      GlobalKey<PostsScreenState>();

  final _authService = AuthService();

  List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();

    _buildScreens();
    _reloadUserData();
    // _loadManagedEntities();
  }

  // In home_tabs.dart

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final accountManager = Provider.of<AccountManager>(context, listen: false);
    final currentAccount = accountManager.activeAccount;

    // Rebuild screens if account type changed
    final currentAccountType = currentAccount?.accountType;

    if (currentAccountType != _lastAccountType) {
      _lastAccountType = currentAccountType;
      _buildScreens();
    }
  }

  void _buildScreens() {
    final accountManager = Provider.of<AccountManager>(context, listen: false);
    final currentAccount = accountManager.activeAccount;

    print('🏗️ Building screens...');
    print('🏗️ Account type: ${currentAccount?.accountType}');
    print('🏗️ Is club account: ${currentAccount?.isClubAccount}');

    if (currentAccount?.isClubAccount ?? false) {
      print('✅ Building CLUB screens');
      // Club view - limited screens
      _screens = [
        PostsScreen(key: _postsScreenKey),
        EventsScreen(),
        VenuesScreen(),
        // MyClubsScreen(),
        ShopScreen(),
        ClubProfileScreen(),
      ];
    } else {
      print('✅ Building USER screens');
      // User view - full screens
      _screens = [
        PostsScreen(key: _postsScreenKey),
        EventsScreen(),
        VenuesScreen(),
        // MyClubsScreen(),
        ShopScreen(),
        ProfileScreen(),
      ];
    }

    if (mounted) setState(() {});
  }

  void _loadManagedEntities() async {
    final accountManager = Provider.of<AccountManager>(context, listen: false);
    final authService = AuthService();

    final activeAccount = accountManager.activeAccount;

    // ✅ Only load if we're on a USER account (not club/venue)
    if (activeAccount == null || !activeAccount.isUserAccount) {
      print('⏭️ Skipping entity load - not a user account');
      return;
    }

    final user = activeAccount.user;
    final token = await authService.getToken();

    if (token == null) return;

    // ✅ Check if we already have entities for this user
    final existingEntities = accountManager.getEntitiesForUser(user.id);

    if (existingEntities.isNotEmpty) {
      print(
        '✅ Already have ${existingEntities.length} entities for user ${user.id}',
      );
      // return;
    }

    print('🔄 Loading managed entities for user ${user.id}');
    await accountManager.loadManagedEntities(user.id, token);
  }

  void _reloadUserData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadUser();
    });
  }

  // Show add menu popup
  void _showAddMenu(ThemeProvider theme) {
    final accountManager = Provider.of<AccountManager>(context, listen: false);

    final isUser = accountManager.activeAccount?.isUserAccount ?? false;
    final isAdmin = accountManager.activeAccount?.user.isAdmin ?? false;

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
                if (isUser) ...[
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
                  if (isAdmin) ...[
                    ListTile(
                      leading: Icon(Icons.photo, color: theme.primaryColor),
                      title: const Text('Add News Blog'),
                      onTap: () {
                        Navigator.pop(context); // Close bottom sheet
                        NavigationHelper.navigateTo(
                          context,
                          const CreateNewsScreen(),
                        );
                      },
                    ),
                  ],
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
                  // ListTile(
                  //   leading: Icon(
                  //     Icons.place_outlined,
                  //     color: theme.primaryColor,
                  //   ),
                  //   title: const Text('Add Club'),
                  //   onTap: () async {
                  //     Navigator.pop(context);

                  //     // Show bottom sheet first
                  //     final result =
                  //         await showModalBottomSheet<Map<String, dynamic>>(
                  //           context: context,
                  //           isScrollControlled: true,
                  //           backgroundColor: Colors.transparent,
                  //           builder: (context) =>
                  //               const ClubTypeSelectionSheet(),
                  //         );

                  //     // If club was created, navigate to edit screen
                  //     if (result != null && result['clubId'] != null) {
                  //       Navigator.push(
                  //         context,
                  //         MaterialPageRoute(
                  //           builder: (context) => CreateClubScreen(
                  //             existingClubId: result['clubId'],
                  //           ),
                  //         ),
                  //       );
                  //     }
                  //   },
                  // ),
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
                ],
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
            icon: iconSvg('assets/app-icons/header-plus.svg', theme, size: 20, alwaysActive: true),
            onPressed: () => _showAddMenu(theme),
          ),
          SharedHeaderIcons.qrCodeIcon(),
        ],
      ),
      title: Image.asset('assets/logo-dark.png', height: 18),
      actions: [
        IconButton(
          icon: iconSvg('assets/app-icons/header-search.svg', theme, size: 20, alwaysActive: true),
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
        final account = accountManager.activeAccount;

        if (account == null) {
          return const Icon(Icons.person_outline);
        }

        // Show club icon for club accounts
        if (account.isClubAccount) {
          final url = account.user.profileImage;
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
                : const Icon(Icons.car_repair),
          );
        }

        // Show user icon for user accounts
        final url = account.user.profileImage;
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
    // _loadManagedEntities();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const EntitySwitcherSheet(),
    );
  }

  Widget iconSvg(
    String assetName,
    ThemeProvider? themeProvider, {
    double size = 24,
    bool isActive = false, 
    bool alwaysActive = false, // NEW: Force active color even if not selected
  }) {
    return SvgPicture.asset(
      assetName,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        isActive
            ? (themeProvider?.primaryColor ??
                  Colors.black)
            : alwaysActive ? Colors.black : Colors.grey,
        BlendMode.srcIn,
      ),
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
        // Special handling for profile tab (index 4)
        if (index == 4 && _currentIndex == 4) {
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
        BottomNavigationBarItem(
          icon: iconSvg(
            'assets/app-icons/01-Home.svg',
            theme,
            isActive: _currentIndex == 0,
          ),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: iconSvg(
            'assets/app-icons/02-Events.svg',
            theme,
            isActive: _currentIndex == 1,
          ),
          label: 'Events',
        ),
        BottomNavigationBarItem(
          icon: iconSvg(
            'assets/app-icons/03-Venues.svg',
            theme,
            isActive: _currentIndex == 2,
          ),
          label: 'Places',
        ),
        BottomNavigationBarItem(
          icon: Consumer<CartProvider>(
            builder: (context, cart, child) {
              final count = cart.itemCount;
              final icon = iconSvg(
                'assets/app-icons/04-Basket.svg',
                theme,
                isActive: _currentIndex == 3,
              );
              if (_currentIndex != 3 && count > 0) {
                return Badge(
                  backgroundColor: theme.primaryColor,
                  label: Text('$count'),
                  child: icon,
                );
              }
              return icon;
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
    final accountManager = Provider.of<AccountManager>(context);

    // ✅ Rebuild screens if account type changes
    final currentAccountType = accountManager.activeAccount?.accountType;
    if (currentAccountType != _lastAccountType) {
      _lastAccountType = currentAccountType;
      _buildScreens();
    }

    // Safety check
    if (_screens.isEmpty) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
