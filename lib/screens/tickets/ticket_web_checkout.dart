import 'package:drivelife/api/checkout_api.dart';
import 'package:drivelife/api/events_api.dart';
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
/// The order still lands on the buyer's account. `cc_get_tickets_for_user()`
/// finds orders by WordPress user id, which the classic checkout stamps from
/// `get_current_user_id()` — a session this browser does not have. So the app
/// mints a short-lived signed claim (`app/v1/checkout-handoff`) and the
/// checkout carries it as `dl_u`; embed.php verifies the signature before the
/// order is written. Signed rather than encrypted on purpose: make_crypt's key
/// is fixed and lives in the repo, so an encrypted user id would be something
/// anyone could mint for any account.
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
  /// [user] only spares a signed-in buyer retyping what the app already
  /// knows — it is prefill, and editable. [handoff] is the part that counts:
  /// a signed, expiring claim the backend verifies before attributing the
  /// order. The two are separate because one is a convenience and the other
  /// is a fact, and a doctored URL must only ever be able to spoil the
  /// convenience.
  static Uri urlFor(
    String eventEid, {
    required String site,
    User? user,
    String? coupon,
    String? handoff,
  }) {
    final params = <String, String>{'complete': _returnLink};

    if ((handoff ?? '').trim().isNotEmpty) params['dl_u'] = handoff!.trim();

    if (user != null) {
      void add(String key, String? value) {
        final v = (value ?? '').trim();
        if (v.isNotEmpty) params[key] = v;
      }

      // Still not the raw user id: `dl_u` above is the identity claim, and
      // it is signed. These are only to save typing.
      add('dl_email', user.email);
      add('dl_first', user.firstName);
      add('dl_last', user.lastName);
      // The same source the native details step prefilled from.
      add('dl_phone', user.billingInfo?.phone);
    }

    if ((coupon ?? '').trim().isNotEmpty) params['coupon'] = coupon!.trim();

    // The region rides in front of the id, bare meaning UK — post ids are
    // only unique within a blog, so a US event opened without it resolves to
    // whichever UK event shares that id.
    final linkEid = site == 'us' ? 'us$eventEid' : eventEid;

    return Uri.parse(
      '${CheckoutApi.checkoutBaseUrl}/$linkEid',
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
    required String site,
    User? user,
    String? coupon,
  }) async {
    // Asked for at the last moment so it is as fresh as possible: it expires,
    // and a token minted when the app launched could be hours old by now.
    // Null when signed out, which is a normal guest checkout, not a failure.
    final handoff = user == null
        ? null
        : await EventsAPI.getCheckoutHandoffToken();

    final url = urlFor(
      eventEid,
      site: site,
      user: user,
      coupon: coupon,
      handoff: handoff,
    );

    // The query carries a buyer's email, phone and identity claim, so this is
    // logged only in a developer's build — never in a shipped one.
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
