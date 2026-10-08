import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/config/feature_flags.dart';
import 'package:drivelife/screens/web/web_page_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the dashboard's event editor inside the app.
///
/// The same container approach as the ticket checkout, and an in-app
/// **browser** for the same reasons — but this one is not a public page, so it
/// needs a session before it will render anything at all.
///
/// The app and the dashboard run on two different JWT systems: different
/// secrets (php-api hardcodes one, dl-accounts signs with `SECURE_AUTH_KEY`)
/// and different claims (`user_id` against `sub`). So the app's own token is
/// not a dashboard session and cannot be made into one by passing it along —
/// it is traded for a short-lived dashboard token first, server-side.
abstract final class EventEditorWeb {
  const EventEditorWeb._();

  /// Where the editor sends the organiser when they are finished.
  ///
  /// The dashboard shows this as "Done" in place of its own back link, which
  /// otherwise points at pages that make no sense inside a container.
  static const String _returnLink = 'drivelife://app/?dl-editor=1';

  /// The dashboard origin. The editor is served by the accounts app, not by
  /// WordPress, so this is the accounts host rather than [AppEnvironment
  /// .wordpressBase].
  static String get _base => AppEnvironment.accountsBase;

  /// Opens the editor for an existing event, or the create wizard when
  /// [eventEid] is null.
  ///
  /// [site] is the event's region, carried in front of the id as the
  /// dashboard's own links do (`parseRef`/`ref` in lib/siteRef.ts) — post ids
  /// are only unique within a blog.
  ///
  /// Returns false when there is no usable session or no browser would take
  /// the URL, so the caller can say so rather than leaving a dead button.
  static Future<bool> open({
    String? eventEid,
    String site = 'uk',
    BuildContext? context,
  }) async {
    // Fetched at the last moment: it is good for fifteen minutes, and a token
    // minted at app launch would be long dead by the time anybody edits
    // anything.
    final session = await EventsAPI.getDashboardSessionToken();

    if (session == null || session.isEmpty) {
      // Signed out, or the exchange is unavailable. Nothing to open: the
      // editor would bounce to the dashboard's own login, which is not a
      // thing a buyer in a container can usefully complete.
      return false;
    }

    // ALWAYS prefixed, both regions — this is the dashboard's convention
    // (formatRef in lib/siteRef.ts), where a bare id means "region unknown"
    // and the editor refuses it with "event-edit requires a site".
    //
    // Deliberately NOT the checkout's rule, where bare means UK. That one is
    // bare for backwards compatibility with every ticket link ever issued;
    // this one has no such history and says what it means. Two conventions
    // that look alike and differ in their default, so resist tidying them
    // into one.
    final ref = '${site.toLowerCase() == 'us' ? 'us' : 'uk'}$eventEid';

    final path = eventEid == null || eventEid.isEmpty
        ? '/events/create'
        : '/events/new';

    final url = Uri.parse('$_base$path').replace(
      queryParameters: {
        if (eventEid != null && eventEid.isNotEmpty) 'eid': ref,
        'complete': _returnLink,
        // Swapped for a cookie and stripped from the URL by the dashboard's
        // middleware on arrival, so it lives in the address bar for exactly
        // one redirect.
        'dl_s': session,
      },
    );

    // As an app screen, where the demo flag asks for it. Needs a context to
    // push onto, so a caller without one still gets the browser.
    if (FeatureFlags.embeddedEditor && context != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<Uri>(
          builder: (_) => WebPageScreen(
            url: url,
            title: eventEid == null ? 'New event' : 'Edit event',
            // The dashboard lives on the accounts host; links anywhere else
            // are somebody's website and belong in a real browser.
            internalHosts: {url.host},
          ),
        ),
      );

      return true;
    }

    // Carries a session token, so only ever in a developer's build.
    if (kDebugMode || AppEnvironment.isStaging) {
      debugPrint(
        '📝 [Editor] Opening ${url.replace(queryParameters: {...url.queryParameters, 'dl_s': '<redacted>'})}',
      );
    }

    for (final mode in [
      LaunchMode.inAppBrowserView,
      LaunchMode.externalApplication,
    ]) {
      try {
        if (await launchUrl(url, mode: mode)) return true;
      } catch (_) {
        // Try the next mode rather than failing the whole attempt.
      }
    }

    return false;
  }
}
