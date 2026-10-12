import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:drivelife/screens/store/shop_screen.dart';
import 'package:drivelife/screens/search_screen.dart';
import 'package:drivelife/screens/garage/garage_list_screen.dart';
import 'package:drivelife/widgets/nav/dl_bottom_nav.dart';
import 'package:drivelife/widgets/nav/dl_top_tabs.dart';
import 'package:drivelife/screens/events/open_event_editor.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/main.dart';
import 'package:drivelife/models/account_model.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/location_access_provider.dart';
import 'package:drivelife/providers/pending_tags_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/auth/entity_switcher.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/screens/clubs/add_club_screen.dart';
import 'package:drivelife/screens/clubs/club_creation_screen.dart';
import 'package:drivelife/screens/clubs/my_clubs_screen.dart';
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

  // Two levels of navigation, and they are not the same thing.
  //
  // The BOTTOM bar picks a destination: Home, Discover, Photos, Garage,
  // Account. The TOP row picks a section WITHIN Home: For You, Events,
  // Places, Groups. Sections used to be bottom tabs, which is why the two
  // lists read as though they overlap — they no longer do.
  static const List<DlTopTab> _homeTabs = [
    DlTopTab(label: 'For You', icon: 'assets/app-icons/01-Home.svg'),
    DlTopTab(label: 'Events', icon: 'assets/app-icons/02-Events.svg'),
    DlTopTab(label: 'Places', icon: 'assets/app-icons/03-Venues.svg'),
    DlTopTab(label: 'Groups', icon: 'assets/app-icons/07-groups.svg'),
    // Last, and reachable only here: the header's basket button went when
    // the header was rebuilt, so this is the shop's only way in.
    DlTopTab(label: 'Shop', icon: 'assets/app-icons/04-Basket.svg'),
  ];

  /// Which section of Home is showing. Only meaningful while the Home
  /// destination is selected.
  int _homeTab = 0;

  /// Drives the header, the section tabs and the bottom bar out of the way
  /// while somebody is reading, and brings them back when they scroll up or
  /// reach the top. Fed by the feed, which is the only thing long enough to
  /// warrant it.
  final ChromeVisibility _chrome = ChromeVisibility();

  /// Shared by every piece of chrome, so the header, the section tabs and
  /// the bottom bar leave and return as one movement rather than three.
  /// Slow enough to read as the chrome moving rather than appearing.
  ///
  /// The quick version popped: at 240ms a header is simply there on the next
  /// glance, which is what makes it feel like a layout jump rather than a
  /// piece of the interface arriving.
  static const Duration _chromeDuration = Duration(milliseconds: 420);

  /// Decelerating, so it settles rather than stopping dead — the part that
  /// separates "slid into place" from "snapped".
  static const Curve _chromeCurve = Curves.easeOutCubic;

  /// Destinations, in bottom-bar order.
  static const int _dHome = 0;
  static const int _dDiscover = 1;
  static const int _dPhotos = 2;
  static const int _dGarage = 3;
  static const int _dAccount = 4;

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
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _buildScreens();
    _reloadUserData();

    // Single source of truth — checks once, all screens read from it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LocationAccessProvider>().refresh();
        // What the Photos tab badge counts. Loaded once on launch rather than
        // when the tab is opened, since the whole point is to say there is
        // something there before anyone goes looking.
        context.read<PendingTagsProvider>().refresh();
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

    // Order must match the items in _buildBottomNav, and the indices named
    // by the _d* constants above.
    final screens = <Widget>[
      // A placeholder. Home is rebuilt in build() instead, because the
      // section it shows changes and a widget stored here would keep the
      // index it was constructed with — which is why the top tabs did
      // nothing: the tap changed _homeTab, and the frozen IndexedStack
      // carried on showing the section it was built with.
      const SizedBox.shrink(),
      const SearchScreen(embedded: true),
      if (FeatureFlags.mediaTab) MediaScreen() else const SizedBox.shrink(),
      const GarageListScreen(embedded: true),
      if (currentAccount?.isClubAccount ?? false)
        ClubProfileScreen()
      else
        ProfileScreen(),
    ];

    if (mounted) setState(() => _screens = screens);
  }

  /// The Home destination: four sections behind the top tab row.
  ///
  /// An IndexedStack, not a switch or an AnimatedSwitcher: each section keeps
  /// its scroll position, its loaded pages and its controllers while the
  /// others are off screen. Animating the content would mean rebuilding it,
  /// and losing a feed's place to gain a cross-fade is a bad trade. The
  /// movement lives in the tab row instead, which is where the eye is.
  Widget _buildHome() {
    return IndexedStack(
      index: _homeTab,
      children: [
        PostsScreen(key: _postsScreenKey, chrome: _chrome),
        EventsScreen(),
        VenuesScreen(),
        MyClubsScreen(),
        // No app bar of its own: the shell above already supplies one, and
        // the shop's own carries a back button that would pop the shell.
        const ShopScreen(),
      ],
    );
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
              label: 'Add Group',
              svg: 'assets/app-icons/07-groups.svg',
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
            onTap: () => openEventEditor(context),
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
  Widget _buildHeader(ThemeProvider theme) {
    return _Header(
      // Left, not centred. The logo is the app saying where you are; a
      // centred one competes with the section row below it for the eye.
      title: Image.asset('assets/logo-dark.png', height: 20),
      actions: [
        _RoundAction(
          child: iconSvg(
            'assets/app-icons/header-plus.svg',
            theme,
            size: 18,
            alwaysActive: true,
          ),
          onTap: () => _showAddMenu(theme),
        ),
        const SizedBox(width: 8),
        _RoundAction(
          child: iconSvg(
            'assets/app-icons/header-search.svg',
            theme,
            size: 18,
            alwaysActive: true,
          ),
          onTap: () => Navigator.pushNamed(context, AppRoutes.search),
        ),
        const SizedBox(width: 8),
        _RoundAction(
          child: iconSvg(
            'assets/app-icons/header-notification.svg',
            theme,
            size: 18,
            alwaysActive: true,
          ),
          onTap: () => Navigator.pushNamed(context, AppRoutes.notifications),
        ),
        const SizedBox(width: 16),
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
    Widget svg(String asset, bool selected) => iconSvg(
      asset,
      theme,
      size: 22,
      isActive: selected,
      alwaysActive: selected,
    );

    return DlBottomNav(
      currentIndex: _currentIndex,
      onChanged: (index) {
        final current = _currentIndex;

        // Tapping the destination you are already on is a shortcut, not a
        // no-op: Account opens the switcher, Home returns the feed to the
        // top. Both are long-standing behaviours and worth keeping.
        if (index == _dAccount && current == _dAccount) {
          _showAccountSwitcher();
          HapticFeedback.lightImpact();
          return;
        }

        if (index == _dHome && current == _dHome) {
          if (_homeTab == 0) {
            _postsScreenKey.currentState?.scrollToTopAndRefresh();
          } else {
            // Not on the feed: "home" means the first section first.
            setState(() => _homeTab = 0);
          }
          HapticFeedback.lightImpact();
          return;
        }

        // A new destination starts with its chrome showing. The one being
        // left may have hidden it, and nothing but the feed knows how to
        // bring it back — so a Garage tab with no header would be stuck.
        _chrome.reset();
        _setIndex(index);
      },
      items: [
        DlNavItem(
          label: 'Home',
          icon: (sel) => svg('assets/app-icons/01-Home.svg', sel),
        ),
        DlNavItem(
          label: 'Discover',
          icon: (sel) => svg('assets/app-icons/header-search.svg', sel),
        ),
        DlNavItem(
          label: 'Photos',
          // Carries the unseen-tag count. Unseen rather than the whole
          // pending queue: a badge mirroring every outstanding tag would
          // never clear, and a dot that is always on is one people stop
          // reading.
          icon: (sel) => Consumer<PendingTagsProvider>(
            builder: (context, tags, child) => _BadgedIcon(
              count: tags.unseen,
              color: theme.primaryColor,
              child: child!,
            ),
            child: svg('assets/app-icons/06-photo.svg', sel),
          ),
        ),
        DlNavItem(
          label: 'Garage',
          icon: (sel) => svg('assets/app-icons/05-User.svg', sel),
        ),
        DlNavItem(label: 'Account', icon: (_) => _buildProfileIcon()),
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

    // Back unwinds the navigation one level at a time: a section first,
    // then the destination, and only then the app. Dropping straight to the
    // feed from deep in Groups would feel like the app lost its place.
    final atRoot = _currentIndex == _dHome && _homeTab == 0;

    return PopScope(
      canPop: atRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (_currentIndex != _dHome) {
          _setIndex(_dHome);
          return;
        }

        if (_homeTab != 0) setState(() => _homeTab = 0);
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
        // No Scaffold appBar: its height is fixed at build time, and this
        // header has to be able to collapse. It lives in the body instead,
        // under a spacer that holds the status bar area — that part never
        // moves, or the content would jump under the clock.
        //
        // extendBody so the bottom bar can slide off the screen rather than
        // shrinking the content, which would reflow the feed on every
        // scroll direction change.
        extendBody: true,
        body: ValueListenableBuilder<bool>(
          valueListenable: _chrome,
          builder: (context, chromeVisible, _) {
            // Only Home hides its chrome. Everywhere else the header is the
            // only navigation on screen, and a destination you cannot leave
            // without scrolling is worse than a chunky header.
            final canHide = _currentIndex == _dHome;
            final showChrome = chromeVisible || !canHide;

            return Column(
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top),

                // Header and section tabs collapse together: they are one
                // block of chrome and sliding them independently reads as
                // two separate things going wrong.
                _Collapsible(
                  visible: showChrome,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(theme),
                      // Sections belong to Home. On any other destination
                      // the row would be navigating something that is not
                      // on screen.
                      if (_currentIndex == _dHome)
                        DlTopTabs(
                          tabs: _homeTabs,
                          currentIndex: _homeTab,
                          onChanged: (i) {
                            _chrome.show();
                            setState(() => _homeTab = i);
                          },
                        ),
                    ],
                  ),
                ),

                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      // Rebuilt every frame so it tracks _homeTab. The
                      // sections inside keep their state regardless:
                      // Flutter reconciles them by type and position, and
                      // the feed carries a key.
                      _buildHome(),
                      ..._screens.skip(1),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: _chrome,
          builder: (context, chromeVisible, child) {
            final showChrome = chromeVisible || _currentIndex != _dHome;

            // Slides off the bottom rather than collapsing. Collapsing would
            // change the body's height and reflow the feed mid-scroll.
            return AnimatedSlide(
              duration: _chromeDuration,
              curve: _chromeCurve,
              offset: showChrome ? Offset.zero : const Offset(0, 1.4),
              child: child,
            );
          },
          child: _buildBottomNav(theme),
        ),
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

/// A nav icon with a count over its top-right corner.
///
/// Nothing is drawn at zero, and the icon keeps its own size either way — a
/// badge that changed the icon's footprint would shift the whole nav row every
/// time a tag arrived.
class _BadgedIcon extends StatelessWidget {
  final Widget child;
  final int count;
  final Color color;

  const _BadgedIcon({
    required this.child,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          right: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 17),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Text(
              // Past nine the exact number stops being useful and starts
              // being too wide for the icon it sits on.
              count > 9 ? '9+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A header action: an icon in a soft circle.
///
/// Circles rather than bare glyphs because the header has no other structure
/// — against a white page three loose icons read as clutter, three discs read
/// as a set.
class _RoundAction extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _RoundAction({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4F4F4),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(width: 40, height: 40, child: Center(child: child)),
      ),
    );
  }
}

/// The home header: logo on the left, round actions on the right.
///
/// A plain Row rather than an AppBar, because this one has to be able to
/// collapse — a Scaffold's appBar reserves its height for the life of the
/// build and cannot animate to nothing.
class _Header extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;

  const _Header({required this.title, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: 56,
      padding: const EdgeInsets.only(left: 20),
      child: Row(children: [title, const Spacer(), ...actions]),
    );
  }
}

/// Collapses its child to nothing and back.
///
/// Height rather than a slide: this sits at the top of a Column, so the
/// content below has to close the gap as it goes. A slide would leave a
/// white band where the header used to be.
class _Collapsible extends StatelessWidget {
  final bool visible;
  final Widget child;

  const _Collapsible({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: _HomeTabsState._chromeDuration,
        curve: _HomeTabsState._chromeCurve,
        alignment: Alignment.bottomCenter,
        heightFactor: visible ? 1 : 0,
        child: child,
      ),
    );
  }
}
