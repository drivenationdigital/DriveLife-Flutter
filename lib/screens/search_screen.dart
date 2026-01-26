import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/utils/date.dart';
import 'package:drivelife/widgets/shared_header_actions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SearchResultsContent extends StatelessWidget {
  final bool isSearching;
  final Map<String, dynamic> searchResults;
  final String resultType; // 'events', 'users', 'venues', 'vehicles'
  final Color primaryColor;

  // Event callbacks
  final Function(Map<String, dynamic>)? onEventTap;
  final String Function(String?)? formatEventDate;
  final String? Function(String?, String?)? formatEventTime;

  // User callbacks
  final Function(Map<String, dynamic>)? onUserTap;

  // Venue callbacks
  final Function(Map<String, dynamic>)? onVenueTap;

  // Vehicle callbacks
  final Function(Map<String, dynamic>)? onVehicleTap;

  const SearchResultsContent({
    Key? key,
    required this.isSearching,
    required this.searchResults,
    required this.resultType,
    required this.primaryColor,
    this.onEventTap,
    this.formatEventDate,
    this.formatEventTime,
    this.onUserTap,
    this.onVenueTap,
    this.onVehicleTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isSearching) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
          ),
        ],
      );
    }

    // Get the appropriate data based on result type
    final data = _getResultData();
    print(
      'SearchResultsContent: resultType=$resultType, data=${data?.length} items',
    );

    if (data == null || data.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_getEmptyIcon(), size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No ${resultType} found',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: data.length,
      itemBuilder: (context, index) {
        final item = data[index];

        switch (resultType) {
          case 'events':
            return _buildEventCard(context, item);
          case 'users':
            return _buildUserCard(context, item);
          case 'venues':
            return _buildVenueCard(context, item);
          case 'vehicles':
            return _buildVehicleCard(context, item);
          default:
            return const SizedBox();
        }
      },
    );
  }

  List<Map<String, dynamic>>? _getResultData() {
    try {
      final typeData = searchResults[resultType];
      if (typeData == null) return null;

      // Check if it's a map with 'data' field (paginated response)
      if (typeData is Map<String, dynamic> && typeData.containsKey('data')) {
        return (typeData['data'] as List?)?.cast<Map<String, dynamic>>();
      }

      // Otherwise assume it's a direct list
      return (typeData as List?)?.cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error getting result data: $e');
      return null;
    }
  }

  IconData _getEmptyIcon() {
    switch (resultType) {
      case 'events':
        return Icons.event_busy;
      case 'users':
        return Icons.person_off;
      case 'venues':
        return Icons.location_off;
      case 'vehicles':
        return Icons.directions_car_outlined;
      default:
        return Icons.search_off;
    }
  }

  // ============================================================================
  // EVENT CARD
  // ============================================================================
  Widget _buildEventCard(BuildContext context, Map<String, dynamic> event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => onEventTap?.call(event),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            // Event image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: Image.network(
                event['thumbnail'] ?? '',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 100,
                    height: 100,
                    color: Colors.grey.shade300,
                    child: const Icon(
                      Icons.event,
                      size: 40,
                      color: Colors.grey,
                    ),
                  );
                },
              ),
            ),

            // Event details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (event['name'] ?? '').replaceAll('&amp;', '&'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Date
                    if (formatEventDate != null && event['start_date'] != null)
                      Text(
                        formatEventDate!(event['start_date']),
                        style: TextStyle(
                          fontSize: 13,
                          color: primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    const SizedBox(height: 4),

                    // Location
                    if (event['location'] != null)
                      Text(
                        event['location'] ?? 'TBA',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // USER CARD
  // ============================================================================
  Widget _buildUserCard(BuildContext context, Map<String, dynamic> user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => onUserTap?.call(user),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              // User avatar
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey.shade300,
                backgroundImage: (user['thumbnail'] ?? '').isNotEmpty
                    ? NetworkImage(user['thumbnail'])
                    : null,
                child: (user['thumbnail'] ?? '').isEmpty
                    ? Icon(Icons.person, color: Colors.grey.shade600, size: 32)
                    : null,
              ),
              const SizedBox(width: 12),

              // User details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${user['username'] ?? ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),

                    // Verified badge if applicable
                    if (user['user_verified'] == true) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.verified, size: 16, color: primaryColor),
                          const SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: TextStyle(
                              fontSize: 12,
                              color: primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Chevron
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // VENUE CARD
  // ============================================================================
  Widget _buildVenueCard(BuildContext context, Map<String, dynamic> venue) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => onVenueTap?.call(venue),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            // Venue image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: Image.network(
                venue['thumbnail'] ?? venue['logo'] ?? '',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 100,
                    height: 100,
                    color: Colors.grey.shade300,
                    child: const Icon(
                      Icons.place,
                      size: 40,
                      color: Colors.grey,
                    ),
                  );
                },
              ),
            ),

            // Venue details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Location
                    if (venue['venue_location'] != null)
                      Text(
                        venue['venue_location'] ?? 'TBA',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                    // Distance
                    if (venue['distance'] != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Approx. ${venue['distance'].toStringAsFixed(1)} miles away',
                            style: TextStyle(
                              fontSize: 12,
                              color: primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // VEHICLE CARD
  // ============================================================================
  Widget _buildVehicleCard(BuildContext context, Map<String, dynamic> vehicle) {
    // Extract vehicle make and model from meta
    final meta = vehicle['meta'] as Map<String, dynamic>?;
    final make = meta?['make'] ?? '';
    final model = meta?['model'] ?? '';
    final variant = meta?['variant'] ?? '';
    final colour = meta?['colour'] ?? '';

    // Owner name
    final ownerName = vehicle['name'] ?? '';

    // Build display text: "Owner's Make Model"
    final displayText = ownerName.isNotEmpty
        ? "$ownerName's $make $model"
        : '$make $model';

    // Get thumbnail URL - handle both full URLs and image IDs
    String thumbnailUrl = vehicle['thumbnail'] ?? '';
    if (thumbnailUrl.isNotEmpty && !thumbnailUrl.startsWith('http')) {
      // If it's an image ID, construct the URL
      thumbnailUrl =
          'https://imagedelivery.net/3UkXrQaSXZJl7XH5FuIHDg/$thumbnailUrl/public';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => onVehicleTap?.call(vehicle),
        child: Row(
          children: [
            // Vehicle thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 60,
                height: 60,
                color: Colors.grey.shade300,
                child: thumbnailUrl.isNotEmpty
                    ? Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.directions_car,
                            size: 30,
                            color: Colors.grey.shade600,
                          );
                        },
                      )
                    : Icon(
                        Icons.directions_car,
                        size: 30,
                        color: Colors.grey.shade600,
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // Vehicle details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (variant.isNotEmpty || colour.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      [variant, colour].where((s) => s.isNotEmpty).join(' • '),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Chevron
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  // Search state
  bool _isSearching = false;
  Map<String, dynamic> _searchResults = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _searchController.text = '';

    // Perform initial search
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performSearch(_searchController.text);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() => _isSearching = true);

    try {
      final results = await EventsAPI.discoverSearch(
        search: query,
        type: 'all', // Search all types
        page: 1,
        perPage: 20,
      );

      if (results != null && mounted) {
        if (results['success'] != true) {
          setState(() {
            _searchResults = {};
            _isSearching = false;
          });
          return;
        }

        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _searchResults = {};
            _isSearching = false;
          });
        }
      }
    } catch (e) {
      print('Error searching: $e');
      if (mounted) {
        setState(() {
          _searchResults = {};
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 96,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          SharedHeaderIcons.qrCodeIcon(),
          SharedHeaderIcons.notificationIcon(),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            _buildSearchBar(theme),

            // Tab Bar
            _buildTabBar(theme),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTopTab(theme),
                  _buildEventsTab(theme),
                  _buildVenuesTab(theme),
                  _buildUsersTab(theme),
                  _buildVehiclesTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeProvider theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _searchController,
        onSubmitted: (value) => _performSearch(value),
        decoration: InputDecoration(
          hintText: 'Search',
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey.shade500),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults = {};
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(ThemeProvider theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: theme.primaryColor,
        unselectedLabelColor: Colors.grey.shade700,
        indicatorColor: theme.primaryColor,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'Top'),
          Tab(text: 'Events'),
          Tab(text: 'Venues'),
          Tab(text: 'Users'),
          Tab(text: 'Vehicles'),
        ],
      ),
    );
  }

  Widget _buildTopTab(ThemeProvider theme) {
    if (_isSearching) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
              ),
            ),
          ),
        ],
      );
    }

    final topResults = _searchResults['top_results'] as Map<String, dynamic>?;
    if (topResults == null) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: Text(
                _searchController.text.isEmpty
                    ? 'Start typing to search'
                    : 'No results found',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // Events section
        if (topResults['events'] != null &&
            (topResults['events'] as List).isNotEmpty) ...[
          _buildSectionHeader('Events', () {
            _tabController.animateTo(1);
          }, theme),
          ...((topResults['events'] as List)
              .take(3)
              .map((event) => _buildEventCard(event, theme))),
          const SizedBox(height: 24),
        ],

        // Users section
        if (topResults['users'] != null &&
            (topResults['users'] as List).isNotEmpty) ...[
          _buildSectionHeader('Users', () {
            _tabController.animateTo(3);
          }, theme),
          ...((topResults['users'] as List)
              .take(3)
              .map((user) => _buildUserCard(user, theme))),
          const SizedBox(height: 24),
        ],

        // Venues section
        if (topResults['venues'] != null &&
            (topResults['venues'] as List).isNotEmpty) ...[
          _buildSectionHeader('Venues', () {
            _tabController.animateTo(2);
          }, theme),
          ...((topResults['venues'] as List).map(
            (venue) => _buildVenueCard(venue, theme),
          )),
        ],
      ],
    );
  }

  Widget _buildEventsTab(ThemeProvider theme) {
    return SearchResultsContent(
      isSearching: _isSearching,
      searchResults: _searchResults,
      resultType: 'events',
      primaryColor: theme.primaryColor,
      onEventTap: (event) {
        Navigator.pushNamed(
          context,
          '/event-detail',
          arguments: {'event': event},
        );
      },
      // formatEventDate: (date) {
      //   return DateHelpers.formatEventDate(date);
      // },
      formatEventTime: (startDate, endDate) {
        if (startDate == null || endDate == null) return null;
        return DateHelpers.formatEventTime(startDate, endDate);
      },
    );
  }

  Widget _buildVenuesTab(ThemeProvider theme) {
    return SearchResultsContent(
      isSearching: _isSearching,
      searchResults: _searchResults,
      resultType: 'venues',
      primaryColor: theme.primaryColor,
      onVenueTap: (venue) {
        Navigator.pushNamed(
          context,
          '/venue-detail',
          arguments: {'venueId': venue['id']},
        );
      },
    );
  }

  Widget _buildUsersTab(ThemeProvider theme) {
    return SearchResultsContent(
      isSearching: _isSearching,
      searchResults: _searchResults,
      resultType: 'users',
      primaryColor: theme.primaryColor,
      onUserTap: (user) {
        Navigator.pushNamed(
          context,
          '/view-profile',
          arguments: {'userId': user['id']},
        );
      },
    );
  }

  Widget _buildVehiclesTab(ThemeProvider theme) {
    return SearchResultsContent(
      isSearching: _isSearching,
      searchResults: _searchResults,
      resultType: 'vehicles',
      primaryColor: theme.primaryColor,
      onVehicleTap: (vehicle) {
        Navigator.pushNamed(
          context,
          '/vehicle-detail',
          arguments: {'garageId': vehicle['id']},
        );
      },
    );
  }

  Widget _buildSectionHeader(
    String title,
    VoidCallback onSeeAll,
    ThemeProvider theme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          TextButton(
            onPressed: onSeeAll,
            child: Text(
              'See all',
              style: TextStyle(
                color: theme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event, ThemeProvider theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: Image.network(
                event['thumbnail'] ?? '',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 100,
                    height: 100,
                    color: Colors.grey.shade300,
                    child: const Icon(
                      Icons.event,
                      size: 40,
                      color: Colors.grey,
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (event['name'] ?? '').replaceAll('&amp;', '&'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateHelpers.formatEventDate(event['start_date']),
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event['location'] ?? 'TBA',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                event['is_liked'] == true
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: event['is_liked'] == true
                    ? theme.primaryColor
                    : Colors.grey.shade400,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, ThemeProvider theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/view-profile',
            arguments: {'userId': user['id']},
          );
        },
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: (user['thumbnail'] ?? '').isNotEmpty
                  ? NetworkImage(user['thumbnail'])
                  : null,
              child: (user['thumbnail'] ?? '').isEmpty
                  ? Icon(Icons.person, color: Colors.grey.shade600, size: 28)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['name'] ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '@${user['username'] ?? ''}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueCard(Map<String, dynamic> venue, ThemeProvider theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/venue-detail',
            arguments: {'venueId': venue['id']},
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: Image.network(
                venue['thumbnail'] ?? '',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 100,
                    height: 100,
                    color: Colors.grey.shade300,
                    child: const Icon(
                      Icons.place,
                      size: 40,
                      color: Colors.grey,
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      venue['venue_location'] ?? 'TBA',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (venue['distance'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Approx. ${venue['distance'].toStringAsFixed(1)} miles away',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.primaryColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
