import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The organiser's way in to the Events Manager.
///
/// Replaces an outlined "Hosting an event? [Add Event]" strip that offered
/// exactly one thing: the create wizard. Running events is more than
/// creating them — orders, applications, editing what is already live — and
/// all of that already exists on the dashboard, so this opens the manager
/// rather than a single form.
class EventsManagerBanner extends StatelessWidget {
  final VoidCallback onOpenManager;

  const EventsManagerBanner({Key? key, required this.onOpenManager})
    : super(key: key);

  static const Color _gold = Color(0xFFB8935E);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B0B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ORGANISERS',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: _gold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Host or manage events?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: _gold,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOpenManager,
                child: const SizedBox(
                  height: 54,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Load Events Manager',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Icon(Icons.chevron_right, size: 22, color: Colors.white),
                    ],
                  ),
                ),
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
      // margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        // borderRadius: BorderRadius.circular(12),
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
/// The My Events tab: the organiser's way in, then saved events.
///
/// It used to open with a list of the events the user had CREATED. That
/// list has gone: an organiser's own events are managed in the Events
/// Manager above, where the things you actually want to do to them live,
/// and showing them twice made the tab read as two half-lists rather than
/// one. What is left is the half nothing else shows — the ones they saved.
class MyEventsTabContent extends StatelessWidget {
  final List<Map<String, dynamic>> likedEvents;
  final VoidCallback onOpenManager;
  final Function(Map<String, dynamic>) onEventTap;
  final Function(String, int) formatEventDate;
  final Function(String eventId, String site, int eventIndex) onUnlikeEvent;
  final Future<void> Function() onRefresh;
  final Color primaryColor;

  const MyEventsTabContent({
    Key? key,
    required this.likedEvents,
    required this.onOpenManager,
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
          EventsManagerBanner(onOpenManager: onOpenManager),

          const SizedBox(height: 24),

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
                // Photos has gone from a SAVED event. Saving one is
                // an intention to go, not a record of having been —
                // offering to add photographs to something that has
                // not happened yet reads as a prompt to do something
                // impossible. It stays on the events above, which are
                // ones the user is involved in running.
                trailingWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.favorite,
                        color: Color(0xFFB8935E),
                      ),
                      onPressed: () => onUnlikeEvent(eventId, site, index),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
