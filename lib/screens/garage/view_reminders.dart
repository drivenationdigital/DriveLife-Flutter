import 'package:drivelife/api/garage_reminders_service.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/garage/add_reminders.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

class RemindersScreen extends StatefulWidget {
  final String garageId;

  const RemindersScreen({Key? key, required this.garageId}) : super(key: key);

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Map<String, dynamic>> _reminders = [];
  bool _loading = true;
  String? _error;

  // Add to state variables
  PermissionStatus? _notificationStatus;

  @override
  void initState() {
    super.initState();
    _loadReminders();
    _checkNotificationPermission();
  }

  Future<void> _loadReminders() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;

      if (user == null) throw Exception('User not logged in');

      final reminders = await ReminderApiService.fetchReminders(
        widget.garageId,
      );

      if (!mounted) return;
      setState(() => _reminders = reminders);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkNotificationPermission() async {
    final status = await Permission.notification.status;
    if (!mounted) return;
    setState(() => _notificationStatus = status);
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    if (!mounted) return;
    setState(() => _notificationStatus = status);

    // If permanently denied, send them to app settings
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Widget _buildNotificationBanner() {
    final isDenied =
        _notificationStatus == PermissionStatus.denied ||
        _notificationStatus == PermissionStatus.permanentlyDenied;
    final isNotDetermined =
        _notificationStatus == PermissionStatus.provisional ||
        _notificationStatus == null;

    if (_notificationStatus == PermissionStatus.granted)
      return const SizedBox.shrink();

    final isPermanent =
        _notificationStatus == PermissionStatus.permanentlyDenied;

    return GestureDetector(
      onTap: _requestNotificationPermission,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Color(0xFFFFF8EC),
          border: Border(
            bottom: BorderSide(color: Color(0xFFFFE0A0), width: 1),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.notifications_off_outlined,
              size: 20,
              color: Color(0xFFB86A00),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isPermanent
                    ? 'Notifications are blocked. Tap to open settings and enable them.'
                    : 'Allow notifications to get reminded before important dates.',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFB86A00),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFB86A00),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isPermanent ? 'Settings' : 'Enable',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How many days until (or since) the reminder date
  int _daysUntil(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return 0;
    return date.difference(DateTime.now()).inDays;
  }

  String _formatDate(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Color _statusColor(int daysUntil) {
    if (daysUntil < 0) return Colors.red; // overdue
    if (daysUntil <= 14) return Colors.orange; // due soon
    return Colors.green; // upcoming
  }

  String _statusLabel(int daysUntil) {
    if (daysUntil < 0) return 'Overdue by ${daysUntil.abs()} days';
    if (daysUntil == 0) return 'Due today';
    if (daysUntil == 1) return 'Due tomorrow';
    if (daysUntil <= 14) return 'Due in $daysUntil days';
    return 'Upcoming';
  }

  IconData _typeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'mot':
        return Icons.fact_check_outlined;
      case 'service':
        return Icons.build_outlined;
      case 'insurance renewal':
        return Icons.shield_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _openAddScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddReminderScreen(garageId: widget.garageId),
      ),
    );
    if (result != null) _loadReminders();
  }

  Future<void> _openEditScreen(Map<String, dynamic> reminder) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddReminderScreen(garageId: widget.garageId, reminder: reminder),
      ),
    );
    if (result != null) _loadReminders();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Reminders',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: theme.primaryColor),
            onPressed: _openAddScreen,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildNotificationBanner(),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: theme.primaryColor),
                  )
                : _error != null
                ? _buildError()
                : _reminders.isEmpty
                ? _buildEmpty(theme)
                : _buildList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadReminders,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeProvider theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'No Reminders Yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Add MOT, service, or insurance\nreminders for this vehicle.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openAddScreen,
              icon: const Icon(Icons.add),
              label: const Text('Add Reminder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ThemeProvider theme) {
    return RefreshIndicator(
      color: theme.primaryColor,
      onRefresh: _loadReminders,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _reminders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final reminder = _reminders[index];
          final days = _daysUntil(reminder['reminder_date'] ?? '');
          final statusColor = _statusColor(days);

          return GestureDetector(
            onTap: () => _openEditScreen(reminder),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE9E9E9)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    // Type icon badge
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _typeIcon(reminder['reminder_type'] ?? ''),
                        color: statusColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Type + date + notes
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reminder['reminder_type'] ?? '',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 13,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDate(reminder['reminder_date'] ?? ''),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          if ((reminder['notes'] ?? '').isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              reminder['notes'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Status pill
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _statusLabel(days),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
