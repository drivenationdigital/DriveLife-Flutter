import 'package:drivelife/config/app_environment.dart';

/// Switches for work that is built but not ready to ship.
///
/// The code behind a disabled flag stays in the tree — it is only unreachable
/// from the UI, so turning a flag back on is a one-line change with no
/// re-implementation. Flip a flag here rather than commenting out call sites,
/// which is what leaves half-wired features behind.
class FeatureFlags {
  const FeatureFlags._();

  /// The Media tab (bottom nav) and the "Images of you" screen behind it.
  ///
  /// Turning this off removes the tab from the nav and the screen from the
  /// stack; nothing else needs touching, because the tab indices around it are
  /// derived rather than hard-coded.
  static const bool mediaTab = true;

  // NOTE: the event editor's Discounts / Show cars / Car clubs / Traders work
  // is parked, not flagged. add_event_screen.dart has been reverted to its
  // committed state, so it neither shows those tabs nor reads a flag for them.
  // The pieces are still on disk for when the API side is ready:
  //   models/event_editor_models.dart, models/event_edit_data.dart,
  //   api/event_extras_api.dart, api/dl_accounts_api.dart,
  //   widgets/events/editor/*.dart
  // Re-wiring them means re-adding the tabs to the editor, not flipping a flag.

  /// The in-app ticket checkout.
  ///
  /// Tickets, details and payment all happen in the app — Stripe, Square and
  /// PayPal through their own SDKs, Mollie through its hosted page and back
  /// via a `drivelife://` link.
  ///
  /// Two things still leave the app on purpose: an organiser's external
  /// ticketing link, which is somebody else's site, and a card processor this
  /// version of the app does not know about, which can only appear if one is
  /// added server-side. Both open the web checkout rather than quietly
  /// dropping a payment method the organiser switched on.
  ///
  /// Still a switch, and still off-able in one build flag:
  ///   flutter build apk --dart-define=DL_NATIVE_TICKETS=false
  /// which puts Buy Tickets back to opening whatever `ticket_url` the events
  /// API sends, in the device's browser. Nothing is stranded by turning it
  /// off — a cart is only created once a buyer commits to the native path, so
  /// the app never opens one, never reserves stock and never talks to the
  /// checkout API.
  /// SHELVED (2026-10-06). Tickets are bought in the web container instead —
  /// see [TicketWebCheckout] — which is one checkout to maintain rather than
  /// two, and lets the Square SDK go (it is what currently breaks release
  /// builds, pulling Kotlin 2.3.0 into a 2.1.0 project).
  ///
  /// Every screen and payment path behind this still compiles. Turn it back
  /// on with one word here, or for a single build:
  ///   flutter build apk --dart-define=DL_NATIVE_TICKETS=true
  static const bool nativeTicketSelection = bool.fromEnvironment(
    'DL_NATIVE_TICKETS',
    defaultValue: false,
  );

  /// Whether Mollie card payments are taken in the app.
  ///
  /// Separate from [nativeTicketSelection] because it is the one provider
  /// that has never taken a real payment from the app. The code is complete —
  /// hosted page, deep-link return, verdict read back from Mollie — but
  /// untested against a live organiser, and Mollie holds the card slot
  /// *instead of* Stripe, so a bug here is not a degraded checkout, it is an
  /// event that cannot sell a ticket.
  ///
  /// Off in production until it has been proven on staging, where it is on.
  /// With it off a Mollie event behaves as it always has: the whole checkout
  /// opens on the web, which works today. Flip the default once it is tested,
  /// or try it early with
  ///   flutter build apk --dart-define=DL_NATIVE_MOLLIE=true
  static const bool nativeMollieCheckout = bool.fromEnvironment(
    'DL_NATIVE_MOLLIE',
    defaultValue: AppEnvironment.useStaging,
  );

  /// The event add/edit form, opened as the dashboard's own editor in a web
  /// container rather than rebuilt natively.
  ///
  /// ON. The dashboard editor has eleven panels against add_event_screen's
  /// one — tickets, discounts, traders and show cars among them — so this is
  /// a gain in capability rather than a retreat, and it is one editor to
  /// maintain instead of two drifting apart.
  ///
  /// [AddEventScreen] is still the fallback, not dead code: an organiser with
  /// no dashboard session, a club event, or an edit reached without an
  /// encrypted id all land there, and so does any device with no browser that
  /// will host an in-app view. See openEventEditor(), which makes that call
  /// in one place.
  ///
  /// Off-able for a single build if a release ever needs the old form back:
  ///   flutter build apk --dart-define=DL_WEB_EVENT_EDITOR=false
  static const bool webEventEditor = bool.fromEnvironment(
    'DL_WEB_EVENT_EDITOR',
    defaultValue: true,
  );

  /// Render the web event editor as an app SCREEN rather than handing it to
  /// the system browser.
  ///
  /// ON, and matching the overview so both organiser screens behave alike.
  /// The difference is all chrome: an embedded WebView wears the app's own
  /// header and back button instead of Safari's share and "open in browser",
  /// and the `drivelife://` finish closes a screen rather than bouncing
  /// through the OS.
  ///
  /// Only safe because the editor takes no payment. The checkout must keep
  /// using the system browser whatever happens here — PayPal refuses embedded
  /// user agents and Apple Pay exists only in Safari. Do not generalise this
  /// flag to cover it.
  ///   flutter build apk --dart-define=DL_EMBEDDED_EDITOR=false
  static const bool embeddedEditor = bool.fromEnvironment(
    'DL_EMBEDDED_EDITOR',
    defaultValue: true,
  );

  /// The organiser's event overview, pulled from the dashboard rather than
  /// rendered natively by event_admin_view_screen.
  ///
  /// ON. The dashboard page carries orders, applications and discounts the
  /// app has never had, and it is one screen to maintain rather than two
  /// drifting apart.
  ///
  /// Knowingly traded away with it: the QR scanner in the native screen's
  /// header, offline behaviour, and the per-region currency work on its
  /// orders and tickets tables. event_admin_view_screen is still the
  /// fallback — no dashboard session, or a row with no encrypted id — so
  /// none of that is deleted, only unreachable from the events list.
  ///   flutter build apk --dart-define=DL_WEB_EVENT_OVERVIEW=false
  static const bool webEventOverview = bool.fromEnvironment(
    'DL_WEB_EVENT_OVERVIEW',
    defaultValue: true,
  );

  /// Community gallery on events: the tab on the event detail screen and the
  /// "Share photos" buttons on the events list.
  ///
  /// Turning this off also drops the tab count on the event detail screen, so
  /// the TabController, the tabs and the TabBarView stay in agreement.
  static const bool eventCommunityGallery = true;
}
