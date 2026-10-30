import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:drivelife/api/notifications_api.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:drivelife/screens/store/shop_screen.dart';
import 'package:drivelife/screens/discover/discover_map_screen.dart';
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
import 'package:drivelife/services/supabase_session.dart';
import 'package:drivelife/services/unread_messages_watcher.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/auth/entity_switcher.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/screens/clubs/add_club_screen.dart';
import 'package:drivelife/screens/places/coming_soon_screen.dart';
import 'package:drivelife/screens/tracks/tracks_screen.dart';
import 'package:drivelife/screens/clubs/club_creation_screen.dart';
import 'package:drivelife/screens/clubs/my_clubs_screen.dart';
import 'package:drivelife/screens/create-post/create_post_screen.dart';
import 'package:drivelife/screens/events/events_screen.dart';
import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/screens/garage/garage_list_screen.dart';
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

class _HomeTabsState extends State<HomeTabs> with WidgetsBindingObserver {
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
    // Tracks before Businesses: one has somewhere to go, the other is still
    // a "coming soon" page.
    //
    // Cupertino glyphs because assets/app-icons has no flag or building.
    // They shared the Places pin until now, which told the user nothing
    // about either.
    DlTopTab(label: 'Tracks & Raceways', glyph: CupertinoIcons.flag),
    DlTopTab(label: 'Businesses', glyph: CupertinoIcons.building_2_fill),
    // Groups is not here: it is a bottom-bar destination again. Listing it
    // in both would mean two routes to the same screen, each with its own
    // scroll position and its own loaded list.
    // Reachable only here: the header's basket button went when the
    // header was rebuilt, so this is the shop's only way in.
    DlTopTab(label: 'Shop', icon: 'assets/app-icons/04-Basket.svg'),
  ];

  /// Which section of Home is showing. Only meaningful while the Home
  /// destination is selected.
  /// Which section of Home is showing.
  ///
  /// Held by the provider rather than here, so anything in the app can send
  /// the user to a section by name. See BottomNavProvider.openHomeSection.
  int get _homeTab => context.read<BottomNavProvider>().homeSection;

  void _setHomeTab(int section) =>
      context.read<BottomNavProvider>().openHomeSection(section);

  /// Drives the header, the section tabs and the bottom bar out of the way
  /// while somebody is reading, and brings them back when they scroll up or
  /// reach the top. Fed by the feed, which is the only thing long enough to
  /// warrant it.
  final ChromeVisibility _chrome = ChromeVisibility();

  /// Height of the header row.
  ///
  /// Taken from [_Header] rather than written out again. The two were
  /// separate constants "kept in sync by hand", which lasted until one of
  /// them changed: the sliver declared 52, the header drew 56, and every
  /// screen carrying it overflowed by exactly 4.
  static const double _headerHeight = _Header.height;

  /// True when the section below is drawing the chrome inside its own
  /// scroll view, so the shell must not draw it as well.
  ///
  /// Three sections do: the feed, Places and Tracks. Each hands its scroll
  /// view a floating sliver holding this header, which is the only way to
  /// move it without resizing the viewport underneath a finger.
  ///
  /// The rest are screens with no scroll view to put it in, so the shell
  /// draws it above them and it stays put.
  bool get _chromeIsInFeed {
    // Groups and Garage are destinations rather than sections of Home, and
    // each draws the header inside its own scroll view just as Places does.
    // Without them here the shell would draw a second one above.
    if (_currentIndex == _dGroups || _currentIndex == _dGarage) return true;

    return _currentIndex == _dHome &&
        const {
          BottomNavProvider.forYou,
          BottomNavProvider.places,
          BottomNavProvider.tracks,
        }.contains(_homeTab);
  }

  /// Whether the current destination draws edge to edge, under the status
  /// bar, with no app header above it.
  ///
  /// Discover is a map: a header and a status-bar spacer above it would cost
  /// ~110px of the thing the screen exists to show, and the map's own search
  /// bar already floats over the top. The bottom bar still floats over it, so
  /// the destination is reachable - this hides the chrome above the content,
  /// not the navigation.
  ///
  /// Such a destination handles its own insets. Discover's search bar sits in
  /// a SafeArea of its own; while the spacer below was also being drawn, the
  /// two stacked and left a gap the height of the status bar.
  bool get _isFullBleed => _currentIndex == _dDiscover;

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
  static const int _dHome = BottomNavProvider.home;
  static const int _dDiscover = BottomNavProvider.discover;
  static const int _dGroups = BottomNavProvider.groups;
  static const int _dPhotos = BottomNavProvider.photos;
  static const int _dGarage = BottomNavProvider.garage;

  // Garage is a destination again, in the slot Account used to hold. The
  // profile is no longer a tab at all — it is the avatar in the header.
  void _setIndex(int index) {
    if (index == _dDiscover && !_discoverOpened) {
      setState(() => _discoverOpened = true);
    }
    context.read<BottomNavProvider>().setIndex(index);
  }

  final GlobalKey<PostsScreenState> _postsScreenKey =
      GlobalKey<PostsScreenState>();

  final _authService = AuthService();

  List<Widget> _screens = [];

  @override
  void dispose() {
    _unread?.dispose();
    _chrome.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadNotificationCount();

      // Messages that arrived while the app was away. The realtime
      // subscription is torn down in the background, so coming back is
      // the one moment the badge is guaranteed stale.
      _unread?.refresh();
    }
  }

  @override
  void initState() {
    super.initState();

    // Notifications arrive while the app is in the background, so the count
    // is re-read on the way back rather than only at launch.
    WidgetsBinding.instance.addObserver(this);
    _loadNotificationCount();

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
      // A placeholder, and it has to be here rather than just commented
      // out: every entry below it is addressed by its position, so dropping
      // the slot silently moved Groups onto Photos, Photos onto Account and
      // Account off the end of the list. Discover itself is built in
      // build() — see [_buildDiscover].
      const SizedBox.shrink(),

      // Groups, back as its own destination rather than a section of Home.
      // A placeholder. Groups is rebuilt every frame in
      // _buildDestinations() because it carries the shell's header, which
      // has a live notification badge on it — captured once here it would
      // never update.
      const SizedBox.shrink(),
      if (FeatureFlags.mediaTab) MediaScreen() else const SizedBox.shrink(),

      // A placeholder: the garage is rebuilt every frame in
      // _buildDestinations, because it carries the shell's header and that
      // header has a live notification badge on it.
      const SizedBox.shrink(),
    ];

    if (mounted) setState(() => _screens = screens);
  }

  /// The destinations, in bottom-bar order.
  ///
  /// Asserted against the number of items in the bar, because the two are
  /// matched by position and nothing else. Getting them out of step does not
  /// fail loudly — it silently shifts every destination after the gap onto
  /// its neighbour's tab and drops the last one off the end, which is
  /// exactly what a missing placeholder here did once already.
  /// Groups, with the shell's chrome inside its own scroll views.
  ///
  /// Built here rather than in [_buildScreens] for the same reason Home
  /// is: the header it is handed carries a notification badge and the
  /// theme, and a widget captured once into a cached list never sees
  /// either change.
  Widget _buildGroups(ThemeProvider theme) {
    return MyClubsScreen(
      chrome: _chrome,
      header: _buildChrome(theme),
      headerHeight: _chromeHeight,
    );
  }

  /// The garage, with the shell's chrome inside its own scroll view.
  ///
  /// Built per frame for the same reason Home and Groups are: the header it
  /// is handed carries the notification badge and the theme, and a widget
  /// captured once into a cached list never sees either change.
  Widget _buildGarage(ThemeProvider theme) {
    final user = context.watch<AccountManager>().activeAccount?.user;

    return GarageListScreen(
      // Keyed by account, which is the whole fix for "switched account,
      // still my old garage". This screen reads the signed-in user once
      // in initState and guards its load with a _garageLoaded flag, so
      // without a new key its State survives the switch and the flag
      // says there is nothing to fetch — refreshing does not help,
      // because the user it refreshes for is the one it captured.
      key: ValueKey('garage-${user?.id ?? 'none'}'),
      chrome: _chrome,
      header: _buildChrome(theme),
      headerHeight: _chromeHeight,
    );
  }

  Widget _buildDestinations(ThemeProvider theme) {
    final destinations = <Widget>[
      // Rebuilt every frame so it tracks _homeTab. The sections inside keep
      // their state regardless: Flutter reconciles them by type and
      // position, and the feed carries a key.
      _buildHome(theme),
      _buildDiscover(),
      _buildGroups(theme),
      ..._screens.skip(3).take(1),
      _buildGarage(theme),
    ];

    assert(
      destinations.length == _navItemCount,
      'The bottom bar has $_navItemCount items but there are '
      '${destinations.length} destinations. They are matched by position, so '
      'a mismatch sends taps to the wrong screen.',
    );

    return IndexedStack(index: _currentIndex, children: destinations);
  }

  /// How many items the bottom bar shows. Kept beside the [_d*] constants it
  /// has to agree with.
  static const int _navItemCount = BottomNavProvider.destinationCount;

  /// How many notifications are unread.
  ///
  /// The bell had no badge at all — the count endpoint and its Dart method
  /// both existed, but the only caller was shared_header_actions.dart, the
  /// header this one replaced. So it was not broken so much as never
  /// reconnected.
  int _notificationCount = 0;

  /// Re-reads the unread count.
  ///
  /// Called on launch, when the app comes back to the foreground, and on
  /// returning from the notifications screen — which marks everything read,
  /// so without that last one the badge would sit there after being cleared.
  Future<void> _loadNotificationCount() async {
    final count = await NotificationsAPI.getNotificationCount();
    if (!mounted || count == _notificationCount) return;
    setState(() => _notificationCount = count);
  }

  /// Whether Discover has ever been opened.
  ///
  /// Everything in the IndexedStack is built whether or not it is the one
  /// showing, and Discover is a native Mapbox view: built on launch it
  /// loads a style and starts pulling tiles for a page nobody has asked for,
  /// and — because its page tour fires when the style finishes loading — it
  /// put that tour on top of the home feed.
  ///
  /// So it is built on first visit and kept afterwards, which also means
  /// someone who never opens Discover never pays for a map.
  bool _discoverOpened = false;

  /// The Discover destination, once it has been asked for.
  Widget _buildDiscover() =>
      _discoverOpened ? const DiscoverMapScreen() : const SizedBox.shrink();

  /// The Home destination: four sections behind the top tab row.
  ///
  /// An IndexedStack, not a switch or an AnimatedSwitcher: each section keeps
  /// its scroll position, its loaded pages and its controllers while the
  /// others are off screen. Animating the content would mean rebuilding it,
  /// and losing a feed's place to gain a cross-fade is a bad trade. The
  /// movement lives in the tab row instead, which is where the eye is.
  /// Header and section tabs, as one block.
  ///
  /// Either handed to the feed to live inside its scroll view, or drawn above
  /// the content for destinations that have no feed to put it in. One builder
  /// so the two cannot drift apart.
  Widget _buildChrome(ThemeProvider theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(theme),
        if (_currentIndex == _dHome)
          DlTopTabs(
            tabs: _homeTabs,
            currentIndex: _homeTab,
            onChanged: _setHomeTab,
          ),
      ],
    );
  }

  /// How tall [_buildChrome] is, which a sliver header has to know up front.
  double get _chromeHeight =>
      _headerHeight + (_currentIndex == _dHome ? DlTopTabs.height : 0);

  /// The inbox, or a prompt to sign in.
  ///
  /// Built per frame rather than held in a field so that signing in or
  /// switching account rebuilds it against the new user — the inbox is
  /// keyed on a user id and would otherwise keep showing the old one's
  /// conversations until the whole shell was rebuilt.
  Widget _buildHome(ThemeProvider theme) {
    final sections = <Widget>[
      // The chrome rides inside the feed's own scroll view, so the
      // scroll moves it. It used to collapse in a Column above the feed,
      // which changed the viewport's height on every frame of the
      // animation — and a viewport that resizes during a drag keeps
      // correcting its own offset, which is what made the top of the feed
      // feel heavy and stutter.
      PostsScreen(
        key: _postsScreenKey,
        chrome: _chrome,
        header: _buildChrome(theme),
        headerHeight: _chromeHeight,
      ),
      EventsScreen(),
      VenuesScreen(
        chrome: _chrome,
        header: _buildChrome(theme),
        headerHeight: _chromeHeight,
      ),

      // Tracks have their own screen and their own endpoints. They were
      // briefly the venues screen with a post type argument, which listed
      // the user's venues under "My tracks" and could not open any of them.
      TracksScreen(
        chrome: _chrome,
        header: _buildChrome(theme),
        headerHeight: _chromeHeight,
      ),

      // There is no `businesses` post type in WordPress yet, so this says
      // so rather than running a search that can only ever come back empty.
      // "No businesses found" reads as "none near you"; this reads as what
      // is actually true. Swap it for a VenuesScreen(postType: 'businesses')
      // — the server already accepts that — the day the post type exists.
      const ComingSoonScreen(title: 'Businesses'),

      // No app bar of its own: the shell above already supplies one, and
      // the shop's own carries a back button that would pop the shell.
      const ShopScreen(),
    ];

    assert(
      _homeTabs.length == BottomNavProvider.sectionCount,
      'Home has ${_homeTabs.length} tabs but BottomNavProvider names '
      '${BottomNavProvider.sectionCount}. Anything navigating by name would '
      'land on the wrong one.',
    );
    assert(
      sections.length == _homeTabs.length,
      'Home has ${_homeTabs.length} tabs but ${sections.length} sections. '
      'They are matched by position, so a mismatch shows the wrong one.',
    );

    return IndexedStack(index: _homeTab, children: sections);
  }

  /// Keeps the unread-message badge current while the inbox is shut.
  ///
  /// The inbox used to be a Home section and so was always built, its
  /// notifier pushing counts whether anybody was looking or not. It is
  /// a pushed screen now, so this holds the one number that has to
  /// outlive it. Remade per account: the badge counts this account's
  /// messages.
  UnreadMessagesWatcher? _unread;
  int? _unreadFor;

  void _syncUnreadWatcher() {
    final accounts = context.read<AccountManager>();
    final id = accounts.activeUser?.id;

    if (id == _unreadFor) return;

    _unreadFor = id;
    _unread?.dispose();
    _unread = null;

    if (id == null) return;

    final provider = context.read<UnreadCountProvider>();

    // The session FIRST, and awaited. Supabase is initialised in main()
    // with the publishable key, which is the anonymous role — the
    // user's own token is a separate step that nothing did outside the
    // inbox. Starting the watcher before it lands means a count
    // fetched as anon, and a realtime socket subscribed as anon, which
    // is subscribed and silent.
    //
    // Clearing first because the token names a user and this runs on
    // every switch.
    SupabaseSession.clear();

    SupabaseSession.ensure(accounts).then((ready) {
      if (!mounted || _unreadFor != id || !ready) return;

      final watcher = UnreadMessagesWatcher(
        myUserId: '$id',
        provider: provider,
      );

      _unread = watcher;
      watcher.start();
    });
  }

  /// Which account UserProvider was last loaded for.
  ///
  /// UserProvider holds the second answer to "who is signed in", and it
  /// was loaded once in initState and never again — so after switching
  /// account every screen reading it saw the previous one. The garage
  /// was the visible symptom because its whole job is "my vehicles",
  /// but 30-odd screens read the same provider.
  int? _userDataFor;

  void _reloadUserData() {
    final active = context.read<AccountManager>().activeUser?.id;
    _userDataFor = active;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<UserProvider>().loadUser();
    });
  }

  /// Reload it when the active account changes.
  ///
  /// Called from build, which already watches AccountManager for the
  /// header avatar, so a switch brings us back here anyway. Guarded on
  /// the id so this is a comparison on most frames and a fetch on
  /// almost none.
  void _syncUserDataToAccount() {
    final active = context.read<AccountManager>().activeUser?.id;
    if (active == _userDataFor) return;

    _reloadUserData();
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
        // Messages, not notifications. Both live behind this one icon
        // now — MessagesScreen is the two of them behind tabs — so the
        // badge is the two counts added together. Splitting them across
        // two badges was two things to check and no way to tell at a
        // glance whether either wanted you.
        _RoundAction(
          child: _BadgedIcon(
            count:
                _notificationCount + context.watch<UnreadCountProvider>().count,
            color: theme.primaryColor,
            // A tray, not a speech bubble. This opens messages AND
            // notifications, and a bubble promises only the first — an
            // inbox is the thing that holds both.
            child: const Icon(
              CupertinoIcons.tray,
              size: 19,
              color: Color(0xFF111111),
            ),
          ),
          onTap: () async {
            await Navigator.pushNamed(context, AppRoutes.messages);
            // Both halves of the badge. The notifications tab marks
            // everything read on its way in, and opening a conversation
            // clears its unread count — so neither number survives the
            // trip and both have to be re-read.
            await _loadNotificationCount();
            await _unread?.refresh();
          },
        ),
        const SizedBox(width: 8),

        // The account, where Search used to be. Search has not gone
        // anywhere — it is the Discover destination in the bar below.
        //
        // Tap opens your own profile, long-press the account switcher, which
        // is what the avatar did when it was a tab.
        _HeaderAccount(
          onTap: _openOwnProfile,
          onLongPress: _showAccountSwitcher,
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  /// Opens the signed-in account's own profile.
  ///
  /// Pushed as a route rather than shown as a tab: the profile stopped
  /// being a destination when the avatar moved up here.
  void _openOwnProfile() {
    final account = Provider.of<AccountManager>(
      context,
      listen: false,
    ).activeAccount;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => (account?.isClubAccount ?? false)
            ? ClubProfileScreen()
            : ProfileScreen(),
      ),
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
      size: 20,
      isActive: selected,
      alwaysActive: selected,
    );

    return DlBottomNav(
      currentIndex: _currentIndex,
      onChanged: (index) {
        final current = _currentIndex;

        // Tapping Home when already on Home returns the feed to the top.
        // The account switcher used to hang off the same gesture on the
        // Account tab; it is a long-press on the header avatar now.
        if (index == _dHome && current == _dHome) {
          if (_homeTab == 0) {
            _postsScreenKey.currentState?.scrollToTopAndRefresh();
          } else {
            // Not on the feed: "home" means the first section first.
            _setHomeTab(BottomNavProvider.forYou);
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
          label: 'Groups',
          icon: (sel) => svg('assets/app-icons/07-groups.svg', sel),
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
          // A Material glyph: assets/app-icons has no car, and the Tracks
          // tab already sets the precedent of borrowing one rather than
          // shipping a tab with somebody else's icon on it. Swaps to an
          // SVG by changing this one line.
          icon: (sel) => Icon(
            Icons.directions_car_rounded,
            size: 21,
            color: sel ? theme.primaryColor : Colors.grey,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final accountManager = Provider.of<AccountManager>(context);

    // The line above already subscribes to account changes, so a switch
    // brings us here. This is the only place that notices.
    _syncUserDataToAccount();
    _syncUnreadWatcher();

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

        if (_homeTab != BottomNavProvider.forYou) {
          _setHomeTab(BottomNavProvider.forYou);
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
        // No Scaffold appBar: its height is fixed at build time, and this
        // header has to be able to collapse. It lives in the body instead,
        // under a spacer that holds the status bar area — that part never
        // moves, or the content would jump under the clock.
        //
        // extendBody so the bottom bar can slide off the screen rather than
        // shrinking the content, which would reflow the feed on every
        // scroll direction change.
        extendBody: true,
        body: Column(
          children: [
            if (!_isFullBleed) ...[
              SizedBox(height: MediaQuery.of(context).padding.top),

              // Drawn here only where there is no feed to put it in. On the
              // feed itself the chrome is a sliver, so nothing above the
              // scroll view changes size while a finger is on the screen.
              if (!_chromeIsInFeed) _buildChrome(theme),
            ],

            Expanded(child: _buildDestinations(theme)),
          ],
        ),
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: _chrome,
          builder: (context, chromeVisible, child) {
            // The bottom bar follows the scroll on the destinations that
            // report one, and stays put on the rest. Groups reports now, so
            // it hides with the header there as it does on the feed.
            final showChrome =
                chromeVisible ||
                (_currentIndex != _dHome &&
                    _currentIndex != _dGroups &&
                    _currentIndex != _dGarage);

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
        child: SizedBox(width: 38, height: 38, child: Center(child: child)),
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

  /// How tall this row is, and the single place that decides.
  ///
  /// The sliver that carries the header has to declare its extent before
  /// layout, and _HomeTabsState._headerHeight reads this rather than
  /// repeating it. When they were two numbers agreeing by hand, one of
  /// them changed and the other did not: the sliver said 52, this drew 56,
  /// and every screen carrying it overflowed by exactly 4.
  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: height,
      padding: const EdgeInsets.only(left: 20),
      child: Row(children: [title, const Spacer(), ...actions]),
    );
  }
}

/// The account avatar in the header.
///
/// The button is the same 38pt disc as the two beside it, and the face is
/// drawn at 28 inside it. Filling the whole disc with a photograph made
/// this read as much the largest of the three even though all three
/// measured the same: a dense photo carries far more weight per point than
/// an 18pt glyph on #F4F4F4, and the eye sizes by weight.
///
/// Tap opens your own profile; long-press the account switcher, which is
/// the gesture the avatar carried when it was a tab.
class _HeaderAccount extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _HeaderAccount({required this.onTap, required this.onLongPress});

  /// The button, matching _RoundAction.
  static const double _size = 38;

  /// The face, inside the button rather than filling it.
  ///
  /// 40 -> 28 -> 38 -> 34, and the wandering is the point: measured
  /// against the other two this has been right at every size and looked
  /// wrong at most of them, because the three are not comparable objects.
  /// They are #F4F4F4 discs carrying an 18pt line glyph; this is a
  /// photograph. A dense, full-colour circle reads larger than a pale
  /// one of identical diameter, so matching the diameter is what makes
  /// it look bigger.
  ///
  /// 34 against their 38: four points smaller, which is roughly what it
  /// takes for the three to read as one size. Anything that changes the
  /// other two — a fill with more contrast, a heavier glyph — changes
  /// what this should be, so it is a judgement rather than a constant
  /// derived from [_size].
  static const double _face = 34;

  @override
  Widget build(BuildContext context) {
    return Consumer<AccountManager>(
      builder: (context, accounts, child) {
        final url = accounts.activeAccount?.user.profileImage?.trim();
        final hasImage = url != null && url.isNotEmpty;

        return Material(
          // Transparent, so nothing is drawn behind the photograph. The
          // ripple still lands: InkWell paints on the Material, and the
          // CircleBorder keeps it round.
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox(
              width: _size,
              height: _size,
              child: Center(
                child: hasImage
                    ? ClipOval(
                        child: SizedBox(
                          width: _face,
                          height: _face,
                          child: CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            memCacheWidth:
                                (_face * MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                            errorWidget: (_, __, ___) => const Icon(
                              Icons.person_outline,
                              size: 18,
                              color: Color(0xFF111111),
                            ),
                          ),
                        ),
                      )
                    // No photograph: a filled disc at the same 28, so
                    // the button keeps its size and its weight instead of
                    // becoming a floating outline of a person.
                    : Container(
                        width: _face,
                        height: _face,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF4F4F4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          size: 17,
                          color: Color(0xFF111111),
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
