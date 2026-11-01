import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/screens/web/web_page_screen.dart';
import 'package:flutter/material.dart';

/// Opens the organiser's Events Manager inside the app.
///
/// The dashboard's own events list — every event the organiser runs, with
/// its orders, applications and editors hanging off it. Far too much to
/// rebuild natively for the small number of people who are organisers, and
/// it already exists, so it is opened in a container like the editor and
/// the overview are.
///
/// Same session trade as [EventEditorWeb]: the app and the dashboard run on
/// different JWT systems, so the app's token is exchanged server-side for a
/// dashboard one rather than passed along.
abstract final class EventsManagerWeb {
  const EventsManagerWeb._();

  /// Where the manager sends the organiser when they are done with it.
  static const String _returnLink = 'drivelife://app/?dl-editor=1';

  /// Opens the manager. Returns false when there is no usable session, so
  /// the caller can say so rather than leaving a button that does nothing.
  static Future<bool> open(BuildContext context) async {
    // Minted at the last moment. Even the longer manager session is
    // short-lived, and one taken at launch would be dead on arrival.
    final session = await EventsAPI.getDashboardSessionToken(scope: 'manager');

    if (session == null || session.isEmpty) return false;
    if (!context.mounted) return false;

    final url = Uri.parse('${AppEnvironment.accountsBase}/events').replace(
      queryParameters: {
        'complete': _returnLink,
        // Traded for a cookie and stripped by the dashboard's middleware on
        // arrival, so it is in the URL for exactly one redirect.
        'dl_s': session,
      },
    );

    await Navigator.of(context).push<Uri>(
      MaterialPageRoute<Uri>(
        builder: (_) => WebPageScreen(
          url: url,
          title: 'Events manager',
          // The manager links on to its own event pages, editors and order
          // lists, all of which belong in here. Anything on another host is
          // somebody's website and should leave.
          internalHosts: {url.host},
        ),
      ),
    );

    return true;
  }
}
