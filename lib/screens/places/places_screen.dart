import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/api/places_api.dart';
import 'package:drivelife/providers/location_access_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/account-settings/app_permissions_screen.dart';
import 'package:drivelife/screens/events/events_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/widgets/events/filter_bottom_sheet.dart';
import 'package:drivelife/widgets/listing/featured_card.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:drivelife/widgets/nav/pinned_sliver_bar.dart';
import 'package:drivelife/widgets/listing/listing_row.dart';
import 'package:drivelife/widgets/listing/listing_chips.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/models/venue_model.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_places_flutter/google_places_flutter.dart';

class VenuesScreen extends StatefulWidget {
  /// Told which way the user is scrolling, so the shell can take the bottom
  /// bar away and bring it back. The same notifier the feed reports to.
  final ChromeVisibility? chrome;

  /// The shell's header and section tabs, drawn inside this screen's own
  /// scroll view rather than above it.
  ///
  /// Above it, the only way to hide it would be to shrink the box it sits
  /// in, which changes the viewport's height on every frame of the
  /// animation — and a viewport that resizes mid-drag keeps correcting its
  /// own offset. As a sliver the scroll moves it, and nothing resizes.
  final Widget? header;

  /// How tall [header] is. A sliver header declares its extent up front.
  final double headerHeight;
  const VenuesScreen({
    super.key,
    this.chrome,
    this.header,
    this.headerHeight = 0,
  });

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends State<VenuesScreen>
    with TickerProviderStateMixin {
  /// What this screen lists. Kept as a field rather than written out in a
  /// dozen strings, which is how it came to say "Venues" on the tracks page.
  static const String _them = 'Venues';
  static const String _themLower = 'venues';

  /// How tall the featured carousel is. Named because the loading state,
  /// the cards and the gap below it all have to agree.
  static const double _featuredHeight = 172;
  late TabController _tabController;
  late ThemeProvider theme;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // State management
  bool _isLoading = false;
  bool _isLoadingMore = false;
  List<Venue> _venues = [];
  List<dynamic> _followedVenues = [];
  List<Venue> _filteredVenues = [];
  List<Venue> _searchResults = [];
  String? _errorMessage;
  bool _isSearching = false;

  bool _isMyVenuesLoading = true;
  List<dynamic> _ownedVenues = [];

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMore = true;

  // Search pagination
  int _searchPage = 1;
  int _searchTotalPages = 1;
  bool _searchHasMore = true;

  // Filters

  final TextEditingController _customLocationController =
      TextEditingController();
  double? _customLat;
  double? _customLng;
  String? _customLocationName;

  /// 100 miles rather than "near me".
  ///
  /// Near me is the tightest of the four and on a first run it is usually
  /// empty — most of the country is further than a few miles from anywhere
  /// worth driving to. An empty list on open reads as a broken screen.
  String? _selectedLocation = _defaultDistance;

  /// Where both tabs start, and what the location banner falls back from.
  static const String _defaultDistance = '100-miles';
  bool _showLocationBanner = false;

  List<Map<String, String?>> _banners = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final locationProvider = context.read<LocationAccessProvider>();

      // If the check hasn't run yet, wait for it. Otherwise read cached result.
      if (!locationProvider.isResolved) {
        await locationProvider.refresh();
      }

      if (!mounted) return;

      final hasAccess = locationProvider.hasAccess;
      setState(() {
        _showLocationBanner = !hasAccess;
        // Without permission there is no "here" to measure from, so the
        // only honest radius is the whole country.
        _selectedLocation = hasAccess ? _defaultDistance : 'national';
      });
    });

    theme = Provider.of<ThemeProvider>(context, listen: false);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    _loadFeaturedVenues();
    _loadVenues();
    _loadMyVenues();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _customLocationController.dispose();
    super.dispose();
  }

  /// The tabs no longer live in a TabBarView, so nothing swaps the content
  /// for us — this does, by rebuilding with the other tab's slivers on
  /// stage. See [_tabSlivers].
  void _onTabChanged() {
    if (!mounted) return;

    setState(() {});

    // Back to the top on a real switch. The two tabs share one scroll
    // offset now, and landing a screen and a half down a tab that only has
    // two rows in it reads as an empty tab.
    if (!_tabController.indexIsChanging && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    if (_tabController.index == 1) {
      _loadMyVenues();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.9) {
      if (_isSearching && !_isLoadingMore && _searchHasMore) {
        _loadMoreSearchResults();
      } else if (!_isSearching &&
          !_isLoadingMore &&
          _hasMore &&
          _tabController.index == 0) {
        _loadMoreVenues();
      }
    }
  }

  /// False once the featured call has come back, whatever it returned.
  ///
  /// Needed because "no banners yet" and "no banners at all" used to look
  /// identical: the load only called setState when the result was non-empty,
  /// so an empty response left the placeholder spinner turning forever.
  bool _loadingBanners = true;

  /// The first of [keys] this row actually has something under.
  ///
  /// The featured endpoint is not the same shape as the listing one and has
  /// changed names over time, so the card asks for what it wants and takes
  /// whichever spelling turns up rather than showing a blank line.
  static String? _firstNonEmpty(dynamic row, List<String> keys) {
    if (row is! Map) return null;

    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;

      final text = value is Map
          ? (value['address'] ?? value['name'] ?? '').toString()
          : value.toString();

      if (text.trim().isNotEmpty && text != 'null') return text.trim();
    }

    return null;
  }

  Future<void> _loadFeaturedVenues() async {
    try {
      final result = await VenueApiService.getFeaturedVenues();
      if (!mounted) return;

      setState(() {
        _banners = (result ?? [])
            .map<Map<String, String?>>(
              (venue) => {
                'image': venue['banner_image'] ?? '',
                'title': venue['name'] ?? '',
                'id': venue['id'].toString(),
                // Both optional, and the card drops whichever is missing
                // rather than leaving an empty line where it would have
                // been.
                'kicker': _firstNonEmpty(venue, const [
                  'category',
                  'venue_type',
                  'type',
                ]),
                'location': _firstNonEmpty(venue, const [
                  'location',
                  'venue_location',
                  'address',
                  'town',
                ]),
              },
            )
            // A banner with no image is just a grey box taking up 150pt.
            .where((banner) => (banner['image'] ?? '').isNotEmpty)
            .toList();
        _loadingBanners = false;
      });
    } catch (e) {
      print('Error loading featured venues: $e');
      // A failed load is still a finished load — otherwise the spinner is
      // permanent on any network hiccup.
      if (mounted) setState(() => _loadingBanners = false);
    }
  }

  Future<void> _refreshVenues() async {
    await _loadVenues();
    await _loadFeaturedVenues();
  }

  Future<void> _loadVenues() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentPage = 1;
      _venues = []; // Clear venues to show skeleton
      _filteredVenues = []; // Clear filtered venues too
    });

    try {
      final result = await VenueApiService.getTrendingVenues(
        page: _currentPage,
        location: _selectedLocation,
        latitude: _customLat,
        longitude: _customLng,
        customLocation: _customLocationName,
        customLat: _customLat,
        customLng: _customLng,
      );

      if (!mounted) return;

      if (result != null && result['data'] != null) {
        final venuesResponse = VenuesResponse.fromJson(result);
        setState(() {
          _venues = venuesResponse.data;
          _filteredVenues = venuesResponse.data;
          _totalPages = venuesResponse.totalPages;
          _hasMore = _currentPage < _totalPages;
          _isLoading = false;
          _sortByDistance();
        });
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Failed to load $_themLower';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading venues: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading $_themLower. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreVenues() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    try {
      final result = await VenueApiService.getTrendingVenues(
        page: _currentPage,
        location: _selectedLocation,
        latitude: _customLat,
        longitude: _customLng,
        customLocation: _customLocationName,
        customLat: _customLat,
        customLng: _customLng,
      );

      if (!mounted) return;

      if (result != null && result['data'] != null) {
        final venuesResponse = VenuesResponse.fromJson(result);
        setState(() {
          _venues.addAll(venuesResponse.data);
          _filteredVenues = _venues;
          _hasMore = _currentPage < venuesResponse.totalPages;
          _isLoadingMore = false;
          _sortByDistance();
        });
      } else {
        if (!mounted) return;
        setState(() {
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      print('Error loading more venues: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _currentPage--;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
        _searchPage = 1;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _isLoading = true;
      _errorMessage = null;
      _searchPage = 1;
      _searchResults = [];
    });

    try {
      final result = await EventsAPI.discoverSearch(
        search: query,
        type: 'venues',
        page: _searchPage,
      );

      if (!mounted) return;

      final data = result?['venues'];

      if (result != null && data?['data'] != null) {
        final venues = (data['data'] as List)
            .map((json) => Venue.fromJson(json))
            .toList();

        setState(() {
          _searchResults = venues;
          _searchTotalPages = data['total_pages'] ?? 1;
          _searchHasMore = _searchPage < _searchTotalPages;
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _searchResults = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error searching venues: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error searching $_themLower. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreSearchResults() async {
    if (_isLoadingMore || !_searchHasMore) return;

    setState(() {
      _isLoadingMore = true;
      _searchPage++;
    });

    try {
      final result = await EventsAPI.discoverSearch(
        search: _searchController.text,
        type: 'venues',
        page: _searchPage,
      );

      if (!mounted) return;
      final data = result?['venues'];

      if (result != null && data?['data'] != null) {
        final venues = (data['data'] as List)
            .map((json) => Venue.fromJson(json))
            .toList();

        setState(() {
          _searchResults.addAll(venues);
          _searchHasMore = _searchPage < _searchTotalPages;
          _isLoadingMore = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      print('Error loading more search results: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _searchPage--;
      });
    }
  }

  void _sortByDistance() {
    _filteredVenues.sort((a, b) => a.distance.compareTo(b.distance));
  }

  void _onSearchChanged(String query) {
    _performSearch(query);
  }

  Future<void> _loadMyVenues() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await VenueApiService.getMyVenues();

      if (!mounted) return;

      if (result != null) {
        setState(() {
          _ownedVenues = VenuesResponse.fromJson({
            'data': result['owned_venues'],
          }).data;
          _followedVenues = VenuesResponse.fromJson({
            'data': result['followed_venues'],
          }).data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading my venues: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // Nothing above the scroll views, and no SafeArea around them. The
      // header, the search field and the tabs are all slivers inside them,
      // so the scroll moves them and the viewport never changes size — the
      // same arrangement the feed uses, and for the same reason.
      //
      // The SafeArea that used to wrap this took the status bar off the top,
      // which the shell above already holds, and the home indicator off the
      // bottom — and that second inset is a band of dead white under the
      // last row that the list can never scroll into. The shell runs with
      // extendBody, so content is meant to pass under the floating bottom
      // bar rather than stop short of it. Neither the feed nor Tracks wraps
      // itself this way.
      //
      // Every scroll in here reports to the shell through this one listener,
      // which is what takes the bottom bar away and brings it back.
      body: NotificationListener<ScrollNotification>(
        onNotification: widget.chrome?.handle ?? (_) => false,
        child: RefreshIndicator(
          onRefresh: _refreshActiveTab,
          color: theme.primaryColor,
          child: CustomScrollView(
            controller: _scrollController,
            // Always scrollable, so a short list still reaches far enough
            // for pull-to-refresh and for the chrome to be scrolled away.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _floatingChrome(),
              if (!_isSearching) _pinnedTabs(),
              ..._tabSlivers(),
            ],
          ),
        ),
      ),
    );
  }

  /// The search field's height, declared because the floating header has
  /// to know its extent before it is laid out. [_buildSearchBar] boxes
  /// itself to the same number, so the two cannot drift.
  static const double _searchBarHeight = 72;

  /// The tab row's height, declared for the same reason.
  static const double _tabBarHeight = 48;

  /// The chrome above a list: the shell's own header and section tabs, with
  /// this screen's search field under them.
  ///
  /// Floating, not pinned — it leaves as you scroll on and comes back the
  /// moment you scroll up, without having to reach the top. The search
  /// field goes with it because it is chrome too: once you are three rows
  /// into a grid, an empty search box is the least useful thing on screen.
  Widget _floatingChrome() {
    final height = widget.headerHeight + _searchBarHeight;

    return SliverPersistentHeader(
      floating: true,
      delegate: FloatingChromeHeader(
        height: height,
        vsync: this,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.header != null) widget.header!,
            _buildSearchBar(),
          ],
        ),
      ),
    );
  }

  /// Whichever tab is showing, as slivers.
  ///
  /// One scroll view holds all of this, not one per tab inside a
  /// TabBarView. With a view each, the chrome and the tabs were inside the
  /// thing that slides, so switching tab swept the header off sideways and
  /// brought an identical one back — the whole page moving to change what
  /// is under it. Here only the content swaps, and the header above it does
  /// not know a tab changed.
  ///
  /// The tab that is not showing stays in the tree: [SliverOffstage] does
  /// not lay it out, but its element is still mounted, so whatever it had
  /// loaded survives a switch and coming back costs nothing.
  List<Widget> _tabSlivers() {
    if (_isSearching) return _searchSlivers();

    return [
      SliverOffstage(
        offstage: _tabController.index != 0,
        sliver: SliverMainAxisGroup(slivers: _findSlivers()),
      ),
      SliverOffstage(
        offstage: _tabController.index != 1,
        sliver: SliverMainAxisGroup(slivers: _mySlivers()),
      ),
    ];
  }

  /// Refreshes whichever tab is showing.
  Future<void> _refreshActiveTab() {
    if (_isSearching) return _refreshVenues();
    return _tabController.index == 0 ? _refreshVenues() : _loadMyVenues();
  }

  /// Fills what is left of the viewport with [child].
  ///
  /// For the states that are not a list — loading, an error, nothing found.
  /// They sit under the chrome rather than replacing it, which matters most
  /// when a filter comes back empty: the way out of an empty list is to
  /// change the search or the distance, and both are in the chrome.
  Widget _fillRest(Widget child) =>
      SliverFillRemaining(hasScrollBody: false, child: child);

  /// The Discover / My Places tabs, which stay put.
  ///
  /// Pinned where the chrome above floats away: these are navigation, and
  /// losing them halfway down a grid would mean scrolling back to the top
  /// to change tab.
  Widget _pinnedTabs() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: PinnedSliverBar(height: _tabBarHeight, child: _buildTabBar()),
    );
  }

  Widget _buildSearchBar() {
    return SizedBox(
      height: _searchBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search $_themLower',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }

  /// "Discover" and "My Places", not "Find Venues" and "My Venues".
  ///
  /// The screen is reused for tracks, where "Find Tracks" read fine but "My
  /// Tracks" sat next to a page about places. These two name what the tabs
  /// DO — look around, or go to the ones you kept — which holds whatever
  /// the screen is listing.
  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorColor: theme.primaryColor,
        indicatorWeight: 3,
        labelColor: theme.primaryColor,
        unselectedLabelColor: theme.subtextColor,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        tabs: const [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.explore_outlined, size: 18),
                SizedBox(width: 6),
                Text('Discover'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bookmark_border_rounded, size: 18),
                SizedBox(width: 6),
                Text('My Places'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The search results, as slivers. No tabs above them — they are hidden
  /// while searching, which is what makes this a separate view at all.
  List<Widget> _searchSlivers() {
    if (_isLoading && _searchResults.isEmpty) {
      return [_fillRest(_buildLoadingSkeleton(showBanner: false))];
    }

    if (_errorMessage != null && _searchResults.isEmpty) {
      return [_fillRest(_buildErrorState())];
    }

    if (_searchResults.isEmpty) {
      return [
        _fillRest(
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  'No $_themLower found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try a different search term',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList.builder(
          itemCount: _searchResults.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _searchResults.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFAE9159)),
                ),
              );
            }

            final venue = _searchResults[index];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (index > 0) const ListingRowDivider(),
                ListingRow(
                  imageUrl: venue.coverImage,
                  title: venue.title,
                  subtitle: venue.venueLocation,
                  onTap: () => _onVenueTap(venue),
                ),
              ],
            );
          },
        ),
      ),
    ];
  }

  /// The Discover tab, as slivers.
  List<Widget> _findSlivers() {
    if (_isLoading && _venues.isEmpty) {
      return [_fillRest(_buildLoadingSkeleton(showBanner: true))];
    }

    if (_errorMessage != null && _venues.isEmpty) {
      return [_fillRest(_buildErrorState())];
    }

    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showLocationBanner) ...[
              LocationBanner(
                onUpdate: () {
                  setState(() => _showLocationBanner = false);
                  NavigationHelper.navigateTo(
                    context,
                    const AppPermissionsScreen(),
                  );
                },
              ),
            ],

            // Spacing rides with the banner: when there is nothing featured
            // the whole block disappears, instead of leaving 32pt of padding
            // wrapped around a zero-height widget.
            if (_loadingBanners || _banners.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildBanner(),
            ],

            const SizedBox(height: 16),

            _buildFilters(),

            const SizedBox(height: 16),

            _buildVenuesList(),

            // Loading indicator for pagination
            if (_isLoadingMore)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFAE9159)),
                ),
              ),

            // The same 24 Tracks leaves under its last row. Enough to
            // clear the floating bottom bar without the band of dead
            // white the SafeArea used to put here.
            const SizedBox(height: 24),
          ],
        ),
      ),
    ];
  }

  /// The featured carousel.
  ///
  /// Peeking rather than full width: the next card showing at the edge is
  /// the only thing that says the row scrolls, and without it people take
  /// the first card for a banner.
  Widget _buildBanner() {
    // Still waiting — a spinner is honest here.
    if (_loadingBanners) {
      return const SizedBox(
        height: _featuredHeight,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFAE9159)),
        ),
      );
    }

    // Loaded, and there is nothing featured. Take up no room rather than
    // leaving a band of empty. The spacing either side is dropped at the
    // call site, since shrink() only collapses this widget.
    if (_banners.isEmpty) return const SizedBox.shrink();

    final width = MediaQuery.sizeOf(context).width * 0.8;

    return SizedBox(
      height: _featuredHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _banners.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final banner = _banners[index];

          return SizedBox(
            width: width,
            child: FeaturedCard(
              imageUrl: banner['image'] ?? '',
              title: banner['title'] ?? '',
              kicker: banner['kicker'],
              subtitle: banner['location'],
              subtitleIcon: Icons.location_on_outlined,
              onTap: () => Navigator.pushNamed(
                context,
                AppRoutes.venueDetails,
                arguments: {'venueId': banner['id']},
              ),
            ),
          );
        },
      ),
    );
  }

  void _onFilterChanged() {
    _loadVenues();
  }

  void _clearCustomLocation() {
    setState(() {
      _customLocationController.clear();
      _customLocationName = null;
      _customLat = null;
      _customLng = null;
    });
  }

  // Google Places Autocomplete Input
  Widget _buildGooglePlacesInput() {
    return GooglePlaceAutoCompleteTextField(
      textEditingController: _customLocationController,
      googleAPIKey: "AIzaSyDqDMSFVfl-tOgqaj4ZqA5I3HnobrIK6jg",
      inputDecoration: InputDecoration(
        hintText: 'Enter Location',
        prefixIcon: const Icon(Icons.location_on),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      debounceTime: 400,
      countries: const ["gb", "us"],
      isLatLngRequired: true,
      getPlaceDetailWithLatLng: (prediction) {
        setState(() {
          _customLocationName = prediction.description ?? '';
          _customLat = double.tryParse(prediction.lat ?? '');
          _customLng = double.tryParse(prediction.lng ?? '');
        });
      },
      itemClick: (prediction) {
        _customLocationController.text = prediction.description ?? '';
        _customLocationController.selection = TextSelection.fromPosition(
          TextPosition(offset: prediction.description?.length ?? 0),
        );
      },
      seperatedBuilder: const Divider(),
      containerHorizontalPadding: 0,
      itemBuilder: (context, index, prediction) {
        return Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.grey, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  prediction.description ?? '',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        );
      },
      isCrossBtnShown: true,
    );
  }

  void _showLocationFilter(ThemeProvider theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FilterBottomSheet(
          title: 'Filter by Location',
          multiSelect: false,
          options: [
            FilterOption(label: 'National', value: 'national'),
            FilterOption(label: 'Near me', value: 'near-me'),
            FilterOption(label: '50 Miles', value: '50-miles'),
            FilterOption(label: '100 Miles', value: '100-miles'),
            FilterOption(label: 'Custom', value: 'custom'),
          ],
          selectedValues: _selectedLocation != null
              ? [_selectedLocation!]
              : ['national'],
          customWidget: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGooglePlacesInput(), // NEW: Use Google Places widget
              const SizedBox(height: 8),
              if (_customLocationName != null &&
                  _customLocationName!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Location selected: $_customLocationName',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  'Search for a city, postcode, or address',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
          onApply: (selected) async {
            final newLocation = selected.isNotEmpty
                ? selected.first
                : 'national';
            final needsLocationAccess = [
              'near-me',
              '50-miles',
              '100-miles',
            ].contains(newLocation);

            // Re-check permissions/services if user picks a location-based option
            if (needsLocationAccess) {
              // Re-check (handles "user enabled it in Settings between visits")
              final hasAccess = await context
                  .read<LocationAccessProvider>()
                  .refresh();
              if (!mounted) return;

              if (!hasAccess) {
                setState(() => _showLocationBanner = true);
                // Show a snackbar so the user knows why their pick didn't stick
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Location access is needed for this filter. Falling back to National.',
                    ),
                    action: SnackBarAction(
                      label: 'Settings',
                      onPressed: () => Geolocator.openLocationSettings(),
                    ),
                  ),
                );
                // Force the selection to National since the chosen one won't work
                setState(() => _selectedLocation = 'national');
                _onFilterChanged();
                return;
              } else {
                setState(() => _showLocationBanner = false);
              }
            }

            setState(() {
              _selectedLocation = newLocation;
              if (_selectedLocation != 'custom') {
                _clearCustomLocation();
              }
            });
            _onFilterChanged();
          },
        ),
      ),
    );
  }

  // Filter Button Widget
  /// The distance pills.
  ///
  /// Pills rather than the two dropdown buttons that were here. A dropdown
  /// hides its options behind a tap and a sheet; for four distances the
  /// whole decision fits on screen, and the one in force is readable
  /// without opening anything.
  ///
  /// There is no category control any more. It offered All, Race Tracks and
  /// Car Shows over a listing that no longer holds tracks — they have their
  /// own screen — so two of its three values were dead and the third was
  /// everything.
  Widget _buildFilters() {
    return ListingChips(
      selected: _selectedLocation ?? _defaultDistance,
      onChanged: (value) {
        // The last pill is not a distance — it opens the place search, and
        // only sets the filter once somewhere is picked.
        if (value == 'custom') {
          _showLocationFilter(theme);
          return;
        }

        if (value == _selectedLocation) return;
        setState(() => _selectedLocation = value);
        _onFilterChanged();
      },
      chips: [
        const ListingChip(label: 'Near me', value: 'near-me'),
        const ListingChip(label: '50 miles', value: '50-miles'),
        const ListingChip(label: '100 miles', value: '100-miles'),
        const ListingChip(label: 'National', value: 'national'),
        // Shows where it is pointed once it is pointed somewhere, because
        // "Custom" tells you a choice was made but not what.
        ListingChip(
          label: _customLocationName ?? 'Somewhere else',
          value: 'custom',
        ),
      ],
    );
  }

  /// The results, two to a row.
  ///
  /// A grid rather than the full-width rows this used to be. A place is
  /// chosen off its photograph more than off its address, and at two columns
  /// twice as many photographs are on screen at once.
  /// The results, as rows.
  ///
  /// Rows rather than a grid of cards. The grid showed the photographs
  /// bigger and fewer; four or five of these fit where two cards did, and
  /// what anyone scans a list of places for is the name and where it is.
  /// The picture is there to tell them apart, which a thumbnail does.
  Widget _buildVenuesList() {
    if (_filteredVenues.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _buildEmptyState(),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < _filteredVenues.length; i++) ...[
          if (i > 0) const ListingRowDivider(),
          ListingRow(
            imageUrl: _filteredVenues[i].coverImage,
            title: _filteredVenues[i].title,
            subtitle: _filteredVenues[i].venueLocation,
            onTap: () => _onVenueTap(_filteredVenues[i]),
          ),
        ],
      ],
    );
  }

  Widget _createVenueSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFB8935E), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Own a venue?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final response = await Navigator.pushNamed(
                context,
                AppRoutes.createVenue,
              );

              if (response == true) {
                _loadMyVenues();
              }
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Venue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB8935E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The My Places tab, as slivers.
  List<Widget> _mySlivers() {
    if (_isLoading && _ownedVenues.isEmpty && _followedVenues.isEmpty) {
      return [_fillRest(_buildLoadingSkeleton(showBanner: false))];
    }

    if (_ownedVenues.isEmpty && _followedVenues.isEmpty) {
      return [
        _fillRest(
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 80,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'No $_themLower found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You don\'t own or follow any venues yet',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverList(
        delegate: SliverChildListDelegate([
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              _ownedVenues.isNotEmpty
                  ? 24
                  : 16, // Add more spacing if owned venues exist
              16,
              8,
            ),
            child: _createVenueSection(),
          ),

          // Owned Venues Section
          if (_ownedVenues.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Text(
                    'My $_them',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
            // The same rows the Discover tab uses. Two card shapes for the
            // same venue, one per tab, was what made this screen look like
            // two screens.
            ..._ownedVenues.map(
              (venue) => ListingRow(
                imageUrl: venue.coverImage,
                title: venue.title,
                subtitle: venue.venueLocation,
                onTap: () => _onVenueTap(venue),
              ),
            ),
          ],

          // Followed Venues Section
          if (_followedVenues.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                _ownedVenues.isNotEmpty
                    ? 24
                    : 16, // Add more spacing if owned venues exist
                16,
                8,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      Text(
                        'Followed $_them',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ..._followedVenues.map(
              (venue) => ListingRow(
                imageUrl: venue.coverImage,
                title: venue.title,
                subtitle: venue.venueLocation,
                onTap: () => _onVenueTap(venue),
              ),
            ),
          ],
        ]),
      ),
    ];
  }

  Widget _buildLoadingSkeleton({required bool showBanner}) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Banner skeleton
          if (showBanner) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 2,
                itemBuilder: (context, index) {
                  return Shimmer.fromColors(
                    baseColor: Colors.grey.shade300,
                    highlightColor: Colors.grey.shade100,
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.85,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Filter skeleton
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Shimmer.fromColors(
                      baseColor: Colors.grey.shade300,
                      highlightColor: Colors.grey.shade100,
                      child: Container(
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Shimmer.fromColors(
                      baseColor: Colors.grey.shade300,
                      highlightColor: Colors.grey.shade100,
                      child: Container(
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Cards skeleton
          ...List.generate(3, (index) => _buildLoadingCard()),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No $_themLower found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Can't find what you're looking for? Add it.",
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.pushNamed(
                context,
                '/create-venue', // adjust to your route
              );
              if (result == true && mounted) {
                // refresh the list — call your existing reload method
                _loadVenues();
              }
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add venue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC4A062),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            'Oops!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'Something went wrong',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadVenues,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFAE9159),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _onVenueTap(Venue venue) {
    Navigator.pushNamed(
      context,
      AppRoutes.venueDetails,
      arguments: {'venueId': venue.id},
    );
  }
}
