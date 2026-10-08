import 'package:drivelife/config/feature_flags.dart';
import 'package:drivelife/screens/events/event_overview_web.dart';
import 'package:flutter/material.dart';

/// Opens an organiser's event overview, wherever it currently lives.
///
/// One decision point, like openEventEditor, so turning the flag off restores
/// the native screen everywhere at once and no call site has to know which
/// version it is getting.
///
/// [eventId] is the raw post id the native screen takes; [eventEid] is the
/// encrypted one the dashboard takes. Both travel because the two screens
/// address an event differently, and the web version is only reachable when
/// the encrypted id is to hand.
Future<void> openEventOverview(
  BuildContext context, {
  required String eventId,
  String? eventEid,
  String site = 'GB',
}) async {
  final region = site.toLowerCase() == 'us' ? 'us' : 'uk';

  if (FeatureFlags.webEventOverview && (eventEid ?? '').isNotEmpty) {
    final closedWith = await EventOverviewWeb.open(
      context,
      eventEid: eventEid!,
      site: region,
    );

    if (closedWith != null) {
      // The page asked for the app's own event screen. It exists, it has the
      // gallery and the navigation sheet, and it is better than the public
      // web page the dashboard would otherwise have opened a browser for.
      if (closedWith.queryParameters.containsKey('dl-view') &&
          context.mounted) {
        Navigator.pushNamed(
          context,
          '/event-detail',
          arguments: {
            'event': {'id': eventId, 'site': site},
          },
        );
      }

      // `dl-back` needs nothing: the events list is already underneath.
      return;
    }

    // No dashboard session. Falling through rather than stopping: the
    // organiser tapped their own event and the native screen still works.
    debugPrint('📋 [Overview] Web overview unavailable; using the native one');
  }

  if (!context.mounted) return;

  Navigator.pushNamed(
    context,
    '/event-owner-view',
    arguments: {'eventId': eventId, 'site': site},
  );
}
