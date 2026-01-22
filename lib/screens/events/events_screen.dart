import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/theme_provider.dart';

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
  int _currentBannerIndex = 0;

  String? _selectedDate;
  String? _selectedCategory;
  String? _selectedLocation;

  final Set<int> _favoriteEvents = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bannerController.dispose();
    super.dispose();
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
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
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
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              isScrollable: false,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Upcoming',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.favorite_border, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'My Events',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.confirmation_number_outlined, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text('Tickets', overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: TabBarView(
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
    return ListView(
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _buildFilterDropdown(
                  'Date',
                  _selectedDate,
                  ['Today', 'This Week', 'This Month', 'All'],
                  (value) => setState(() => _selectedDate = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterDropdown(
                  'Category',
                  _selectedCategory,
                  ['Motorsport', 'Car Show', 'Track Day', 'Meet'],
                  (value) => setState(() => _selectedCategory = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterDropdown(
                  'Location',
                  _selectedLocation,
                  ['Nearby', 'UK', 'Europe', 'All'],
                  (value) => setState(() => _selectedLocation = value),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Event List
        ..._buildEventsList(),
      ],
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

  Widget _buildFilterDropdown(
    String label,
    String? value,
    List<String> items,
    Function(String?) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item, style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  List<Widget> _buildEventsList() {
    final events = [
      {
        'id': 1,
        'title': 'Power Maxed MotoFest Coventry',
        'date': 'Sat, 24th Jan 26',
        'time': '10AM - 4PM',
        'location': 'The Motorist, New Lennerton Ln, Leeds LS25 6JE',
        'images': [
          'https://via.placeholder.com/800x400/333333/ffffff?text=Event+Image+1',
          'https://via.placeholder.com/800x400/444444/ffffff?text=Event+Image+2',
          'https://via.placeholder.com/800x400/555555/ffffff?text=Event+Image+3',
        ],
        'description':
            'Japanese cars have one of the largest cult followings amongst petrolheads, and for good reason! Their performance straight out of the factory, matched with a massive modification community has led to them becoming a fan favourite across the globe. Here at The Motorist our Japanese meets are easily some of our most popular events, with hundreds of cars on display each time.',
        'ticketsAvailable': true,
        'registrationRequired': true,
      },
      {
        'id': 2,
        'title': 'Power Maxed MotoFest Coventry',
        'date': 'Sat, 24th Jan 26',
        'time': '10AM - 4PM',
        'location': 'The Motorist, New Lennerton Ln, Leeds LS25 6JE',
        'images': [
          'https://via.placeholder.com/800x400/333333/ffffff?text=Event+Image+1',
          'https://via.placeholder.com/800x400/444444/ffffff?text=Event+Image+2',
          'https://via.placeholder.com/800x400/555555/ffffff?text=Event+Image+3',
        ],
        'description':
            'Japanese cars have one of the largest cult followings amongst petrolheads, and for good reason! Their performance straight out of the factory, matched with a massive modification community has led to them becoming a fan favourite across the globe. Here at The Motorist our Japanese meets are easily some of our most popular events, with hundreds of cars on display each time.',
        'ticketsAvailable': true,
        'registrationRequired': true,
      },
      {
        'id': 3,
        'title': 'Power Maxed MotoFest Coventry',
        'date': 'Sat, 24th Jan 26',
        'time': '10AM - 4PM',
        'location': 'The Motorist, New Lennerton Ln, Leeds LS25 6JE',
        'images': [
          'https://via.placeholder.com/800x400/333333/ffffff?text=Event+Image+1',
          'https://via.placeholder.com/800x400/444444/ffffff?text=Event+Image+2',
          'https://via.placeholder.com/800x400/555555/ffffff?text=Event+Image+3',
        ],
        'description':
            'Japanese cars have one of the largest cult followings amongst petrolheads, and for good reason! Their performance straight out of the factory, matched with a massive modification community has led to them becoming a fan favourite across the globe. Here at The Motorist our Japanese meets are easily some of our most popular events, with hundreds of cars on display each time.',
        'ticketsAvailable': true,
        'registrationRequired': true,
      },
      {
        'id': 4,
        'title': 'Power Maxed MotoFest Coventry',
        'date': 'Sat, 24th Jan 26',
        'time': '10AM - 4PM',
        'location': 'The Motorist, New Lennerton Ln, Leeds LS25 6JE',
        'images': [
          'https://via.placeholder.com/800x400/333333/ffffff?text=Event+Image+1',
          'https://via.placeholder.com/800x400/444444/ffffff?text=Event+Image+2',
          'https://via.placeholder.com/800x400/555555/ffffff?text=Event+Image+3',
        ],
        'description':
            'Japanese cars have one of the largest cult followings amongst petrolheads, and for good reason! Their performance straight out of the factory, matched with a massive modification community has led to them becoming a fan favourite across the globe. Here at The Motorist our Japanese meets are easily some of our most popular events, with hundreds of cars on display each time.',
        'ticketsAvailable': true,
        'registrationRequired': true,
      },
    ];

    return events.map((event) => _buildEventCard(event)).toList();
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final isFavorite = _favoriteEvents.contains(event['id']);
    final theme = Provider.of<ThemeProvider>(context, listen: false);

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
                  child: Image.network(
                    event['images'][0],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade300,
                      child: Icon(
                        Icons.event,
                        color: Colors.grey.shade500,
                        size: 40,
                      ),
                    ),
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
                      event['title'],
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
                      event['date'],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryColor,
                      ),
                    ),
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
                            event['location'],
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
                onPressed: () {
                  setState(() {
                    if (isFavorite) {
                      _favoriteEvents.remove(event['id']);
                    } else {
                      _favoriteEvents.add(event['id']);
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyEventsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 80, color: Colors.grey.shade300),
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
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
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
