import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/api/places_api.dart';
import 'package:drivelife/components/venue_card.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/widgets/events/filter_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/models/venue_model.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_places_flutter/google_places_flutter.dart';

class VenuesScreen extends StatefulWidget {
  const VenuesScreen({super.key});

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends State<VenuesScreen>
    with SingleTickerProviderStateMixin {
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
  String? _selectedCategory;

  final TextEditingController _customLocationController =
      TextEditingController();
  double? _customLat;
  double? _customLng;
  String? _customLocationName;
  String? _selectedLocation = 'near-me';

  List<Map<String, String>> _banners = [];

  @override
  void initState() {
    super.initState();
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

  void _onTabChanged() {
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

  Future<void> _loadFeaturedVenues() async {
    try {
      final result = await VenueApiService.getFeaturedVenues();
      if (!mounted) return;

      if (result != null && result.isNotEmpty) {
        setState(() {
          _banners = result
              .map<Map<String, String>>(
                (venue) => {
                  'image': venue['banner_image'] ?? '',
                  'title': venue['name'] ?? '',
                  'id': venue['id'].toString(),
                },
              )
              .toList();
        });
      }
    } catch (e) {
      print('Error loading featured venues: $e');
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
          _errorMessage = 'Failed to load venues';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading venues: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading venues. Please try again.';
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
        _errorMessage = 'Error searching venues. Please try again.';
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
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            _buildSearchBar(),

            // Show tabs only when not searching
            if (!_isSearching) _buildTabBar(),

            // Content
            Expanded(
              child: _isSearching
                  ? _buildSearchResultsView()
                  : TabBarView(
                      controller: _tabController,
                      children: [_buildFindVenuesTab(), _buildMyVenuesTab()],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search venues',
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
    );
  }

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
                Icon(Icons.location_on, size: 16),
                SizedBox(width: 4),
                Text('Find Venues'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite, size: 16),
                SizedBox(width: 4),
                Text('My Venues'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsView() {
    if (_isLoading && _searchResults.isEmpty) {
      return _buildLoadingSkeleton(showBanner: false);
    }

    if (_errorMessage != null && _searchResults.isEmpty) {
      return _buildErrorState();
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No venues found',
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
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: VenueCard(venue: venue, onTap: () => _onVenueTap(venue)),
        );
      },
    );
  }

  Widget _buildFindVenuesTab() {
    if (_isLoading && _venues.isEmpty) {
      return _buildLoadingSkeleton(showBanner: true);
    }

    if (_errorMessage != null && _venues.isEmpty) {
      return _buildErrorState();
    }

    if (_filteredVenues.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _refreshVenues,
      color: theme.primaryColor,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildBanner(),

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

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner() {
    // Add a check to see if banners are loaded
    if (_banners.isEmpty) {
      return const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _banners.length,
        itemBuilder: (context, index) {
          final banner = _banners[index];
          return GestureDetector(
            onTap: () => {
              Navigator.pushNamed(
                context,
                AppRoutes.venueDetails,
                arguments: {'venueId': banner['id']},
              ),
            },
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      banner['image']!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey.shade200,
                          child: Icon(
                            Icons.image_not_supported,
                            color: Colors.grey.shade400,
                            size: 40,
                          ),
                        );
                      },
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                        ),
                      ),
                    ),
                    // Changed positioning to center the title
                    Center(
                      child: Text(
                        banner['title']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ],
                ),
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
              : ['near-me'],
          customWidget: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGooglePlacesInput(),
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
          onApply: (selected) {
            setState(() {
              _selectedLocation = selected.isNotEmpty
                  ? selected.first
                  : 'near-me';
              // Clear custom location if not using custom
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
  Widget _buildFilterButton(String label, String value, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
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
      ),
    );
  }

  void _showCategoryFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => FilterBottomSheet(
        title: 'Filter by Category',
        multiSelect: false,
        options: [
          FilterOption(label: 'All', value: 'all'),
          FilterOption(label: 'Race Tracks', value: 'race-tracks'),
          FilterOption(label: 'Car Shows', value: 'car-shows'),
        ],
        selectedValues: _selectedCategory != null ? [_selectedCategory!] : [],
        onApply: (selected) {
          setState(() {
            _selectedCategory = selected.isNotEmpty ? selected.first : null;
          });
          _onFilterChanged();
        },
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildFilterButton(
            'Category',
            _selectedCategory == 'race-tracks'
                ? 'Race Tracks'
                : _selectedCategory == 'car-shows'
                ? 'Car Shows'
                : 'All',
            () => _showCategoryFilter(),
          ),
          const SizedBox(width: 12),
          _buildFilterButton(
            'Location',
            _selectedLocation == 'national'
                ? 'National'
                : _selectedLocation == 'near-me'
                ? 'Near me'
                : _selectedLocation == '50-miles'
                ? '50 Miles'
                : _selectedLocation == '100-miles'
                ? '100 Miles'
                : _customLocationName ?? 'Custom',
            () => _showLocationFilter(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildVenuesList() {
    return Column(
      children: _filteredVenues.map((venue) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: VenueCard(venue: venue, onTap: () => _onVenueTap(venue)),
        );
      }).toList(),
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
            'Hosting your own event?',
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

  Widget _buildMyVenuesTab() {
    // Loading state
    if (_isLoading && _ownedVenues.isEmpty && _followedVenues.isEmpty) {
      return _buildLoadingSkeleton(showBanner: false);
    }

    // Empty state - no owned or followed venues
    if (_ownedVenues.isEmpty && _followedVenues.isEmpty) {
      return Center(
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
              'No venues found',
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
      );
    }

    // Show venues with sections
    return RefreshIndicator(
      onRefresh: _loadMyVenues,
      color: theme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
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
                    'My Venues',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
            ..._ownedVenues.map((venue) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: VenueCard(
                  venue: venue,
                  onTap: () => _onVenueTap(venue),
                  showOwnerBadge: true,
                ),
              );
            }),
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
                        'Followed Venues',
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
            ..._followedVenues.map((venue) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: VenueCard(
                  venue: venue,
                  onTap: () => _onVenueTap(venue),
                  showOwnerBadge: false,
                ),
              );
            }),
          ],
        ],
      ),
    );
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
            'No venues found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
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
