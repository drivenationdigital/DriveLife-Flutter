/// Which set of servers this build talks to.
///
/// One switch, because the pieces have to agree. An encrypted event id, a cart
/// token and a Stripe PaymentIntent all belong to one WordPress — mixing a
/// production event id with the staging checkout proxy produces "event not
/// found" at best and a cart that cannot be paid for at worst.
///
/// Production is the default and the only thing a shipped build may use.
library;

import 'package:flutter/foundation.dart';

abstract final class AppEnvironment {
  const AppEnvironment._();

  /// Point the whole app at staging.
  ///
  /// Flip to true to test against staging.carevents.com, log in with a staging
  /// account, and buy a staging event's tickets with Stripe test cards. Flip
  /// back before building for release — [assertSafeForRelease] shouts if it is
  /// still on, and the app wears a stripe across the top the whole time so a
  /// staging build cannot be mistaken for the real one in a screenshot.
  ///
  /// Overridable at build time without editing this file:
  ///   flutter run --dart-define=DL_STAGING=true
  static const bool useStaging = bool.fromEnvironment(
    'DL_STAGING',
    defaultValue: false,
  );

  static bool get isStaging => useStaging;

  /// The WordPress the app reads and writes everything through.
  static String get wordpressBase => useStaging
      ? 'https://staging.carevents.com/uk'
      : 'https://www.carevents.com/uk';

  /// The same WordPress without the country path, for the few endpoints
  /// registered at the network root rather than on a blog.
  static String get wordpressRoot => useStaging
      ? 'https://staging.carevents.com'
      : 'https://www.carevents.com';

  /// The Next.js accounts app, which serves the checkout proxy at
  /// `/api/checkout`.
  static String get accountsBase => useStaging
      ? 'https://phpstack-889362-6614036.cloudwaysapps.com'
      : 'https://account.carevents.com';

  /// Where a buyer is sent to finish paying on the web.
  ///
  /// Production has a vanity host whose middleware rewrites `/<eid>` to
  /// `/get-tickets/<eid>`. Staging has no such subdomain, so it uses the real
  /// path on the accounts host — both end up appending `/<eid>`.
  static String get checkoutLinkBase => useStaging
      ? '$accountsBase/get-tickets'
      : 'https://checkout.carevents.com';

  /// Complains loudly if a release build was cut while still on staging.
  ///
  /// An assert rather than a hard failure: it stops a debug or profile build
  /// in its tracks during testing, and in release it is compiled out — which
  /// is why the banner exists as well.
  static void assertSafeForRelease() {
    assert(
      !(kReleaseMode && useStaging),
      'This is a RELEASE build pointed at STAGING. Set DL_STAGING=false.',
    );
  }
}

/// The region prefix the accounts dashboard puts in front of an event id.
///
/// The dashboard splits a ref on this prefix — see lib/siteRef.ts and
/// lib/regions.ts there — and it matches against its real region list
/// rather than a fixed two characters, so a new region needs an entry in
/// that table and nothing more here.
///
/// Written out rather than `site.toLowerCase()` because the two are not
/// the same thing: the country is GB and the region key is uk. Anything
/// unrecognised falls to uk, which is where the server sends it too.
String dashboardRegionKey(String? site) {
  switch ((site ?? '').trim().toLowerCase()) {
    case 'us':
    case 'usa':
    case 'ca':
    case 'mx':
      return 'us';
    case 'eu':
      return 'eu';
    case 'au':
    case 'nz':
      return 'au';
    default:
      return 'uk';
  }
}
