import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class NavigationHelper {
  /// Navigate with slide animation and iOS swipe support
  static Future<T?> navigateTo<T>(BuildContext context, Widget screen) {
    return Navigator.push<T>(
      context,
      CupertinoPageRoute(builder: (context) => screen),
    );
  }

  /// Navigate as modal with semi-transparent background
  static Future<T?> navigateModal<T>(BuildContext context, Widget screen) {
    return Navigator.push<T>(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
      ),
    );
  }

  /// Navigate and remove all previous routes
  static Future<T?> navigateAndRemoveAll<T>(
    BuildContext context,
    Widget screen,
  ) {
    return Navigator.pushAndRemoveUntil<T>(
      context,
      CupertinoPageRoute(builder: (context) => screen),
      (route) => false,
    );
  }

  /// Navigate and replace current route
  static Future<T?> navigateReplace<T>(BuildContext context, Widget screen) {
    return Navigator.pushReplacement<T, void>(
      context,
      CupertinoPageRoute(builder: (context) => screen),
    );
  }

  /// Go back
  static void goBack(BuildContext context, [dynamic result]) {
    Navigator.pop(context, result);
  }
}
