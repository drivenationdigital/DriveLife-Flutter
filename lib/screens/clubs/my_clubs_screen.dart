import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/models/my_clubs.dart';
import 'package:drivelife/providers/location_access_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/account-settings/app_permissions_screen.dart';
import 'package:drivelife/screens/clubs/add_club_screen.dart';
import 'package:drivelife/screens/events/events_screen.dart';
import 'package:drivelife/screens/profile/view_club_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/widgets/events/filter_bottom_sheet.dart';
import 'package:drivelife/widgets/listing/featured_card.dart';
import 'package:drivelife/widgets/listing/listing_row.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/api/club_api_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:provider/provider.dart';

class MyClubsScreen extends StatefulWidget {
  const MyClubsScreen({super.key});

  @override
  State<MyClubsScreen> createState() => _MyClubsScreenState();
}

class _MyClubsScreenState extends State<MyClubsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ThemeProvider theme;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // ===========================================================================
  // MY CLUBS — real data (unchanged logic)
  // ===========================================================================
  List<MyClub> _clubs = [];
  bool _isLoading = true;
  String? _errorMessage;

  // ===========================================================================
  // DISCOVER — hardcoded placeholder data
  // ===========================================================================
  bool _isSearching = false;
  bool _isDiscoverLoading = true;
  bool _isDiscoverLoadingMore = false;
  String? _discoverError;
  List<dynamic> _discoverClubs = [];
  List<dynamic> _searchResults = [];
  bool _isSearchLoading = false;
  int _discoverPage = 1;
  bool _discoverHasMore = true;
  Timer? _searchDebounce;

  String _selectedClubType = 'all';
  String _selectedLocation = 'near-me';
  bool _showLocationBanner = false;

  final TextEditingController _customLocationController =
      TextEditingController();
  double? _customLat;
  double? _customLng;
  String? _customLocationName;

  int _spotlightPage = 0;
  late final PageController _spotlightController;

  // Spotlight (featured) — API-loaded
  List<dynamic> _spotlightClubs = [];
  bool _isSpotlightLoading = true;

  static const int _totalClubResults = 128;
  List<FilterOption> _clubTypes = [];
  bool _loadingClubTypes = false;

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
        _selectedLocation = hasAccess ? 'near-me' : 'national';
      });
    });

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _spotlightController = PageController(viewportFraction: 0.88);
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    _loadMyClubs();
    _loadDiscoverClubs();
    _loadFeaturedClubs();
    _loadClubTypes();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _spotlightController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final searching = _searchController.text.trim().isNotEmpty;
    if (searching != _isSearching) {
      setState(() => _isSearching = searching);
    }

    // Debounce the actual API call
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (searching) {
        _performClubSearch(_searchController.text.trim());
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.9) {
      if (!_isSearching &&
          !_isDiscoverLoadingMore &&
          _discoverHasMore &&
          _tabController.index == 0) {
        _loadMoreDiscoverClubs();
      }
    }
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && _clubs.isEmpty && !_isLoading) {
      _loadMyClubs();
    }
  }

  Future<void> _loadFeaturedClubs() async {
    if (!mounted) return;
    setState(() => _isSpotlightLoading = true);

    try {
      final result = await ClubApiService.fetchFeaturedClubs();
      if (!mounted) return;
      setState(() {
        _spotlightClubs = result ?? [];
        _isSpotlightLoading = false;
        // Reset page if it's now out of range
        if (_spotlightPage >= _spotlightClubs.length) _spotlightPage = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _spotlightClubs = [];
        _isSpotlightLoading = false;
      });
    }
  }

  Future<void> _loadMyClubs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ClubApiService.getMyClubs();

      if (!mounted) return;

      if (response.success && response.data != null) {
        setState(() {
          _clubs = response.data!.clubs;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Failed to load groups';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDiscoverClubs() async {
    if (!mounted) return;

    setState(() {
      _isDiscoverLoading = true;
      _discoverError = null;
      _discoverPage = 1;
      _discoverClubs = [];
    });

    try {
      final result = await ClubApiService.fetchClubs(
        page: _discoverPage,
        category: _selectedClubType,
        lat: _customLat,
        lng: _customLng,
        location: _selectedLocation,
      );

      if (!mounted) return;

      setState(() {
        _discoverClubs = result ?? [];
        _discoverHasMore = (result?.length ?? 0) >= 15;
        _isDiscoverLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _discoverError = 'Could not load groups. Pull to retry.';
        _isDiscoverLoading = false;
      });
    }
  }

  Future<void> _loadMoreDiscoverClubs() async {
    if (_isDiscoverLoadingMore || !_discoverHasMore) return;

    setState(() {
      _isDiscoverLoadingMore = true;
      _discoverPage++;
    });

    try {
      final result = await ClubApiService.fetchClubs(
        page: _discoverPage,
        category: _selectedClubType,
        lat: _customLat,
        lng: _customLng,
        location: _selectedLocation,
      );

      if (!mounted) return;

      setState(() {
        _discoverClubs.addAll(result ?? []);
        _discoverHasMore = (result?.length ?? 0) >= 15;
        _isDiscoverLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDiscoverLoadingMore = false;
        _discoverPage--;
      });
    }
  }

  Future<void> _performClubSearch(String query) async {
    if (!mounted || query.isEmpty) return;
    setState(() {
      _isSearchLoading = true;
      _searchResults = [];
    });

    try {
      final result = await ClubApiService.fetchClubs(search: query);

      if (!mounted) return;
      setState(() {
        _searchResults = result ?? [];
        _isSearchLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearchLoading = false);
    }
  }

  void _openClubEditor(MyClub club) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateClubScreen(existingClubId: club.clubId),
      ),
    );

    if (result == true || result == 'deleted') {
      _loadMyClubs();
    }
  }

  @override
  Widget build(BuildContext context) {
    theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      // top: false — the shell above already holds the status bar area, and
      // the section tabs sit between it and this screen. Claiming it again
      // put a band of white between the tabs and the search field.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildSearchBar(),
            if (!_isSearching) _buildTabBar(),
            Expanded(
              child: _isSearching
                  ? _buildSearchResultsView()
                  : TabBarView(
                      controller: _tabController,
                      children: [_buildDiscoverTab(), _buildMyClubsTab()],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoverTab() {
    if (_isDiscoverLoading && _discoverClubs.isEmpty) {
      final theme = Provider.of<ThemeProvider>(context);
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    if (_discoverError != null && _discoverClubs.isEmpty) {
      return _buildErrorState(_discoverError!, _loadDiscoverClubs);
    }

    // Show spotlight only when not loading AND we have featured clubs
    final showSpotlight = !_isSpotlightLoading && _spotlightClubs.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadDiscoverClubs(), _loadFeaturedClubs()]);
      },
      color: theme.primaryColor,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
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

            if (showSpotlight) ...[
              // const SizedBox(height: 16),
              // _buildSpotlightHeader(),
              const SizedBox(height: 12),
              _buildSpotlightCarousel(),
              const SizedBox(height: 12),
              _buildSpotlightDots(),
              const SizedBox(height: 20),
            ] else
              const SizedBox(height: 16),
            _buildFilters(),
            // const SizedBox(height: 20),
            // _buildAllClubsHeader(),
            const SizedBox(height: 12),
            _buildDiscoverClubsList(),
            if (_isDiscoverLoadingMore)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(color: theme.primaryColor),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildAllClubsHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // const Text(
          //   'All Clubs',
          //   style: TextStyle(
          //     fontSize: 18,
          //     fontWeight: FontWeight.w700,
          //     color: Colors.black,
          //   ),
          // ),
          // Text(
          //   '${_discoverClubs.length} ${_discoverClubs.length == 1 ? "result" : "results"}',
          //   style: TextStyle(
          //     fontSize: 13,
          //     color: Colors.grey.shade600,
          //     fontWeight: FontWeight.w500,
          //   ),
          // ),
        ],
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
            'No groups found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Start your own and bring your community together.",
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.pushNamed(context, '/add-club');
              if (result == true && mounted) {
                _loadMyClubs();
              }
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add group'),
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

  /// The clubs, as rows.
  ///
  /// The same [ListingRow] Places and Tracks list with — thumbnail, name,
  /// chevron, hairline. Clubs were the last of the three still laid out as
  /// a grid of cards, which is the sort of difference nobody can name but
  /// everybody feels when they move between the tabs.
  Widget _buildDiscoverClubsList() {
    if (_discoverClubs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Center(child: _buildEmptyState()),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < _discoverClubs.length; i++) ...[
          if (i > 0) const ListingRowDivider(),
          Builder(
            builder: (context) {
              final club = _discoverClubs[i] as Map<String, dynamic>;

              return ListingRow(
                imageUrl: _clubThumb(club),
                title: _clubText(club['title']),
                onTap: () => NavigationHelper.navigateTo(
                  context,
                  ClubViewScreen(
                    clubPostId: club['ID'],
                    isOwnClub: false,
                    showAppBar: true,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSearchResultsView() {
    if (_isSearchLoading && _searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No groups found',
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
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final club = _searchResults[index] as Map<String, dynamic>;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index > 0) const ListingRowDivider(),
            ListingRow(
              imageUrl: _clubThumb(club),
              title: _clubText(club['title']),
              onTap: () => NavigationHelper.navigateTo(
                context,
                ClubViewScreen(
                  clubPostId: club['ID'],
                  isOwnClub: false,
                  showAppBar: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------- Search bar ----------
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search groups',
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () => _searchController.clear(),
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
    );
  }

  // ---------- Tab bar ----------
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
                Text('Discover Clubs'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_border, size: 18),
                SizedBox(width: 6),
                Text('My Clubs'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildSpotlightHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FEATURED',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: theme.primaryColor,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Spotlight Groups',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The featured carousel.
  ///
  /// The same [FeaturedCard] that heads the venues and tracks screens, so
  /// the three listing pages read as one app rather than three that happen
  /// to share a logo.
  Widget _buildSpotlightCarousel() {
    return SizedBox(
      height: _featuredHeight,
      child: PageView.builder(
        controller: _spotlightController,
        padEnds: false,
        itemCount: _spotlightClubs.length,
        onPageChanged: (i) => setState(() => _spotlightPage = i),
        itemBuilder: (context, index) {
          final club = _spotlightClubs[index] as Map<String, dynamic>;

          return Padding(
            padding: EdgeInsets.only(
              left: index == 0 ? 16 : 6,
              right: index == _spotlightClubs.length - 1 ? 16 : 6,
            ),
            child: FeaturedCard(
              imageUrl: _clubImage(club),
              title: _clubText(club['title']),
              kicker: _clubText(club['category']),
              subtitle: _clubStanding(club),
              subtitleIcon: Icons.person_outline_rounded,
              onTap: () => NavigationHelper.navigateTo(
                context,
                ClubViewScreen(
                  clubPostId: club['ID'],
                  isOwnClub: false,
                  showAppBar: true,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// How tall the featured carousel is. Named because the carousel, the
  /// dots under it and the loading state all have to agree.
  static const double _featuredHeight = 172;

  /// A club's picture for the featured carousel: the cover, which fills a
  /// card 250px wide and wants a photograph.
  static String _clubImage(Map<String, dynamic> club) {
    final cover = _clubText(club['cover_image']);
    return cover.isNotEmpty ? cover : _clubText(club['logo']);
  }

  /// A club's picture for a row: the badge, which is drawn to be read at
  /// 56px square where a cropped cover is a patch of sky.
  static String _clubThumb(Map<String, dynamic> club) {
    final logo = _clubText(club['logo']);
    return logo.isNotEmpty ? logo : _clubText(club['cover_image']);
  }

  /// A string from the API, or empty. Clubs come back with nulls and
  /// numbers in fields that are nominally text.
  static String _clubText(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    return text == 'null' ? '' : text;
  }

  /// "1,284 members · Yorkshire", or whichever half of it exists.
  ///
  /// The member count has been missing from this endpoint before now — it
  /// was commented out of the old card rather than guarded — so it is shown
  /// only when there is a real number behind it.
  static String _clubStanding(Map<String, dynamic> club) {
    final where = _clubText(club['location']);
    final raw = club['member_count'] ?? club['members_count'];

    final count = raw is num
        ? raw.toInt()
        : (raw is String ? int.tryParse(raw.trim()) : null);

    final members = count == null || count <= 0
        ? ''
        : '${_grouped(count)} member${count == 1 ? '' : 's'}';

    if (members.isEmpty) return where;
    if (where.isEmpty) return members;
    return '$members · $where';
  }

  /// 1284 as "1,284".
  static String _grouped(int value) {
    final digits = value.toString();
    final out = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }

    return out.toString();
  }

  Widget _buildSpotlightDots() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_spotlightClubs.length, (i) {
          final active = i == _spotlightPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 6,
            width: active ? 18 : 6,
            decoration: BoxDecoration(
              color: active ? theme.primaryColor : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
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
      countries: const [
        "gb",
        "us",
      ], // Restrict to specific countries if needed, or remove for worldwide
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

  void _clearCustomLocation() {
    setState(() {
      _customLocationController.clear();
      _customLocationName = null;
      _customLat = null;
      _customLng = null;
    });
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
          selectedValues: [_selectedLocation],
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

  void _onFilterChanged() {
    // For now, just reload the discover clubs with new filters
    _loadDiscoverClubs();
  }

  Future<void> _loadClubTypes() async {
    if (!mounted) return;
    setState(() => _loadingClubTypes = true);

    try {
      final types = await ClubApiService.fetchClubTypes();
      if (!mounted) return;
      setState(() {
        _clubTypes = types;
        _loadingClubTypes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingClubTypes = false);
    }
  }

  void _onClubTypeFilterTapped() {
    if (_loadingClubTypes) return; // ignore taps while loading

    if (_clubTypes.isEmpty) {
      // Try one retry in case the initial fetch failed
      _loadClubTypes();
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => FilterBottomSheet(
        title: 'Filter by Group Type',
        multiSelect: false,
        options: [
          FilterOption(label: 'All', value: 'all'),
          ..._clubTypes,
        ],
        selectedValues: [_selectedClubType],
        onApply: (selected) {
          setState(() {
            _selectedClubType = selected.isNotEmpty ? selected.first : 'all';
          });
          _onFilterChanged();
        },
      ),
    );
  }

  String _resolveClubTypeLabel() {
    // Look up the label that matches the stored value
    final match = _clubTypes.firstWhere(
      (t) => t.value == _selectedClubType,
      orElse: () => FilterOption(label: 'All', value: 'all'),
    );
    return match.label;
  }

  String _resolveLocationLabel() {
    switch (_selectedLocation) {
      case 'national':
        return 'National';
      case 'near-me':
        return 'Near me';
      case '50-miles':
        return '50 Miles';
      case '100-miles':
        return '100 Miles';
      default:
        return 'Custom';
    }
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildFilterButton(
              'Club Type',
              _selectedClubType == 'all' ? 'All' : _resolveClubTypeLabel(),
              _onClubTypeFilterTapped,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildFilterButton(
              'Location',
              _resolveLocationLabel(),
              () => _showLocationFilter(theme),
            ),
          ),
        ],
      ),
    );
  }

  /// One of the two filter controls.
  ///
  /// No outline, and a softer corner than it had. Two bordered boxes side
  /// by side read as a form to be filled in; these are a pair of current
  /// answers you can change, so the fill does the work and the border goes.
  Widget _buildFilterButton(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          // A pill now it is one line tall, like the distance chips on
          // Places and Tracks.
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              // Label and value on one line, not stacked. Two lines made
              // each control 60pt tall for four words, which is a lot of
              // the screen spent on a setting that is usually left alone.
              child: Row(
                children: [
                  Text(
                    '$label ',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8A8A8E),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: Color(0xFF111111),
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF8A8A8E),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildMyClubsTab() {
    if (_isLoading) {
      final theme = Provider.of<ThemeProvider>(context);
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMyClubs,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_clubs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No groups yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first group to get started',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    const rolePriority = {'Owner': 0, 'Admin': 1, 'Member': 2};

    _clubs.sort((a, b) {
      final aRank = rolePriority[a.associationType] ?? 99;
      final bRank = rolePriority[b.associationType] ?? 99;
      return aRank.compareTo(bRank);
    });

    return RefreshIndicator(
      onRefresh: _loadMyClubs,
      color: theme.primaryColor,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _clubs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final club = _clubs[index];
          return _ClubCard(
            club: club,
            onEdit: () => _openClubEditor(club),
            onView: () async {
              final result = await NavigationHelper.navigateTo(
                context,
                ClubViewScreen(
                  clubPostId: int.parse(club.Id ?? '0'),
                  isOwnClub: false,
                  showAppBar: true,
                ),
              );

              if (!mounted) return;

              if (result == 'deleted') {
                _loadMyClubs(); // or whatever your refresh method is called
              }
            },
          );
        },
      ),
    );
  }
}

class _ClubCard extends StatelessWidget {
  final MyClub club;
  final VoidCallback onEdit;
  final VoidCallback onView;

  const _ClubCard({
    required this.club,
    required this.onEdit,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onView, // tap the card body = view profile
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: club.logo != null
                  ? Image.network(
                      club.logo!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _thumbFallback(),
                    )
                  : _thumbFallback(),
            ),
            const SizedBox(width: 12),

            // Title + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          club.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _StatusDot(isPublished: club.isPublished),
                    ],
                  ),
                  Text(
                    '${club.associationType} • ${club.memberCount} member${club.memberCount == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    semanticsIdentifier:
                        '${club.associationType}, ${club.memberCount} members',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Stacked action buttons
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // SizedBox(
                //   width: 80,
                //   height: 30,
                //   child: OutlinedButton(
                //     onPressed: onEdit,
                //     style: OutlinedButton.styleFrom(
                //       foregroundColor: primaryColor,
                //       side: BorderSide(color: primaryColor, width: 1.2),
                //       padding: EdgeInsets.zero,
                //       shape: RoundedRectangleBorder(
                //         borderRadius: BorderRadius.circular(8),
                //       ),
                //     ),
                //     child: const Text(
                //       'Edit',
                //       style: TextStyle(
                //         fontSize: 12,
                //         fontWeight: FontWeight.w600,
                //       ),
                //     ),
                //   ),
                // ),
                // const SizedBox(height: 6),
                SizedBox(
                  width: 80,
                  height: 30,
                  child: TextButton(
                    onPressed: onView,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: Colors.grey.shade700, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'View',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbFallback() {
    return Container(
      width: 56,
      height: 56,
      color: Colors.grey.shade200,
      child: Icon(Icons.group, color: Colors.grey.shade400, size: 24),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool isPublished;
  const _StatusDot({required this.isPublished});

  @override
  Widget build(BuildContext context) {
    final color = isPublished ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isPublished ? 'Live' : 'Draft',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
