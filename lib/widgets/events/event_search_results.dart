import 'package:flutter/material.dart';

/// Loading state for search
class SearchLoadingState extends StatelessWidget {
  final Color primaryColor;

  const SearchLoadingState({Key? key, required this.primaryColor})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2.5),
    );
  }
}

/// Empty state when no search results are found
class EmptySearchResultsState extends StatelessWidget {
  const EmptySearchResultsState({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
}

/// Search result event card
class SearchResultCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final String formattedDate;
  final String? formattedTime;
  final Color dateColor;
  final VoidCallback onTap;

  const SearchResultCard({
    Key? key,
    required this.event,
    required this.formattedDate,
    this.formattedTime,
    required this.dateColor,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
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
                      formattedDate,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: dateColor,
                      ),
                    ),
                    if (formattedTime != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        formattedTime!,
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
  }
}

/// Main search results content widget that handles all states
class SearchResultsContent extends StatelessWidget {
  final bool isSearching;
  final List<Map<String, dynamic>> searchResults;
  final Color primaryColor;
  final Function(Map<String, dynamic>) onEventTap;
  final String Function(String date) formatEventDate;
  final String? Function(String? startDate, String? endDate) formatEventTime;

  const SearchResultsContent({
    Key? key,
    required this.isSearching,
    required this.searchResults,
    required this.primaryColor,
    required this.onEventTap,
    required this.formatEventDate,
    required this.formatEventTime,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isSearching) {
      return SearchLoadingState(primaryColor: primaryColor);
    }

    if (searchResults.isEmpty) {
      return const EmptySearchResultsState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: searchResults.length,
      itemBuilder: (context, index) {
        final event = searchResults[index];

        final String? formattedTime =
            event['start_date'] != null && event['end_date'] != null
            ? formatEventTime(event['start_date'], event['end_date'])
            : null;

        return SearchResultCard(
          event: event,
          formattedDate: formatEventDate(event['start_date'] ?? ''),
          formattedTime: formattedTime,
          dateColor: primaryColor,
          onTap: () => onEventTap(event),
        );
      },
    );
  }
}
