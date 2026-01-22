import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/add_event_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/widgets/filter_bottom_sheet.dart';
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
  List<Map<String, dynamic>> _likedEvents = [];
  List<Map<String, dynamic>> _myCreatedEvents = [];
  List<Map<String, dynamic>> _categories = [];

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
      _fetchCategories();
      _fetchEvents(refresh: true);
    });

    _tabController.addListener(() {
      if (_tabController.index == 1) {
        // My Events tab
        _fetchProfileEvents();
      }
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

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchResults.clear();
    });
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

  Future<void> _fetchProfileEvents() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;

      if (user == null) return;

      final response = await EventsAPI.getProfileEvents(
        userId: user['id'].toString(),
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

  Future<void> _toggleEventLike(String eventId, int index) async {
    final event = _upcomingEvents[index];
    final site = event['site'] ?? 'GB';

    // Optimistic update
    setState(() {
      _upcomingEvents[index]['is_liked'] = !_upcomingEvents[index]['is_liked'];
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

  void _onFilterChanged() {
    _fetchEvents(refresh: true);
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
        // This is called when user selects a place
        print('📍 Place selected: ${prediction.description}');
        print('📍 Lat: ${prediction.lat}, Lng: ${prediction.lng}');

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
    print('Showing category filter with categories: $_categories');
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

  String _formatEventDate(String dateStr) {
    try {
      // Parse "01/26/2026 18:00" format
      final parts = dateStr.split(' ');
      if (parts.isEmpty) return dateStr;

      final datePart = parts[0].split('/');
      if (datePart.length != 3) return dateStr;

      final month = int.parse(datePart[0]);
      final day = int.parse(datePart[1]);
      final year = int.parse(datePart[2]);

      final date = DateTime(year, month, day);
      final formatter = DateFormat('EEE, d MMM yy');

      return formatter.format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String _formatEventTime(String startDate, String endDate) {
    try {
      final startParts = startDate.split(' ');
      final endParts = endDate.split(' ');

      if (startParts.length < 2 || endParts.length < 2) return '';

      final startTime = startParts[1];
      final endTime = endParts[1];

      // Convert 24h to 12h format
      final startHour = int.parse(startTime.split(':')[0]);
      final endHour = int.parse(endTime.split(':')[0]);

      final startPeriod = startHour >= 12 ? 'PM' : 'AM';
      final endPeriod = endHour >= 12 ? 'PM' : 'AM';

      final start12h = startHour > 12
          ? startHour - 12
          : (startHour == 0 ? 12 : startHour);
      final end12h = endHour > 12
          ? endHour - 12
          : (endHour == 0 ? 12 : endHour);

      return '$start12h$startPeriod - $end12h$endPeriod';
    } catch (e) {
      return '';
    }
  }

  Widget _buildSearchResults(ThemeProvider theme) {
    if (_isSearching) {
      return Center(
        child: CircularProgressIndicator(
          color: theme.primaryColor,
          strokeWidth: 2.5,
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No events found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final event = _searchResults[index];
        return Container(
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
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
                          event['name'] ?? 'Untitled Event',
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
                          _formatEventDate(event['start_date'] ?? ''),
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
                            _formatEventTime(
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
                ],
              ),
            ),
          ),
        );
      },
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
          SizedBox(
            height: 220,
            child: Stack(
              children: [
                PageView(
                  controller: _bannerController,
                  onPageChanged: (index) {
                    setState(() => _currentBannerIndex = index);
                  },
                  children: [
                    _buildBannerCard(
                      'JAPFEST',
                      '19TH APRIL 2026',
                      'SILVERSTONE',
                      'https://via.placeholder.com/800x400/dc143c/ffffff?text=JAPFEST',
                    ),
                    _buildBannerCard(
                      'EURO FEST',
                      '25TH MAY 2026',
                      'BRANDS HATCH',
                      'https://via.placeholder.com/800x400/1e90ff/ffffff?text=EUROFEST',
                    ),
                    _buildBannerCard(
                      'CLASSICS',
                      '12TH JUNE 2026',
                      'GOODWOOD',
                      'https://via.placeholder.com/800x400/228b22/ffffff?text=CLASSICS',
                    ),
                  ],
                ),
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentBannerIndex == index
                              ? theme.primaryColor
                              : Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Filter Row
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

  Widget _buildBannerCard(
    String title,
    String date,
    String location,
    String imageUrl,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: Colors.grey.shade800),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 8,
                          offset: Offset(2, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    date,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    location,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(
    Map<String, dynamic> event,
    int index,
    ThemeProvider theme,
  ) {
    final isFavorite = event['is_liked'] ?? false;
    final eventId = event['id'].toString();

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
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
                      _formatEventDate(event['start_date'] ?? ''),
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
                        _formatEventTime(
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

  Widget _buildMyEventsTab() {
    return RefreshIndicator(
      onRefresh: _fetchProfileEvents,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Add Event Banner
          Container(
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
                  onPressed: () {
                    NavigationHelper.navigateTo(context, AddEventScreen());
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Event'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB8935E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // My Events Section
          if (_myCreatedEvents.isNotEmpty) ...[
            const Text(
              'My Events',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            ..._myCreatedEvents.map((event) => _buildMyEventCard(event)),
            const SizedBox(height: 24),
          ],

          // Saved Events Section
          const Text(
            'Saved Events',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),

          if (_likedEvents.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.favorite_border,
                      size: 80,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No saved events yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Events you save will appear here',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._likedEvents.map((event) => _buildSavedEventCard(event)),
        ],
      ),
    );
  }

  Widget _buildMyEventCard(Map<String, dynamic> event) {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                  width: 80,
                  height: 80,
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
                    const SizedBox(height: 6),
                    Text(
                      _formatEventDate(event['start_date'] ?? ''),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
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
                              fontSize: 12,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavedEventCard(Map<String, dynamic> event) {
    final theme = Provider.of<ThemeProvider>(context, listen: false);
    final eventId = event['id'].toString();
    final eventIndex = _likedEvents.indexOf(event);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                  width: 80,
                  height: 80,
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
                    const SizedBox(height: 6),
                    Text(
                      _formatEventDate(event['start_date'] ?? ''),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
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
                              fontSize: 12,
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

              // Like button
              IconButton(
                icon: const Icon(Icons.favorite, color: Color(0xFFB8935E)),
                onPressed: () async {
                  // Unlike the event
                  final site = event['country'] ?? 'gb';
                  setState(() {
                    _likedEvents.removeAt(eventIndex);
                  });

                  final success = await EventsAPI.toggleEventLike(
                    eventId: eventId,
                    site: site,
                  );

                  if (!success && mounted) {
                    // Revert on failure
                    setState(() {
                      _likedEvents.insert(eventIndex, event);
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyTicketsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.confirmation_number_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No tickets yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your purchased tickets will appear here',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
