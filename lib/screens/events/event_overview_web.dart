import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/screens/web/web_page_screen.dart';
import 'package:flutter/material.dart';

/// The organiser's event overview, served by the dashboard.
///
/// The same page the dashboard shows at `/events/<ref>` — overview, orders
/// and applications — rendered as an app screen rather than rebuilt natively.
///
/// Read-only in the sense that matters here: nothing on it takes a payment,
/// so it can live in a WebView. The ticket checkout cannot, and never will —
/// PayPal refuses embedded user agents and Apple Pay exists only in Safari.
abstract final class EventOverviewWeb {
  const EventOverviewWeb._();

  /// Where the page sends the organiser when they are done with it.
  static const String _returnLink = 'drivelife://app/?dl-editor=1';

  /// Opens the overview for [eventEid].
  ///
  /// Returns null when it could not be opened at all — no dashboard session,
  /// signed out, or the exchange unavailable — and the caller should fall
  /// back to the native screen rather than show an empty one.
  ///
  /// Otherwise returns the `drivelife://` link the page closed with, or an
  /// empty Uri if the organiser simply backed out. The page uses that link to
  /// ask for something the app does better than a web page can: `dl-view=1`
  /// for the native event screen, `dl-back=1` for the events list.
  static Future<Uri?> open(
    BuildContext context, {
    required String eventEid,
    String site = 'uk',
  }) async {
    // Minted at the last moment: it lives fifteen minutes, so one taken at
    // launch would be dead by the time anybody opened an event.
    final session = await EventsAPI.getDashboardSessionToken();

    if (session == null || session.isEmpty) return null;
    if (!context.mounted) return null;

    // Always prefixed, both regions — the dashboard's own convention
    // (formatRef in lib/siteRef.ts), where a bare id means "region unknown"
    // and the page refuses it. Not the checkout's rule, where bare means UK.
    final ref = '${site.toLowerCase() == 'us' ? 'us' : 'uk'}$eventEid';

    final url = Uri.parse('${AppEnvironment.accountsBase}/events/$ref').replace(
      queryParameters: {
        'complete': _returnLink,
        // Traded for a cookie and stripped by the dashboard's middleware on
        // arrival, so it is in the URL for exactly one redirect.
        'dl_s': session,
      },
    );

    final closedWith = await Navigator.of(context).push<Uri>(
      MaterialPageRoute<Uri>(
        builder: (_) => WebPageScreen(
          url: url,
          title: 'Event overview',
          // The dashboard links on to its own editor and order pages, which
          // should stay in here. Anything elsewhere is somebody's website.
          internalHosts: {url.host},
        ),
      ),
    );

    // Empty rather than null: null means "could not open", and backing out
    // of a screen that opened perfectly well is not that.
    return closedWith ?? Uri();
  }
}
