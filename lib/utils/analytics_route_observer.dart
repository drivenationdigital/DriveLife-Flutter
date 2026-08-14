import 'package:drivelife/services/analytics_service.dart';
import 'package:flutter/widgets.dart';

/// Sends a Piwik PRO screen view whenever the visible page route changes.
///
/// Deep links arrive as raw URLs in [RouteSettings.name] (see
/// `AppRoutes.generateRoute`); those are skipped because the handler pushes the
/// real named route straight after, and the URLs can carry reset / verification
/// tokens we must not send off-device.
class AnalyticsRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _track(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _track(newRoute);
  }

  void _track(Route<dynamic>? route) {
    if (route is! PageRoute) return;

    final name = route.settings.name;
    if (name == null || !name.startsWith('/') || name.contains('?')) return;

    Analytics.trackScreen(name);
  }
}
