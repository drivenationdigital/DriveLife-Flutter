import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Banner prompting users to add their own event
class AddEventBanner extends StatelessWidget {
  final VoidCallback onAddEvent;

  const AddEventBanner({Key? key, required this.onAddEvent}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
            onPressed: onAddEvent,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Event'),
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
}

/// Reusable event card widget
class EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final String formattedDate;
  final Color dateColor;
  final VoidCallback onTap;
  final Widget? trailingWidget;

  const EventCard({
    Key? key,
    required this.event,
    required this.formattedDate,
    required this.dateColor,
    required this.onTap,
    this.trailingWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
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
                      formattedDate,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: dateColor,
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

              // Optional trailing widget (like button, etc)
              if (trailingWidget != null) trailingWidget!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state for saved events
class EmptySavedEventsState extends StatelessWidget {
  const EmptySavedEventsState({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
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
      ),
    );
  }
}

/// Section header widget
class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.black,
      ),
    );
  }
}

/// Main events tab content widget
class MyEventsTabContent extends StatelessWidget {
  final List<Map<String, dynamic>> myCreatedEvents;
  final List<Map<String, dynamic>> likedEvents;
  final VoidCallback onAddEvent;
  final Function(Map<String, dynamic>) onEventTap;
  final Function(String, int) formatEventDate;
  final Function(String eventId, String site, int eventIndex) onUnlikeEvent;
  final Future<void> Function() onRefresh;
  final Color primaryColor;

  const MyEventsTabContent({
    Key? key,
    required this.myCreatedEvents,
    required this.likedEvents,
    required this.onAddEvent,
    required this.onEventTap,
    required this.formatEventDate,
    required this.onUnlikeEvent,
    required this.onRefresh,
    required this.primaryColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: theme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Add Event Banner
          AddEventBanner(onAddEvent: onAddEvent),

          const SizedBox(height: 24),

          // My Events Section
          if (myCreatedEvents.isNotEmpty) ...[
            const SectionHeader(title: 'My Events'),
            const SizedBox(height: 12),
            ...myCreatedEvents.map((event) {
              return EventCard(
                event: event,
                formattedDate: formatEventDate(event['start_date'] ?? '', 0),
                dateColor: primaryColor,
                onTap: () => onEventTap(event),
              );
            }),
            const SizedBox(height: 24),
          ],

          // Saved Events Section
          const SectionHeader(title: 'Saved Events'),
          const SizedBox(height: 12),

          if (likedEvents.isEmpty)
            const EmptySavedEventsState()
          else
            ...likedEvents.asMap().entries.map((entry) {
              final index = entry.key;
              final event = entry.value;
              final eventId = event['id'].toString();
              final site = event['country'] ?? 'gb';

              return EventCard(
                event: event,
                formattedDate: formatEventDate(
                  event['start_date'] ?? '',
                  index,
                ),
                dateColor: primaryColor,
                onTap: () => onEventTap(event),
                trailingWidget: IconButton(
                  icon: const Icon(Icons.favorite, color: Color(0xFFB8935E)),
                  onPressed: () => onUnlikeEvent(eventId, site, index),
                ),
              );
            }),
        ],
      ),
    );
  }
}
