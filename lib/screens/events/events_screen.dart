import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/events/add_event_screen.dart';
import 'package:drivelife/screens/events/order_ticket_view.dart';
import 'package:drivelife/utils/date.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/widgets/events/event_search_results.dart';
import 'package:drivelife/widgets/events/featured_events.dart';
import 'package:drivelife/widgets/events/my_events.dart';
import 'package:drivelife/widgets/events/my_tickets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/widgets/events/filter_bottom_sheet.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:google_places_flutter/google_places_flutter.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late TabController _tabController;
  final PageController _bannerController = PageController();
  final ScrollController _scrollController = ScrollController();

  final TextEditingController _customLocationController =
      TextEditingController();
  double? _customLat;
  double? _customLng;
  String? _customLocationName;

  // Search
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];

  int _currentBannerIndex = 0;

  // Filters
  String? _selectedDate = 'anytime'; // Changed default
  List<String> _selectedCategories = [];
  String? _selectedLocation = 'near-me'; // Changed default

  DateTime? _customDateFrom;
  DateTime? _customDateTo;

  // Events data
  List<Map<String, dynamic>> _upcomingEvents = [];
  List<Map<String, dynamic>> _featuredEvents = [];
  List<Map<String, dynamic>> _likedEvents = [];
  List<Map<String, dynamic>> _myCreatedEvents = [];
  List<Map<String, dynamic>> _categories = [];

  List<Map<String, dynamic>> _activeTickets = [];
  List<Map<String, dynamic>> _pastTickets = [];
  bool _isLoadingTickets = false;
  String? _ticketsError;

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = false;
  bool _hasMore = true;

  // Debounce timer
  Timer? _scrollDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _scrollController.addListener(_onScroll);

    // Fetch initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchFeaturedEvents();
      _fetchCategories();
      _fetchEvents(refresh: true);
      _fetchProfileEvents();
      _fetchUserTickets();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bannerController.dispose();
    _scrollController.dispose();
    _scrollDebounce?.cancel();
    _customLocationController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollDebounce?.isActive ?? false) _scrollDebounce!.cancel();

    _scrollDebounce = Timer(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients &&
          _scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 500 &&
          !_isLoading &&
          _hasMore &&
          _tabController.index == 0) {
        _fetchEvents();
      }
    });
  }

  void _clearCustomLocation() {
    setState(() {
      _customLocationController.clear();
      _customLocationName = null;
      _customLat = null;
      _customLng = null;
    });
  }

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults.clear();
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchResults.clear();
    });
  }

  void _onFilterChanged() {
    _fetchEvents(refresh: true);
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() => _isSearching = true);

    try {
      final results = await EventsAPI.discoverSearch(
        search: query,
        type: 'events',
        page: 1,
        perPage: 20,
      );

      if (results != null && mounted) {
        if (results['success'] != true) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
          return;
        }

        setState(() {
          _searchResults =
              (results['events']?['data'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          _isSearching = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        }
      }
    } catch (e) {
      print('Error searching: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final categories = await EventsAPI.getEventCategories();

      if (categories != null && mounted) {
        setState(() {
          _categories = categories;
        });
      }
    } catch (e) {
      print('Error fetching categories: $e');
    }
  }

  Future<void> _fetchEvents({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    if (refresh) {
      _currentPage = 1;
      _upcomingEvents.clear();
      _hasMore = true;
    }

    try {
      // Join multiple categories with comma for API
      final categoryFilter = _selectedCategories.isNotEmpty
          ? _selectedCategories.join(',')
          : null;

      final response = await EventsAPI.getEvents(
        page: _currentPage,
        limit: 10,
        category: categoryFilter,
        location: _selectedLocation,
        dateFilter: _selectedDate,
        customDateFrom: _selectedDate == 'custom'
            ? _customDateFrom
            : null, // NEW
        customDateTo: _selectedDate == 'custom' ? _customDateTo : null, // NEW
        customLocation: _selectedLocation == 'custom'
            ? _customLocationName
            : null, // NEW
        customLat: _selectedLocation == 'custom' ? _customLat : null, // NEW
        customLng: _selectedLocation == 'custom' ? _customLng : null, // NEW
      );
      if (response != null && mounted) {
        final List<dynamic> events = response['data'] ?? [];
        final totalPages = response['total_pages'] ?? 1;
        final currentPage = response['current_page'] ?? 1;

        setState(() {
          if (refresh) {
            _upcomingEvents = events.cast<Map<String, dynamic>>();
          } else {
            _upcomingEvents.addAll(events.cast<Map<String, dynamic>>());
          }

          _totalPages = totalPages;
          _currentPage = currentPage + 1; // Increment for next fetch
          _hasMore = events.isNotEmpty && events.length >= 10;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error fetching events: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchFeaturedEvents() async {
    try {
      final response = await EventsAPI.getFeaturedEvents();

      if (response != null && response['success'] == true && mounted) {
        final events = response['data'];
        setState(() {
          _featuredEvents =
              (events as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        });
      }
    } catch (e) {
      print('Error fetching featured events: $e');
    }
  }

  Future<void> _fetchProfileEvents() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user == null) return;

      final response = await EventsAPI.getProfileEvents(
        userId: user.id.toString(),
      );

      if (response != null && response['success'] == true && mounted) {
        final events = response['events'];
        setState(() {
          _myCreatedEvents =
              (events['my_events'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          _likedEvents =
              (events['saved_events'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
        });
      }
    } catch (e) {
      print('Error fetching profile events: $e');
    }
  }

  Future<void> _fetchUserTickets() async {
    if (!mounted) return;

    setState(() {
      _isLoadingTickets = true;
      _ticketsError = null;
    });

    try {
      final response = await EventsAPI.getMyEventTickets();
      print('🎟️ User tickets response: $response');
      if (!mounted) return;

      if (response != null && response['success'] == true) {
        final data = response['data'] as Map<String, dynamic>?;

        final active = (data?['active'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final past = (data?['past'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();

        setState(() {
          _activeTickets = active;
          _pastTickets = past;
          _isLoadingTickets = false;
        });
      } else {
        setState(() {
          _ticketsError = 'Failed to load tickets';
          _isLoadingTickets = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _ticketsError = e.toString();
        _isLoadingTickets = false;
      });

      print('❌ Error fetching user tickets: $e');
    }
  }

  Future<void> _toggleEventLike(String eventId, int index) async {
    final event = _upcomingEvents[index];

    final site = event['site'] ?? 'GB';

    final isLiked = event['is_liked'] ?? false;

    // Optimistic update
    setState(() {
      _upcomingEvents[index]['is_liked'] = !isLiked;
    });

    final success = await EventsAPI.toggleEventLike(
      eventId: eventId,
      site: site,
    );

    if (!success && mounted) {
      // Revert on failure
      setState(() {
        _upcomingEvents[index]['is_liked'] =
            !_upcomingEvents[index]['is_liked'];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update event'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _selectCustomDate(
    BuildContext context,
    bool isFromDate,
    StateSetter setModalState,
  ) async {
    final initialDate = isFromDate
        ? (_customDateFrom ?? DateTime.now())
        : (_customDateTo ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _customDateFrom = picked;
          // Auto-set end date to 1 week later
          _customDateTo = picked.add(const Duration(days: 7));
        } else {
          _customDateTo = picked;
        }
      });

      // Update the modal immediately
      setModalState(() {});
    }
  }

  void _showDateFilter(ThemeProvider theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        // NEW: Wrap with StatefulBuilder
        builder: (context, setModalState) => FilterBottomSheet(
          title: 'Filter by Date',
          multiSelect: false,
          options: [
            FilterOption(label: 'Anytime', value: 'anytime'),
            FilterOption(label: 'Today', value: 'today'),
            FilterOption(label: 'Tomorrow', value: 'tomorrow'),
            FilterOption(label: 'This Weekend', value: 'this-weekend'),
            FilterOption(label: 'Custom', value: 'custom'),
          ],
          selectedValues: _selectedDate != null
              ? [_selectedDate!]
              : ['anytime'],
          customWidget: Column(
            children: [
              const Text(
                'Select Date Range',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectCustomDate(
                        context,
                        true,
                        setModalState,
                      ), // Pass setModalState
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'From',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _customDateFrom != null
                                  ? DateFormat(
                                      'MMM dd, yyyy',
                                    ).format(_customDateFrom!)
                                  : 'Select date',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectCustomDate(
                        context,
                        false,
                        setModalState,
                      ), // Pass setModalState
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'To',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _customDateTo != null
                                  ? DateFormat(
                                      'MMM dd, yyyy',
                                    ).format(_customDateTo!)
                                  : 'Select date',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          onApply: (selected) {
            setState(() {
              _selectedDate = selected.isNotEmpty ? selected.first : 'anytime';
            });
            _onFilterChanged();
          },
        ),
      ),
    );
  }

  void _showCategoryFilter(ThemeProvider theme) {
    final options = _categories.map((cat) {
      return FilterOption(label: cat['name'], value: cat['id'].toString());
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => FilterBottomSheet(
        title: 'Filter by Category',
        multiSelect: true,
        options: options,
        selectedValues: _selectedCategories,
        onApply: (selected) {
          setState(() {
            _selectedCategories = selected;
          });
          _onFilterChanged();
        },
      ),
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
          onApply: (selected) {
            setState(() {
              _selectedLocation = selected.isNotEmpty
                  ? selected.first
                  : 'national';
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search events...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey.shade400),
                        onPressed: _clearSearch,
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          if (_searchController.text.isEmpty)
            // Tab Bar
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: theme.primaryColor,
                indicatorWeight: 3,
                labelColor: theme.primaryColor,
                unselectedLabelColor: Colors.grey.shade600,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                isScrollable: false,
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event, size: 16),
                        SizedBox(width: 4),
                        Text('Upcoming'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite_border, size: 16),
                        SizedBox(width: 4),
                        Text('My Events'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.confirmation_number_outlined, size: 16),
                        SizedBox(width: 4),
                        Text('Tickets'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Content
          Expanded(
            child: _searchController.text.isNotEmpty
                ? _buildSearchResults(
                    theme,
                  ) // NEW: Show search results when searching
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildUpcomingEventsTab(theme),
                      _buildMyEventsTab(),
                      _buildMyTicketsTab(),
                    ],
                  ),
          ),
        ],
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

  // Widget for rendering search results
  Widget _buildSearchResults(ThemeProvider theme) {
    return SearchResultsContent(
      isSearching: _isSearching,
      searchResults: _searchResults,
      primaryColor: theme.primaryColor,
      onEventTap: (event) {
        Navigator.pushNamed(
          context,
          '/event-detail',
          arguments: {'event': event},
        );
      },
      formatEventDate: (date) {
        return DateHelpers.formatEventDate(date);
      },
      formatEventTime: (startDate, endDate) {
        if (startDate == null || endDate == null) return null;
        return DateHelpers.formatEventTime(startDate, endDate);
      },
    );
  }

  // Upcoming Events Tab
  Widget _buildUpcomingEventsTab(ThemeProvider theme) {
    return RefreshIndicator(
      color: theme.primaryColor,
      onRefresh: () => _fetchEvents(refresh: true),
      child: ListView(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        children: [
          // Featured Banner Carousel
          const SizedBox(height: 16),

          FeaturedEventsCarousel(
            featuredEvents: _featuredEvents,
            pageController: _bannerController,
            currentPage: _currentBannerIndex,
            onPageChanged: (index) {
              setState(() => _currentBannerIndex = index);
            },
            onEventTap: (event) {
              Navigator.pushNamed(
                context,
                '/event-detail',
                arguments: {'event': event},
              );
            },
            primaryColor: theme.primaryColor,
            formatEventDate: (date) => DateHelpers.formatEventDate(date),
          ),

          const SizedBox(height: 16),

          // Filter Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildFilterButton(
                    'Date',
                    _selectedDate == 'anytime'
                        ? 'Anytime'
                        : _selectedDate == 'today'
                        ? 'Today'
                        : _selectedDate == 'tomorrow'
                        ? 'Tomorrow'
                        : _selectedDate == 'this-weekend'
                        ? 'This Weekend'
                        : 'Custom',
                    () => _showDateFilter(theme),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFilterButton(
                    'Category',
                    _selectedCategories.isEmpty
                        ? 'All'
                        : '${_selectedCategories.length} selected',
                    () => _showCategoryFilter(theme),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFilterButton(
                    'Location',
                    _selectedLocation == 'national'
                        ? 'National'
                        : _selectedLocation == 'near-me'
                        ? 'Near me'
                        : _selectedLocation == '50-miles'
                        ? '50 Miles'
                        : _selectedLocation == '100-miles'
                        ? '100 Miles'
                        : 'Custom',
                    () => _showLocationFilter(theme),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Event List
          if (_upcomingEvents.isEmpty && !_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No events found',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            )
          else
            ..._upcomingEvents.asMap().entries.map((entry) {
              final index = entry.key;
              final event = entry.value;
              return _buildEventCard(event, index, theme);
            }),

          // Loading indicator
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(
                  color: theme.primaryColor,
                  strokeWidth: 2.5,
                ),
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Filter Button Widget
  Widget _buildFilterButton(String label, String value, VoidCallback onTap) {
    return InkWell(
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
    );
  }

  // Event Card Widget
  Widget _buildEventCard(
    Map<String, dynamic> event,
    int index,
    ThemeProvider theme,
  ) {
    final isFavorite = event['is_liked'] ?? false;
    final eventId = event['id'].toString();

    return Container(
      // margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/event-detail',
            arguments: {'event': event},
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Event Image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 90,
                  height: 90,
                  color: Colors.grey.shade200,
                  child: event['thumbnail'] != null
                      ? Image.network(
                          event['thumbnail'],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade300,
                            child: Icon(
                              Icons.event,
                              color: Colors.grey.shade500,
                              size: 40,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.event,
                          color: Colors.grey.shade500,
                          size: 40,
                        ),
                ),
              ),

              const SizedBox(width: 12),

              // Event Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event['title'] ?? 'Untitled Event',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateHelpers.formatEventDate(event['start_date'] ?? ''),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryColor,
                      ),
                    ),
                    if (event['start_date'] != null &&
                        event['end_date'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        DateHelpers.formatEventTime(
                          event['start_date'],
                          event['end_date'],
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event['location'] ?? 'Location TBA',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Favorite Button
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? Colors.red : Colors.grey.shade400,
                ),
                onPressed: () => _toggleEventLike(eventId, index),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // My Events Tab
  Widget _buildMyEventsTab() {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    return MyEventsTabContent(
      myCreatedEvents: _myCreatedEvents,
      likedEvents: _likedEvents,
      primaryColor: theme.primaryColor,
      onRefresh: _fetchProfileEvents,
      onAddEvent: () {
        NavigationHelper.navigateTo(context, AddEventScreen());
      },
      onEventTap: (event) {
        Navigator.pushNamed(
          context,
          '/event-detail',
          arguments: {'event': event},
        );
      },
      formatEventDate: (date, index) => DateHelpers.formatEventDate(date),
      onUnlikeEvent: (eventId, site, eventIndex) async {
        final event = _likedEvents[eventIndex];

        // Optimistically remove
        setState(() {
          _likedEvents.removeAt(eventIndex);
        });

        // Make API call
        final success = await EventsAPI.toggleEventLike(
          eventId: eventId,
          site: site,
        );

        // Revert on failure
        if (!success && mounted) {
          setState(() {
            _likedEvents.insert(eventIndex, event);
          });
        }
      },
    );
  }

  // My Tickets Tab
  Widget _buildMyTicketsTab() {
    return MyTicketsTabContent(
      isLoading: _isLoadingTickets,
      errorMessage: _ticketsError,
      tickets: _activeTickets,
      onRefresh: () => _fetchUserTickets(),
      onViewTicket: (orderId) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OrderTicketsPage(orderId: orderId)),
        );
      },
      onAddToWallet: (ticket) {
        print('Add to wallet tapped for: ${ticket['event']['title']}');
        // Add your wallet logic here
      },
    );
  }
}
