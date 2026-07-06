import 'package:drivelife/api/notifications_api.dart';
import 'package:drivelife/providers/cart_provider.dart';
import 'package:drivelife/screens/notifications_screen.dart';
import 'package:drivelife/screens/store/shop_screen.dart';
import 'package:drivelife/services/qr_scanner.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

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

  static Widget storeIcon() {
    return Builder(
      builder: (context) => Consumer<CartProvider>(
        builder: (context, cart, child) {
          final count = cart.itemCount;
          final baseIcon = SvgPicture.asset(
            'assets/app-icons/04-Basket.svg',
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
          );

          final icon = count > 0
              ? Badge(
                  backgroundColor: Colors.red,
                  label: Text('$count'),
                  child: baseIcon,
                )
              : baseIcon;

          return IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            onPressed: () => NavigationHelper.navigateTo(
              context,
              const ShopScreen(showAppBar: true, initialTab: 'basket'),
            ),
            icon: icon,
          );
        },
      ),
    );
  }

  /// Creates a QR code scanner button
  ///
  /// [onSuccess] callback is called when a QR code is successfully scanned
  /// Returns the scanned data containing entity_type and entity_id
  static Widget qrCodeIcon({
    Color iconColor = Colors.black,
    double iconSize = 20,
    EdgeInsets? padding,
    Function(Map<String, dynamic>)? onSuccess,
  }) {
    return Builder(
      builder: (context) => IconButton(
        padding: padding ?? EdgeInsets.zero,
        iconSize: iconSize,
        onPressed: () => _handleQrScan(context, onSuccess),
        icon: SvgPicture.asset(
          'assets/app-icons/header-qr.svg',
          width: iconSize,
          height: iconSize,
          colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
        ),
      ),
    );
  }

  static Widget qrCodeIconWLabel({
    Color iconColor = Colors.black,
    Function(Map<String, dynamic>)? onSuccess,
  }) {
    return Builder(
      builder: (context) => ListTile(
        // PADDING
        contentPadding: const EdgeInsets.symmetric(horizontal: 19, vertical: 0),
        leading: SvgPicture.asset(
          'assets/app-icons/header-qr.svg',
          width: 17,
          height: 17,
          colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
        ),
        title: const Text('Scan QR Code'),
        onTap: () {
          Navigator.pop(context);
          _handleQrScan(context, onSuccess);
        },
      ),
    );
  }

  /// Handle QR code scanning
  static Future<void> _handleQrScan(
    BuildContext context,
    Function(Map<String, dynamic>)? onSuccess,
  ) async {
    // Capture a stable navigator BEFORE the await.
    // The calling widget (menu item / button) may be disposed while
    // the scanner is open, leaving `context` defunct afterwards.
    final navigator = Navigator.of(context, rootNavigator: true);
    final result = await QrScannerService.showScanner(context);

    if (result == null) return;

    print('Scan result: $result');
    QrScannerService.handleScanResult(
      navigator.context, // stable context, not the defunct one
      result,
    );
  }

  /// Creates a combined row with QR and notification icons
  /// Useful for app bar actions
  static List<Widget> actionIcons({
    Color iconColor = Colors.black,
    bool showQr = true,
    bool showNotifications = true,
    bool showShare = false,
    Function(Map<String, dynamic>)? onQrSuccess,
    Function()? onShareTap,
  }) {
    return [
      if (showQr) qrCodeIcon(iconColor: iconColor, onSuccess: onQrSuccess),
      if (showNotifications) notificationIcon(iconColor: iconColor),
      if (showShare)
        IconButton(
          padding: EdgeInsets.zero,
          iconSize: 22,
          onPressed: onShareTap,
          icon: const Icon(Icons.share, color: Colors.black),
        ),
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
    this.iconSize = 20,
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
          SvgPicture.asset(
            'assets/app-icons/header-notification.svg',
            width: widget.iconSize,
            height: widget.iconSize,
            colorFilter: ColorFilter.mode(widget.iconColor, BlendMode.srcIn),
          ),
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
