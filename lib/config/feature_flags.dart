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

  /// Community gallery on events: the tab on the event detail screen and the
  /// "Share photos" buttons on the events list.
  ///
  /// Turning this off also drops the tab count on the event detail screen, so
  /// the TabController, the tabs and the TabBarView stay in agreement.
  static const bool eventCommunityGallery = true;
}
