import 'package:drivelife/screens/events/add_event_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';

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
  bool _isFavLoading = false;

  // NEW: Loading states
  bool _isLoadingEvent = true;
  Map<String, dynamic>? _fullEventData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _isFavorite = widget.event?['is_liked'] ?? false;
    _fetchEventDetails(); // NEW: Fetch full event data
  }

  @override
  void dispose() {
    _tabController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _fetchEventDetails() async {
    if (widget.event == null) {
      setState(() {
        _errorMessage = 'Event not found';
        _isLoadingEvent = false;
      });
      return;
    }

    final eventId = widget.event!['id']?.toString();
    final site = widget.event!['site'] ?? widget.event!['country'] ?? 'GB';

    if (eventId == null) {
      setState(() {
        _errorMessage = 'Invalid event ID';
        _isLoadingEvent = false;
      });
      return;
    }

    try {
      final eventData = await EventsAPI.getEvent(
        eventId: eventId,
        country: site,
      );

      if (eventData != null && mounted) {
        setState(() {
          _fullEventData = eventData;
          _isFavorite = eventData['is_liked'] ?? false;
          _isLoadingEvent = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load event details';
          _isLoadingEvent = false;
        });
      }
    } catch (e) {
      print('Error fetching event details: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading event';
          _isLoadingEvent = false;
        });
      }
    }
  }

  String _formatEventDate(Map<String, dynamic> event) {
    try {
      final dates = event['dates'] as List<dynamic>?;
      if (dates == null || dates.isEmpty) return 'Date TBA';

      final firstDate = dates[0];
      final startDate = DateTime.parse(firstDate['start_date']);
      final formatter = DateFormat('EEE, d MMM yy');
      return formatter.format(startDate);
    } catch (e) {
      return 'Date TBA';
    }
  }

  String _formatEventTime(Map<String, dynamic> event) {
    try {
      final dates = event['dates'] as List<dynamic>?;
      if (dates == null || dates.isEmpty) return 'Time TBA';

      final firstDate = dates[0];
      if (firstDate['exclude_time'] == true) return 'All Day';

      final startTime = firstDate['start_time'] ?? '';
      final endTime = firstDate['end_time'] ?? '';

      if (startTime.isEmpty) return 'Time TBA';

      // Convert 24h to 12h format
      final startParts = startTime.split(':');
      final endParts = endTime.split(':');

      final startHour = int.parse(startParts[0]);
      final endHour = endParts.isNotEmpty ? int.parse(endParts[0]) : startHour;

      final startPeriod = startHour >= 12 ? 'PM' : 'AM';
      final endPeriod = endHour >= 12 ? 'PM' : 'AM';

      final start12h = startHour > 12
          ? startHour - 12
          : (startHour == 0 ? 12 : startHour);
      final end12h = endHour > 12
          ? endHour - 12
          : (endHour == 0 ? 12 : endHour);

      return endTime.isNotEmpty
          ? '$start12h$startPeriod - $end12h$endPeriod'
          : '$start12h$startPeriod';
    } catch (e) {
      return 'Time TBA';
    }
  }

  List<String> _getEventImages(Map<String, dynamic> event) {
    final images = <String>[];

    // Add cover photo first
    final coverPhoto = event['cover_photo'];
    if (coverPhoto != null && coverPhoto['url'] != null) {
      images.add(coverPhoto['url']);
    }

    // Add gallery images
    final gallery = event['gallery'] as List<dynamic>?;
    if (gallery != null) {
      for (var item in gallery) {
        if (item['url'] != null) {
          images.add(item['url']);
        }
      }
    }

    return images;
  }

  String _stripHtml(String? html) {
    if (html == null || html.isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }

  Future<void> _toggleFavorite() async {
    setState(() {
      _isFavLoading = true;
      _isFavorite = !_isFavorite;
    });

    final eventId =
        _fullEventData?['id']?.toString() ?? widget.event?['id']?.toString();
    final site = _fullEventData?['country'] ?? widget.event?['country'] ?? 'gb';

    if (eventId == null) {
      setState(() => _isFavLoading = false);
      return;
    }

    final success = await EventsAPI.toggleEventLike(
      eventId: eventId,
      site: site,
    );

    if (!success && mounted) {
      setState(() {
        _isFavorite = !_isFavorite;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update favorite'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => _isFavLoading = false);
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image skeleton
          Container(
            height: 300,
            color: Colors.grey.shade200,
            child: Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title skeleton
                Container(
                  width: double.infinity,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 200,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 24),

                // Date skeleton
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 150,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Time skeleton
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 120,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Location skeleton
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 180,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Button skeletons
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tab bar skeleton
          const SizedBox(height: 20),
          Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content skeleton
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(
                5,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Failed to load event',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoadingEvent = true;
                  _errorMessage = null;
                });
                _fetchEventDetails();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventContent(ThemeProvider theme) {
    final event = _fullEventData!; // Use full event data

    final eventImages = _getEventImages(event);
    final eventTitle = event['title'] ?? 'Untitled Event';
    final eventDate = _formatEventDate(event);
    final eventTime = _formatEventTime(event);
    final eventLocation = event['location'] ?? 'Location TBA';
    final eventDescription = _stripHtml(event['description']);
    final entryDetails = _stripHtml(event['entry_details']);
    final hasTickets = event['has_tickets'] == true;
    final ticketUrl = event['ticket_url'];
    final registrationRequired = event?['registrationRequired'] == true;
    final eventUrl = event['url'] ?? '';
    final isEventOwner = event['is_owner'] == true;

    Widget buildHtmlContent(String? htmlContent, String emptyMessage) {
      final theme = Provider.of<ThemeProvider>(context, listen: false);

      if (htmlContent == null || htmlContent.isEmpty) {
        return Text(
          emptyMessage,
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade700,
            height: 1.6,
          ),
        );
      }

      return Html(
        data: htmlContent,
        // style: {
        //   "body": Style(
        //     fontSize: FontSize(15),
        //     color: Colors.grey.shade700,
        //     lineHeight: const LineHeight(1.6),
        //     margin: Margins.zero,
        //     padding: HtmlPaddings.zero,
        //   ),
        //   "p": Style(margin: Margins.only(bottom: 12)),
        //   "h1": Style(
        //     fontSize: FontSize(20),
        //     fontWeight: FontWeight.w700,
        //     color: Colors.black,
        //     margin: Margins.only(top: 16, bottom: 12),
        //   ),
        //   "h2": Style(
        //     fontSize: FontSize(18),
        //     fontWeight: FontWeight.w700,
        //     color: Colors.black,
        //     margin: Margins.only(top: 14, bottom: 10),
        //   ),
        //   "h3": Style(
        //     fontSize: FontSize(16),
        //     fontWeight: FontWeight.w600,
        //     color: Colors.black,
        //     margin: Margins.only(top: 12, bottom: 8),
        //   ),
        //   "ul": Style(
        //     padding: HtmlPaddings.only(left: 20),
        //     margin: Margins.only(bottom: 12),
        //   ),
        //   "ol": Style(
        //     padding: HtmlPaddings.only(left: 20),
        //     margin: Margins.only(bottom: 12),
        //   ),
        //   "li": Style(margin: Margins.only(bottom: 8)),
        //   "a": Style(
        //     color: theme.primaryColor,
        //     textDecoration: TextDecoration.underline,
        //   ),
        //   "strong, b": Style(fontWeight: FontWeight.w700),
        //   "em, i": Style(fontStyle: FontStyle.italic),
        //   "div": Style(margin: Margins.only(bottom: 12)),
        // },
        onLinkTap: (url, attributes, element) async {
          if (url != null) {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Carousel
          SizedBox(
            height: 300,
            child: eventImages.isEmpty
                ? Container(
                    color: Colors.grey.shade300,
                    child: Icon(
                      Icons.event,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                  )
                : Stack(
                    children: [
                      PageView.builder(
                        controller: _imageController,
                        onPageChanged: (index) {
                          setState(() => _currentImageIndex = index);
                        },
                        itemCount: eventImages.length,
                        itemBuilder: (context, index) {
                          return Container(
                            color: Colors.grey.shade300,
                            child: Image.network(
                              eventImages[index],
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
                      if (eventImages.length > 1)
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              eventImages.length,
                              (index) => Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
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
                  eventTitle,
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
                      eventDate,
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
                      eventTime,
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
                        eventLocation,
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
                const SizedBox(height: 12),

                if (registrationRequired)
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

                // edit event button
                if (isEventOwner)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        NavigationHelper.navigateTo(
                          context,
                          AddEventScreen(eventId: event['id'].toString()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.edit),
                      label: const Text(
                        'Edit Event',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                // Action Buttons
                if (hasTickets && ticketUrl != null && ticketUrl.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        // Open ticket URL
                        final uri = Uri.parse(ticketUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
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

                if (hasTickets) const SizedBox(height: 12),

                // Favorite and Share Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isFavLoading ? null : _toggleFavorite,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: _isFavLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
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
                          final shareText =
                              'Check out this event: $eventTitle\n$eventLocation\n$eventDate at $eventTime\n$eventUrl';
                          await Share.share(shareText, subject: eventTitle);
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
                  child: buildHtmlContent(
                    eventDescription,
                    'No description available.',
                  ),
                ),

                // Entry & Tickets Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: buildHtmlContent(
                    entryDetails,
                    hasTickets
                        ? 'Tickets are available for this event.'
                        : 'This is a free event. No tickets required.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

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
      body: _isLoadingEvent
          ? _buildSkeleton()
          : _errorMessage != null
          ? _buildErrorState()
          : _buildEventContent(theme),
    );
  }
}
