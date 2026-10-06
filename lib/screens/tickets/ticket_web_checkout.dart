import 'package:drivelife/api/checkout_api.dart';
import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/models/user_model.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the web ticket checkout inside the app.
///
/// An in-app **browser**, not a WebView. That is not a detail: PayPal refuses
/// to authenticate inside an embedded WebView, and Mollie's own docs say to
/// use the device browser rather than one so its 3-D Secure redirects work.
/// A WebView would look marginally more integrated and quietly break two of
/// the four payment methods.
///
/// The buyer never has to find their way back by hand. `?complete=` tells the
/// checkout to redirect to a `drivelife://` link instead of rendering its
/// thank-you page, which the deep-link handler turns into the buyer's tickets
/// with the browser closing over it — see the `dl-order` branch in
/// deeplinks_helper.dart.
///
/// NOT yet solved: the order does not reach the buyer's ticket section.
/// `cc_get_tickets_for_user()` finds orders by WordPress user id, and the
/// classic checkout stamps that from `get_current_user_id()` — a carevents.com
/// session cookie this browser does not have. So an order bought here is
/// reachable from the confirmation and the buyer's email, but not from the
/// Tickets tab. Fixing it means the browser carrying a token the backend
/// verifies, not an id on the URL; the box-office flow in embed.php
/// (`admin_token`) is the pattern to copy.
abstract final class TicketWebCheckout {
  const TicketWebCheckout._();

  /// Where the checkout sends the buyer once the order is placed.
  ///
  /// The checkout appends `order_id` (and a download URL) to this, and the
  /// deep-link handler reads them. Keeping the literal here rather than at the
  /// call site means the app only claims to handle one shape of return.
  static const String _returnLink = 'drivelife://app/?dl-order=1';

  /// Builds the checkout URL for an event.
  ///
  /// [user] is used only to spare a signed-in buyer retyping what the app
  /// already knows. It is prefill and nothing more: the order is attributed
  /// server-side from the session, never from anything carried in a URL, so a
  /// doctored link cannot put somebody else's order on an account.
  static Uri urlFor(String eventEid, {User? user, String? coupon}) {
    final params = <String, String>{'complete': _returnLink};

    if (user != null) {
      void add(String key, String? value) {
        final v = (value ?? '').trim();
        if (v.isNotEmpty) params[key] = v;
      }

      // Deliberately NOT the user id. Nothing server-side can safely act on
      // an id carried in a URL — anyone can edit it — so sending one would
      // put a user identifier in server logs and browser history to no
      // purpose. Attributing the order to an account needs a token the
      // backend can verify; see the note at the top of this file.
      add('dl_email', user.email);
      add('dl_first', user.firstName);
      add('dl_last', user.lastName);
      // The same source the native details step prefilled from.
      add('dl_phone', user.billingInfo?.phone);
    }

    if ((coupon ?? '').trim().isNotEmpty) params['coupon'] = coupon!.trim();

    return Uri.parse(
      '${CheckoutApi.checkoutBaseUrl}/$eventEid',
    ).replace(queryParameters: params);
  }

  /// Opens the checkout. Returns false if no browser would take it.
  ///
  /// Tries the in-app browser first and a real one second. Some devices have
  /// nothing that will host an in-app view, and on those a buyer leaving the
  /// app is far better than a Buy Tickets button that does nothing — they
  /// still come back through the same `drivelife://` link.
  static Future<bool> open(
    String eventEid, {
    User? user,
    String? coupon,
  }) async {
    final url = urlFor(eventEid, user: user, coupon: coupon);

    // The query carries a buyer's email and phone, so this is logged only in
    // a developer's build — never in a shipped one.
    if (kDebugMode || AppEnvironment.isStaging) {
      debugPrint('🎟️ [Checkout] Opening the web checkout: $url');
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
