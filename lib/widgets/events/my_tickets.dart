import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/utils/date.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Reusable ticket card widget
class TicketCard extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final int quantity;
  final String dateText;
  final VoidCallback onView;
  final VoidCallback onAddToWallet;
  final String eventLocation; // Placeholder for event location

  const TicketCard({
    Key? key,
    required this.title,
    this.imageUrl,
    required this.quantity,
    required this.dateText,
    required this.onView,
    required this.onAddToWallet,
    required this.eventLocation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image on the left
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            child: imageUrl != null && imageUrl!.isNotEmpty
                ? Image.network(
                    imageUrl!,
                    width: 110,
                    height: 180,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 110,
                    height: 180,
                    color: Colors.grey.shade300,
                    child: Icon(
                      Icons.confirmation_number_outlined,
                      color: Colors.grey.shade500,
                      size: 40,
                    ),
                  ),
          ),

          // All content on the right
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ticket info
                  Text(
                    '$quantity x tickets',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateText,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    eventLocation,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 12),

                  // Buttons
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onView,
                      icon: const Icon(Icons.qr_code_2, size: 18),
                      label: const Text('View'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onAddToWallet,
                      icon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 18,
                      ),
                      label: const Text('Add to Wallet'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state widget for when there are no tickets
class EmptyTicketsState extends StatelessWidget {
  const EmptyTicketsState({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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

/// Main tab content widget that handles loading, error, and ticket display
class MyTicketsTabContent extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;
  final List<Map<String, dynamic>> tickets;
  final Function(String orderId) onViewTicket;
  final Function(Map<String, dynamic> ticket) onAddToWallet;
  final Future<void> Function() onRefresh;

  const MyTicketsTabContent({
    Key? key,
    required this.isLoading,
    this.errorMessage,
    required this.tickets,
    required this.onViewTicket,
    required this.onAddToWallet,
    required this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (isLoading) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: theme.primaryColor,
        child: Stack(
          children: [
            ListView(), // Required for RefreshIndicator to work
            Center(child: CircularProgressIndicator(color: theme.primaryColor)),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: theme.primaryColor,
        child: Stack(
          children: [
            ListView(), // Required for RefreshIndicator to work
            Center(
              child: Text(
                errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }

    if (tickets.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: theme.primaryColor,
        child: Stack(
          children: [
            ListView(), // Required for RefreshIndicator to work
            const EmptyTicketsState(),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: theme.primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: tickets.length,
        itemBuilder: (context, index) {
          final ticket = tickets[index];

          final event = ticket['event'] ?? {};
          final dates = ticket['dates'] ?? {};
          final ticketData = ticket['ticket'] ?? {};

          final title = event['title'] ?? 'Event';
          final imageUrl = event['image_url'];
          final quantity = ticketData['quantity'] ?? 0;

          final startDate = dates['start_date'];
          final startTime = dates['start_time'] ?? '';
          final isSingleDay = dates['is_single_day'] == true;

          return TicketCard(
            title: title,
            imageUrl: imageUrl,
            quantity: quantity,
            dateText: DateHelpers.formatDate(startDate, startTime, isSingleDay),
            onView: () => onViewTicket(event['id']),
            onAddToWallet: () => onAddToWallet(ticket),
            eventLocation: event['location'] ?? 'Event Location',
          );
        },
      ),
    );
  }
}
