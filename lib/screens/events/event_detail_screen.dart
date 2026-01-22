import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:share_plus/share_plus.dart';

class EventDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? event;

  const EventDetailScreen({super.key, this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PageController _imageController = PageController();
  int _currentImageIndex = 0;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    // Dummy event data (replace with actual data)
    final event =
        widget.event ??
        {
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
        };
    print(widget.event);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Image.asset('assets/logo-dark.png', height: 18),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Carousel
            SizedBox(
              height: 300,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _imageController,
                    onPageChanged: (index) {
                      setState(() => _currentImageIndex = index);
                    },
                    itemCount: event['images'].length,
                    itemBuilder: (context, index) {
                      return Container(
                        color: Colors.grey.shade300,
                        child: Image.network(
                          event['images'][index],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade300,
                            child: Icon(
                              Icons.event,
                              size: 80,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        event['images'].length,
                        (index) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentImageIndex == index
                                ? theme.primaryColor
                                : Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Event Details Section
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event Title
                  Text(
                    event['title'],
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Date
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 20,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        event['date'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Time
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 20,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        event['time'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Location
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 20,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          event['location'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  if (event['ticketsAvailable'])
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Buy tickets action
                          print('Buy Tickets');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade900,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.confirmation_number),
                        label: const Text(
                          'Buy Tickets',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  if (event['registrationRequired'])
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Register action
                          print('Register Now');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade900,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.person_add),
                        label: const Text(
                          'Register Now',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Favorite and Share Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() => _isFavorite = !_isFavorite);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: Icon(
                            _isFavorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                          ),
                          label: const Text(
                            'Favourite',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await Share.share(
                              'Check out this event: ${event['title']}\n${event['location']}',
                              subject: event['title'],
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.share),
                          label: const Text(
                            'Share',
                            style: TextStyle(
                              fontSize: 15,
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
                  fontSize: 16,
                ),
                tabs: const [
                  Tab(text: 'About Us'),
                  Tab(text: 'Entry & Tickets'),
                ],
              ),
            ),

            // Tab Content
            SizedBox(
              height: 300,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // About Us Tab
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      event['description'],
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade700,
                        height: 1.6,
                      ),
                    ),
                  ),

                  // Entry & Tickets Tab
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ticket Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTicketInfo(
                          'General Admission',
                          '£15.00',
                          'Access to all areas',
                        ),
                        const SizedBox(height: 12),
                        _buildTicketInfo(
                          'VIP Pass',
                          '£35.00',
                          'Includes priority entry and VIP lounge access',
                        ),
                        const SizedBox(height: 12),
                        _buildTicketInfo(
                          'Family Pass (4 people)',
                          '£50.00',
                          'Best value for families',
                        ),
                      ],
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

  Widget _buildTicketInfo(String name, String price, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              Text(
                price,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFAE9159),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
