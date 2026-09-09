import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/main.dart';
import 'package:drivelife/models/account_model.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/location_access_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/auth/entity_switcher.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/screens/clubs/add_club_screen.dart';
import 'package:drivelife/screens/clubs/club_creation_screen.dart';
import 'package:drivelife/screens/clubs/my_clubs_screen.dart';
import 'package:drivelife/screens/events/add_event_screen.dart';
import 'package:drivelife/screens/create-post/create_post_screen.dart';
import 'package:drivelife/screens/events/events_screen.dart';
import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/screens/places/add_venue_screen.dart';
import 'package:drivelife/screens/places/places_screen.dart';
import 'package:drivelife/screens/profile/my_club_profile_view.dart';
import 'package:drivelife/screens/news/create_news_post_screen.dart';
import 'package:drivelife/config/feature_flags.dart';
import 'package:drivelife/screens/media/new_gallery_screen.dart';
import 'package:drivelife/screens/media/media_screen.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/services/firebase_messaging_service.dart';
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
  // int _currentIndex = 0;
  AccountType? _lastAccountType;

  // Provider-backed current tab. All existing _currentIndex references keep working.
  int get _currentIndex => context.read<BottomNavProvider>().currentIndex;

  // Tab order: Home, Events, Places, Clubs, [Media], Profile.
  // _buildBottomNav's items and the screens list in _buildScreens must both
  // follow it. The shop is reached from the header basket button, not a tab.
  static const int _mediaIndex = 4;

  /// Profile is always the last tab. Derived rather than written down, because
  /// a hard-coded literal goes stale the moment a tab is added or hidden and
  /// silently points the account switcher and avatar highlight at the wrong
  /// tab. Only read while [_screens] is non-empty — build() returns early
  /// otherwise, so the nav never sees an empty list.
  int get _profileIndex => _screens.length - 1;
  void _setIndex(int index) =>
      context.read<BottomNavProvider>().setIndex(index);
  final GlobalKey<PostsScreenState> _postsScreenKey =
      GlobalKey<PostsScreenState>();

  final _authService = AuthService();

  List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();

    _buildScreens();
    _reloadUserData();

    // Single source of truth — checks once, all screens read from it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LocationAccessProvider>().refresh();
        FirebaseMessagingService.flushPendingDeepLink();
      }
    });
  }

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

  // After your WordPress login succeeds and you have a WP JWT:
  Future<void> onWordPressLoginSuccess(String wordpressJwt) async {
    print(
      '[HomeTabs] Supa onWordPressLoginSuccess called with JWT: $wordpressJwt',
    );
    // Exchange for a Supabase token
    await SupabaseTokenManager.fetchAndStore(wordpressJwt);
  }

  Future<void> _buildScreens() async {
    final accountManager = Provider.of<AccountManager>(context, listen: false);
    final currentAccount = accountManager.activeAccount;

    // ✅ Await the token BEFORE building any screens
    // if (currentAccount != null && currentAccount.token != '') {
    //   await onWordPressLoginSuccess(currentAccount.token);
    // }

    final List<Widget> screens;

    // Order must match the items in _buildBottomNav.
    screens = [
      PostsScreen(key: _postsScreenKey),
      EventsScreen(),
      VenuesScreen(),
      MyClubsScreen(),
      // InboxScreen(myUserId: currentAccount!.user.id.toString()),
      if (FeatureFlags.mediaTab) MediaScreen(),
      if (currentAccount?.isClubAccount ?? false)
        ClubProfileScreen()
      else
        ProfileScreen(),
    ];

    if (mounted) setState(() => _screens = screens);
  }

  void _reloadUserData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadUser();
    });
  }

  // ignore: unused_element
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

  /// The Create sheet behind the header's plus button.
  ///
  /// A grid of cards rather than a list of rows: these are six equal choices
  /// made a few times a week, and a stacked list made them read as a settings
  /// menu — the eye has to travel the whole column to find the one it wants.
  void _showAddMenu(ThemeProvider theme) {
    final accountManager = Provider.of<AccountManager>(context, listen: false);

    final isUser = accountManager.activeAccount?.isUserAccount ?? false;
    final isAdmin = accountManager.activeAccount?.user.isAdmin ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        // Club and vehicle belong to a person, not to a club or venue account;
        // an event or a venue can be made by either.
        final actions = <_CreateAction>[
          if (isUser)
            _CreateAction(
              label: 'Add Post',
              icon: Icons.image_outlined,
              onTap: () => NavigationHelper.navigateTo(
                context,
                const CreatePostScreen(),
              ),
            ),
          if (isUser)
            _CreateAction(
              label: 'Add Gallery',
              icon: Icons.collections_outlined,
              onTap: () => NavigationHelper.navigateTo(
                context,
                const NewGalleryScreen(),
              ),
            ),
          if (isUser)
            _CreateAction(
              label: 'Add Club',
              svg: 'assets/app-icons/06-Clubs.svg',
              onTap: _createClub,
            ),
          if (isUser)
            _CreateAction(
              label: 'Add Vehicle',
              icon: Icons.directions_car_outlined,
              onTap: () => NavigationHelper.navigateTo(
                context,
                const AddVehicleScreen(),
              ),
            ),
          _CreateAction(
            label: 'Add Event',
            icon: Icons.calendar_today_outlined,
            onTap: () =>
                NavigationHelper.navigateTo(context, const AddEventScreen()),
          ),
          _CreateAction(
            label: 'Add Venue',
            icon: Icons.place_outlined,
            onTap: () =>
                NavigationHelper.navigateTo(context, const CreateVenueScreen()),
          ),
          if (isUser && isAdmin)
            _CreateAction(
              label: 'Add News',
              icon: Icons.article_outlined,
              onTap: () => NavigationHelper.navigateTo(
                context,
                const CreateNewsScreen(),
              ),
            ),
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                Row(
                  children: [
                    Text(
                      'Create',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: theme.textColor,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => Navigator.pop(sheetContext),
                      customBorder: const CircleBorder(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: theme.textColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                LayoutBuilder(
                  builder: (context, constraints) {
                    // Two per row, worked out from the width actually
                    // available so an odd number of actions leaves a
                    // half-width gap rather than stretching the last card.
                    const gap = 12.0;
                    final cardWidth = (constraints.maxWidth - gap) / 2;

                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final action in actions)
                          SizedBox(
                            width: cardWidth,
                            child: _CreateCard(
                              action: action,
                              theme: theme,
                              onTap: () {
                                Navigator.pop(sheetContext);
                                action.onTap();
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0B0B0B),
                      minimumSize: const Size.fromHeight(58),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      SharedHeaderIcons.scanQrCode(context);
                    },
                    icon: SvgPicture.asset(
                      'assets/app-icons/header-qr.svg',
                      width: 22,
                      height: 22,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                    label: const Text(
                      'Scan QR Code',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Picking a club type comes first, and only then the edit screen.
  Future<void> _createClub() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ClubTypeSelectionSheet(),
    );

    if (!mounted || result == null || result['clubId'] == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CreateClubScreen(existingClubId: result['clubId']),
      ),
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
            icon: iconSvg(
              'assets/app-icons/header-plus.svg',
              theme,
              size: 20,
              alwaysActive: true,
            ),
            onPressed: () => _showAddMenu(theme),
          ),
          SharedHeaderIcons.storeIcon(),
        ],
      ),
      title: Image.asset('assets/logo-dark.png', height: 18),
      actions: [
        IconButton(
          icon: iconSvg(
            'assets/app-icons/header-search.svg',
            theme,
            size: 20,
            alwaysActive: true,
          ),
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
    final theme = Provider.of<ThemeProvider>(context);

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
                    // 12 = the 24px the SVG icons use. Anything taller makes
                    // this item taller and its label drop out of line.
                    radius: 12,
                    backgroundColor: Colors.transparent,
                    backgroundImage: CachedNetworkImageProvider(url),
                    onBackgroundImageError: (_, __) {},
                  )
                : iconSvg(
                    'assets/app-icons/05-User.svg',
                    null,
                    size: 24,
                    alwaysActive: true,
                  ),
          );
        }

        // Show user icon for user accounts
        final url = account.user.profileImage;
        final hasUrl = (url != null && url.trim().isNotEmpty);

        return GestureDetector(
          onLongPress: () => _showAccountSwitcher(),
          child: hasUrl
              ? CircleAvatar(
                  // Matches the 24px of every other nav icon.
                  radius: 12,
                  backgroundColor: Colors.transparent,
                  backgroundImage: CachedNetworkImageProvider(url),
                  onBackgroundImageError: (_, __) {},
                )
              : iconSvg(
                  'assets/app-icons/05-User.svg',
                  theme,
                  size: 24,
                  isActive: _currentIndex == _profileIndex,
                ),
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
            ? (themeProvider?.primaryColor ?? Colors.black)
            : alwaysActive
            ? Colors.black
            : Colors.grey,
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
      selectedFontSize: 12,
      iconSize: 28,
      currentIndex: _currentIndex,
      onTap: (index) {
        final current = _currentIndex; // snapshot before mutating

        if (index == _profileIndex && current == _profileIndex) {
          _showAccountSwitcher();
          HapticFeedback.lightImpact();
          return;
        }

        if (index == 0 && current == 0) {
          _postsScreenKey.currentState?.scrollToTopAndRefresh();
          HapticFeedback.lightImpact();
          return;
        }

        _setIndex(index);
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
          icon: iconSvg(
            'assets/app-icons/06-Clubs.svg',
            theme,
            isActive: _currentIndex == 3,
          ),
          label: 'Clubs',
        ),
        if (FeatureFlags.mediaTab)
          BottomNavigationBarItem(
            icon: iconSvg(
              // Lowercase p: this must match the file on disk exactly, since
              // the asset bundle is case-sensitive on device.
              'assets/app-icons/06-photo.svg',
              theme,
              isActive: _currentIndex == _mediaIndex,
            ),
            label: 'Photos',
          ),
        BottomNavigationBarItem(icon: _buildProfileIcon(), label: 'Profile'),

        // BottomNavigationBarItem(
        //   icon: Consumer<UnreadCountProvider>(
        //     builder: (context, unread, child) {
        //       final count = unread.count;
        //       final icon = const Icon(Icons.chat_bubble_outline);
        //       if (count > 0) {
        //         return Badge(
        //           backgroundColor: theme.primaryColor,
        //           label: Text(count > 99 ? '99+' : '$count'),
        //           child: icon,
        //         );
        //       }
        //       return icon;
        //     },
        //   ),
        //   label: 'Chat',
        // ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final accountManager = Provider.of<AccountManager>(context);

    // Subscribe so the scaffold rebuilds when the active tab changes.
    context.watch<BottomNavProvider>();

    // ✅ Rebuild screens if account type changes
    final currentAccountType = accountManager.activeAccount?.accountType;
    if (currentAccountType != _lastAccountType) {
      _lastAccountType = currentAccountType;
      _buildScreens();
    }

    // Safety check
    if (_screens.isEmpty) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    return PopScope(
      canPop: _currentIndex == 0, // Only allow pop if on home tab
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 0) {
          // If we didn't pop and we're not on home, go to home
          _setIndex(0);
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

/// One choice in the Create sheet.
class _CreateAction {
  final String label;

  /// A Material icon, or [svg] for one of the app's own.
  final IconData? icon;
  final String? svg;

  final VoidCallback onTap;

  const _CreateAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.svg,
  });
}

class _CreateCard extends StatelessWidget {
  final _CreateAction action;
  final ThemeProvider theme;
  final VoidCallback onTap;

  const _CreateCard({
    required this.action,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.isDarkMode ? Colors.white10 : const Color(0xFFF4F4F4),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.isDarkMode ? Colors.white12 : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: action.svg != null
                      ? SvgPicture.asset(
                          action.svg!,
                          width: 22,
                          height: 22,
                          colorFilter: ColorFilter.mode(
                            theme.primaryColor,
                            BlendMode.srcIn,
                          ),
                        )
                      : Icon(action.icon, size: 24, color: theme.primaryColor),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: theme.textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
