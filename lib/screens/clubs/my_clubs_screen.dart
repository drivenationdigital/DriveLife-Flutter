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
          _errorMessage = response.message ?? 'Failed to load clubs';
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
        _discoverError = 'Could not load clubs. Pull to retry.';
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
      body: SafeArea(
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
      return Center(child: CircularProgressIndicator(color: theme.primaryColor));
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
                child: Center(child: CircularProgressIndicator(color: theme.primaryColor)),
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
          'No clubs found',
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
            final result = await Navigator.pushNamed(
              context,
              '/add-club',
            );
            if (result == true && mounted) {
              _loadMyClubs();
            }
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add club'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC4A062),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
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

  Widget _buildDiscoverClubsList() {
    if (              _discoverClubs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Center(
          child: _buildEmptyState(),
        ),
      );
    }

    return Column(
      children: _discoverClubs.map((club) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: _DiscoverClubCard(
            club: club as Map<String, dynamic>,
            primaryColor: theme.primaryColor,
            onView: () {
              NavigationHelper.navigateTo(
                context,
                ClubViewScreen(
                  clubPostId: club['ID'],
                  isOwnClub: false,
                  showAppBar: true,
                ),
              );
            },
          ),
        );
      }).toList(),
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
              'No clubs found',
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
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: _DiscoverClubCard(
            club: _searchResults[index] as Map<String, dynamic>,
            primaryColor: theme.primaryColor,
            onView: () {
              NavigationHelper.navigateTo(
                context,
                ClubViewScreen(
                  clubPostId: _searchResults[index]['ID'],
                  isOwnClub: false,
                  showAppBar: true,
                ),
              );
            },
          ),
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
          hintText: 'Search clubs',
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
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        tabs: const [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.explore_outlined, size: 16),
                SizedBox(width: 6),
                Text('Discover Clubs'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_border, size: 16),
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
                'Spotlight Clubs',
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

  Widget _buildSpotlightCarousel() {
    return SizedBox(
      height: 190,
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
            child: _SpotlightClubCard(club: club),
          );
        },
      ),
    );
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
        title: 'Filter by Club Type',
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

  Widget _buildFilterButton(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              color: Colors.grey.shade600,
              size: 20,
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
      return Center(child: CircularProgressIndicator(color: theme.primaryColor,));
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
              'No clubs yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first club to get started',
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
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    semanticsIdentifier: '${club.associationType}, ${club.memberCount} members',
                  )
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

class _SpotlightClubCard extends StatelessWidget {
  final Map<String, dynamic> club;

  const _SpotlightClubCard({required this.club});

  @override
  Widget build(BuildContext context) {
    String _str(dynamic v) => v is String ? v : '';
    // int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

    final imageUrl = _str(club['cover_image']).isNotEmpty
        ? _str(club['cover_image'])
        : _str(club['logo']);
    final title = _str(club['title']);
    final category = _str(club['category']);
    final location = _str(club['location'] ?? 'N/A');
    // final memberCount = _int(club['member_count']);

    return GestureDetector(
      onTap: () => NavigationHelper.navigateTo(
        context,
        ClubViewScreen(
          clubPostId: club['ID'],
          isOwnClub: false,
          showAppBar: true,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _imageFallback(),
              )
            else
              _imageFallback(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, color: Colors.amber, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Featured',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (category.isNotEmpty) ...[
                    Text(
                      category,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // if (memberCount > 0) ...[
                      //   const Icon(
                      //     Icons.person_outline,
                      //     color: Colors.white70,
                      //     size: 13,
                      //   ),
                      //   const SizedBox(width: 4),
                      //   Text(
                      //     '$memberCount members',
                      //     style: const TextStyle(
                      //       color: Colors.white70,
                      //       fontSize: 12,
                      //     ),
                      //   ),
                      // ],
                      // if (memberCount > 0 && location.isNotEmpty) ...[
                      //   const SizedBox(width: 8),
                      //   const Text(
                      //     '·',
                      //     style: TextStyle(color: Colors.white70),
                      //   ),
                      //   const SizedBox(width: 8),
                      // ],
                      if (location.isNotEmpty)
                        Flexible(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageFallback() => Container(
    color: Colors.grey.shade300,
    child: Icon(Icons.group, color: Colors.grey.shade500, size: 48),
  );
}

class _DiscoverClubCard extends StatelessWidget {
  final Map<String, dynamic> club;
  final Color primaryColor;
  final VoidCallback onView;

  const _DiscoverClubCard({
    required this.club,
    required this.primaryColor,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    // Pull values with fallbacks so the card is resilient to missing fields
    String _str(dynamic v) => v is String ? v : '';
    // int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

    final title = _str(club['title']).isNotEmpty
        ? _str(club['title'])
        : _str(club['name']);
    final imageUrl = _str(club['logo']);
    // final category = _str(club['category']);
    // final location = _str(club['location'] ?? 'N/A');
    // final memberCount = _int(club['member_count']);
    final isOwnerOrMember =
        (club['is_owner'] == true) ||
        (club['is_member'] == true) ||
        (club['is_admin'] == true);

    // final subtitle = category.isNotEmpty ? category : location;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: GestureDetector(
        onTap: onView,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _fallback(),
                    )
                  : _fallback(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      if (isOwnerOrMember) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified, size: 14, color: primaryColor),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Row(
                  //   children: [
                  //     Icon(
                  //       Icons.directions_car_outlined,
                  //       size: 13,
                  //       color: primaryColor,
                  //     ),
                  //     const SizedBox(width: 4),
                  //     Flexible(
                  //       child: Text(
                  //         subtitle,
                  //         maxLines: 1,
                  //         overflow: TextOverflow.ellipsis,
                  //         style: TextStyle(fontSize: 12, color: primaryColor),
                  //       ),
                  //     ),
                  //     if (memberCount > 0) ...[
                  //       const SizedBox(width: 8),
                  //       Icon(Icons.people, size: 13, color: Colors.grey.shade600),
                  //       const SizedBox(width: 4),
                  //       Text(
                  //         '$memberCount',
                  //         style: TextStyle(
                  //           fontSize: 12,
                  //           color: Colors.grey.shade600,
                  //         ),
                  //       ),
                  //     ],
                  //   ],
                  // ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onView,
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(color: primaryColor, width: 1.2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                minimumSize: const Size(0, 32),
              ),
              child: const Text(
                'View',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Container(
    width: 56,
    height: 56,
    color: Colors.grey.shade200,
    child: Icon(Icons.group, color: Colors.grey.shade400, size: 24),
  );
}
