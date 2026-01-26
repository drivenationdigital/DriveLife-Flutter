import 'package:drivelife/api/notifications_api.dart';
import 'package:drivelife/screens/notifications_screen.dart';
import 'package:drivelife/services/qr_scanner.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';

// Import your existing services and helpers
// import 'package:your_app/services/notifications_api.dart';
// import 'package:your_app/services/qr_scanner_service.dart';
// import 'package:your_app/helpers/navigation_helper.dart';
// import 'package:your_app/screens/notifications_screen.dart';

/// Reusable header icons for app bars across the application
class SharedHeaderIcons {
  /// Creates a notification icon button with badge count
  ///
  /// This is a stateful widget that manages its own notification count
  /// and automatically refreshes when returning from the notifications screen
  static Widget notificationIcon({
    Color iconColor = Colors.black,
    Color badgeColor = Colors.red,
    double iconSize = 24,
    EdgeInsets? padding,
  }) {
    return NotificationIconButton(
      iconColor: iconColor,
      badgeColor: badgeColor,
      iconSize: iconSize,
      padding: padding ?? const EdgeInsets.only(right: 12),
    );
  }

  /// Creates a QR code scanner button
  ///
  /// [onSuccess] callback is called when a QR code is successfully scanned
  /// Returns the scanned data containing entity_type and entity_id
  static Widget qrCodeIcon({
    Color iconColor = Colors.black,
    double iconSize = 24,
    EdgeInsets? padding,
    Function(Map<String, dynamic>)? onSuccess,
  }) {
    return Builder(
      builder: (context) => IconButton(
        padding: padding ?? EdgeInsets.zero,
        iconSize: iconSize,
        onPressed: () => _handleQrScan(context, onSuccess),
        icon: Icon(Icons.qr_code, color: iconColor),
      ),
    );
  }

  /// Handle QR code scanning
  static Future<void> _handleQrScan(
    BuildContext context,
    Function(Map<String, dynamic>)? onSuccess,
  ) async {
    final result = await QrScannerService.showScanner(context);
    if (result != null && context.mounted) {
      QrScannerService.handleScanResult(
        context,
        result,
        onSuccess: (data) {
          // Call custom success callback if provided
          onSuccess?.call(data);

          // Default navigation based on entity type
          if (data['entity_type'] == 'profile') {
            Navigator.pushNamed(
              context,
              '/view-profile',
              arguments: {'userId': data['entity_id']},
            );
          } else if (data['entity_type'] == 'vehicle') {
            Navigator.pushNamed(
              context,
              '/vehicle-detail',
              arguments: {'garageId': data['entity_id'].toString()},
            );
          }
        },
      );
    }
  }

  /// Creates a combined row with QR and notification icons
  /// Useful for app bar actions
  static List<Widget> actionIcons({
    Color iconColor = Colors.black,
    bool showQr = true,
    bool showNotifications = true,
    Function(Map<String, dynamic>)? onQrSuccess,
  }) {
    return [
      if (showQr) qrCodeIcon(iconColor: iconColor, onSuccess: onQrSuccess),
      if (showNotifications) notificationIcon(iconColor: iconColor),
    ];
  }
}

/// Stateful notification icon button that manages its own count
class NotificationIconButton extends StatefulWidget {
  final Color iconColor;
  final Color badgeColor;
  final double iconSize;
  final EdgeInsets padding;

  const NotificationIconButton({
    Key? key,
    this.iconColor = Colors.black,
    this.badgeColor = Colors.red,
    this.iconSize = 24,
    this.padding = const EdgeInsets.only(right: 12),
  }) : super(key: key);

  @override
  State<NotificationIconButton> createState() => _NotificationIconButtonState();
}

class _NotificationIconButtonState extends State<NotificationIconButton> {
  int _notifCount = 0;
  bool _notifLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshNotificationCount();
  }

  Future<void> _refreshNotificationCount() async {
    if (_notifLoading) return;
    _notifLoading = true;

    try {
      final res = await NotificationsAPI.getNotificationCount();
      if (!mounted) return;
      setState(() => _notifCount = res);
    } catch (_) {
      // Silently fail - don't show error for notification count
    } finally {
      _notifLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: widget.padding,
      iconSize: widget.iconSize,
      onPressed: () async {
        await NavigationHelper.navigateTo(context, const NotificationsScreen());
        // Refresh count after coming back (so count updates after reading)
        if (mounted) _refreshNotificationCount();
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.notifications_none, color: widget.iconColor),
          if (_notifCount > 0)
            Positioned(
              right: -5,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: widget.badgeColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  _notifCount > 99 ? '99+' : '$_notifCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
