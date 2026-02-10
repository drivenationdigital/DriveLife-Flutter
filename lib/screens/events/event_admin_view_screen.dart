import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/events/add_event_screen.dart';
import 'package:drivelife/screens/events/order_ticket_view.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/widgets/shared_header_actions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

class EventAdminPage extends StatefulWidget {
  final String eventId;
  final String site;

  const EventAdminPage({Key? key, required this.eventId, required this.site})
    : super(key: key);

  @override
  State<EventAdminPage> createState() => _EventAdminPageState();
}

class _EventAdminPageState extends State<EventAdminPage> {
  Map<String, dynamic>? _eventData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEventData();
  }

  Future<void> _loadEventData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await EventsAPI.getProfileEventForOwner(
        eventId: widget.eventId,
        site: widget.site,
      );

      if (mounted) {
        setState(() {
          _eventData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleCancelEvent() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text('Cancel Event'),
        content: Text(
          'Are you sure you want to cancel this event? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No, Keep Event'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Yes, Cancel Event'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await EventsAPI.cancelEvent(
        eventId: widget.eventId,
        site: widget.site,
      );

      // Hide loading
      if (mounted) Navigator.pop(context);

      if (result != null &&
          (result['success'] == true || result['status'] == 'success')) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Event cancelled successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Refresh data or navigate back
        await _refreshData();
      } else {
        throw Exception(result?['message'] ?? 'Failed to cancel event');
      }
    } catch (e) {
      // Hide loading if still showing
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel event: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteEvent() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text('Delete Event'),
        content: Text(
          'Are you sure you want to permanently delete this event? '
          'This will remove all associated data and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await EventsAPI.deleteEvent(
        eventId: widget.eventId,
        site: widget.site,
      );

      // Hide loading
      if (mounted) Navigator.pop(context);

      if (result != null &&
          (result['success'] == true || result['status'] == 'success')) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Event deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate back to previous screen
        if (mounted) {
          Navigator.pop(context, true); // Return true to indicate deletion
        }
      } else {
        throw Exception(result?['message'] ?? 'Failed to delete event');
      }
    } catch (e) {
      // Hide loading if still showing
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete event: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _refreshData() async {
    try {
      final data = await EventsAPI.getProfileEventForOwner(
        eventId: widget.eventId,
        site: widget.site,
      );

      if (mounted) {
        setState(() {
          _eventData = data;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to refresh: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 96,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => {Navigator.pop(context)},
              icon: Icon(Icons.arrow_back_ios, color: Colors.black),
            ),
          ],
        ),
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.search);
            },
          ),
          // ✅ Using the actionIcons helper for multiple icons at once
          ...SharedHeaderIcons.actionIcons(
            iconColor: Colors.black,
            showQr: false, // Already shown in leading
            showNotifications: true,
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingSkeleton(theme)
          : _error != null
          ? _buildError()
          : RefreshIndicator(
              onRefresh: _refreshData,
              color: theme.primaryColor,
              child: _buildContent(theme),
            ),
    );
  }

  Widget _buildLoadingSkeleton(ThemeProvider theme) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event card skeleton
            Container(
              height: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            SizedBox(height: 20),
            // Sales summary skeleton
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            SizedBox(height: 20),
            // Ticket breakdown skeleton
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            SizedBox(height: 20),
            // Orders skeleton
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          SizedBox(height: 16),
          Text(
            'Failed to load event details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 8),
          Text(
            _error ?? 'Unknown error',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24),
          ElevatedButton(onPressed: _loadEventData, child: Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeProvider theme) {
    if (_eventData == null || !(_eventData!['success'] ?? false)) {
      return Center(child: Text('No event data available'));
    }

    final event = _eventData!['event'] as Map<String, dynamic>;
    final sales = _eventData!['sales'] as Map<String, dynamic>;

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEventCard(event, theme),
          SizedBox(height: 20),
          _buildSalesSummary(sales['sales'] as Map<String, dynamic>, theme),
          SizedBox(height: 20),
          _buildTicketBreakdown(sales['tickets'] as List<dynamic>, theme),
          SizedBox(height: 20),
          _buildOrders(sales['orders'] as List<dynamic>, theme),
          SizedBox(height: 100), // Bottom padding for navigation bar
        ],
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event, ThemeProvider theme) {
    final dates = event['dates'] as List<dynamic>;
    final firstDate = dates.isNotEmpty
        ? dates[0] as Map<String, dynamic>
        : null;

    String dateText = 'No date specified';
    if (firstDate != null) {
      try {
        final startDate = DateTime.parse(firstDate['start_date']);
        dateText = 'Starts ${DateFormat('EEE, d MMM yyyy').format(startDate)}';
      } catch (e) {
        dateText = firstDate['start_date'];
      }
    }

    final startTime = firstDate?['start_time'] ?? '00:00';
    final endTime = firstDate?['end_time'] ?? '00:00';
    final location = event['location'] ?? 'No location';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event['title'] ?? 'Untitled Event',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            _buildInfoRow(Icons.calendar_today, dateText),
            SizedBox(height: 12),
            _buildInfoRow(Icons.access_time, '$startTime - $endTime'),
            SizedBox(height: 12),
            _buildInfoRow(Icons.location_on, location),
            SizedBox(height: 16),
            InkWell(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/event-detail',
                  arguments: {'event': event},
                );
              },
              child: Row(
                children: [
                  Icon(Icons.link, color: theme.primaryColor, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Preview Event Listing',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            _buildActionButton('Edit Event', theme.primaryColor, () {
              NavigationHelper.navigateTo(
                context,
                AddEventScreen(eventId: event['id'].toString()),
              );
            }),
            SizedBox(height: 12),
            _buildActionButton('Cancel Event', theme.primaryColor, () {
              _handleCancelEvent();
            }),
            SizedBox(height: 12),
            TextButton(
              onPressed: () {
                _handleDeleteEvent();
              },
              child: Text(
                'Delete Event',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 15, color: Colors.grey[800]),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(String text, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildSalesSummary(Map<String, dynamic> sales, ThemeProvider theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sales Summary',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Total Orders',
                sales['total_orders'].toString(),
                theme,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Total Tickets',
                sales['total_tickets'].toString(),
                theme,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Value',
                '£${sales['net_sales'].toStringAsFixed(2)}',
                theme,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, ThemeProvider theme) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: theme.primaryColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketBreakdown(List<dynamic> tickets, ThemeProvider theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ticket Breakdown',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Table(
              columnWidths: {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(2),
              },
              children: [
                TableRow(
                  children: [
                    _buildTableHeader('Title'),
                    _buildTableHeader('Sold'),
                    _buildTableHeader('Status'),
                  ],
                ),
                ...tickets.map((ticket) {
                  return TableRow(
                    children: [
                      _buildTableCell(ticket['name'] ?? '-'),
                      _buildTableCell(ticket['sold']?.toString() ?? '0'),
                      _buildTableCell(ticket['status'] ?? '-'),
                    ],
                  );
                }).toList(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildTableCell(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, color: Colors.grey[800]),
      ),
    );
  }

  Widget _buildOrders(List<dynamic> orders, ThemeProvider theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Orders',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            ...orders.map((order) {
              return Container(
                margin: EdgeInsets.only(bottom: 16),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                order['email'] ?? '-',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Qty: ${order['quantity']} • £${order['total']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderTicketsPage(
                                  orderId: order['order_id'].toString(),
                                  admin: true,
                                ),
                              ),
                            );
                          },
                          child: Text(
                            'View',
                            style: TextStyle(color: theme.primaryColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
