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

  /// "Continue with Apple" and "Continue with Google" on the login screen.
  ///
  /// ── WHY IT SHIPS OFF ─────────────────────────────────────────────
  ///
  /// The code is complete on both sides, but neither provider works
  /// until console configuration exists that cannot live in this
  /// repository:
  ///
  ///   * google_sign_in THROWS on iOS without the REVERSED_CLIENT_ID
  ///     URL scheme in Info.plist, and returns a silent failure on
  ///     Android without the SHA-1 and SHA-256 fingerprints registered.
  ///   * Sign in with Apple needs the capability on the App ID, the
  ///     entitlement in Xcode, and a Services ID + key for the server
  ///     to verify against.
  ///   * The server needs DL_GOOGLE_CLIENT_IDS and DL_APPLE_BUNDLE_IDS
  ///     in endpoints/app-secrets.php, or every token is rejected --
  ///     deliberately, because a token with an unchecked audience is a
  ///     token minted for somebody else's app.
  ///
  /// A button that opens a sheet and then fails is worse than no
  /// button, so this stays false until that work is done. Turning it on
  /// is this one line.
  ///
  /// APPLE REQUIRE THE PAIR. An app offering Google without Apple is
  /// rejected under App Store guideline 4.8, so these are one flag
  /// rather than two.
  static const bool socialSignIn = true;

  /// The Apple button specifically.
  ///
  /// Separate from [socialSignIn] ONLY so Google could be tested before
  /// the Apple Developer work was done. That work is now complete:
  ///
  ///   * Sign In with Apple is enabled on App ID com.app.carcalendar
  ///   * com.apple.developer.applesignin is in Runner.entitlements,
  ///     which all three build configs point at
  ///   * the server verifies Apple's tokens against
  ///     DL_APPLE_BUNDLE_IDS — see endpoints/auth-social.php
  ///
  /// ── STILL OUTSTANDING, AND NOT GATED BY THIS FLAG ─────────────────
  ///
  /// Revoking the Apple token on account deletion, which App Store
  /// guideline 5.1.1(v) requires. dl_social_apple_revoke() is written
  /// but returns 'not_configured' until DL_APPLE_KEY_ID and
  /// DL_APPLE_PRIVATE_KEY are set in app-secrets.php. Sign-in works
  /// without them; only the revoke is dormant, and a deletion still
  /// completes. That is a review finding waiting to happen, not a
  /// broken feature — so it does not hold this flag off.
  ///
  /// App Store guideline 4.8: an app offering a third-party sign-in has
  /// to offer Sign in with Apple as well, so shipping iOS with
  /// socialSignIn on and this off would be a rejection.
  ///
  /// Android is unaffected either way: the Apple button never renders
  /// there, where it would be a web redirect for no benefit.
  static const bool appleSignIn = true;

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

  /// Show `@username` on a push notification.
  ///
  /// OFF. It is the label naming WHICH signed-in account a notification
  /// is for, shown as the Android subText and the iOS subtitle — not
  /// the sender's name. On the only device most people have, with one
  /// account signed in, it answers a question nobody asked and reads
  /// like the notification is addressed from them.
  ///
  /// Hidden rather than deleted: it earns its place the moment multi-
  /// account is common, and "which account was that for?" becomes a
  /// real question. Turning it back on is this one line.
  ///
  /// Note the background isolate cannot see the account list, so it
  /// cannot show the label only when two accounts exist — it is all or
  /// nothing there, which is part of why this is a flag rather than a
  /// smarter rule.
  static const bool notificationAccountLabel = false;

  /// Shows what each picked photo's EXIF actually contained, under the
  /// media grid in the composer.
  ///
  /// ── A DEBUG PANEL, NOT A FEATURE ─────────────────────────────────
  ///
  /// The question it answers is what share of real photos carry a usable
  /// GPS tag, and WHY the rest do not — a redacted tag, a screenshot, a
  /// photo saved from a message and a denied permission all look
  /// identical from the outside, and only one of them is fixable.
  ///
  /// It shows the misses as prominently as the hits for that reason. A
  /// panel listing only successes would make any camera roll look fully
  /// tagged and send us hunting the wrong bug.
  ///
  /// Off before release. It exposes coordinates on screen.
  static const bool mediaLocationDebug = false;

  /// WRITE chat messages encrypted.
  ///
  /// ── ON, AND GATED PER CONVERSATION ───────────────────────────────
  ///
  /// Reading encrypted messages is NOT behind this flag and is always
  /// on: a client has to be able to open an envelope before any client
  /// is allowed to create one. This flag only controls whether THIS
  /// app seals what it sends.
  ///
  /// Messaging is two-sided — a sealed message sent to somebody on
  /// 4.7.9 renders as base64 on their screen, because their app reads
  /// `content` straight out of Supabase and knows nothing about
  /// envelopes. There is no client-side fix for a client that has
  /// already shipped.
  ///
  /// ── THIS FLAG IS NOT THE SAFETY MECHANISM ────────────────────────
  ///
  /// ChatReadiness is. Turning this on does not seal anything on its
  /// own: every send still asks whether EVERY participant has recorded
  /// that they can open an envelope, and sends plaintext unless they
  /// all have. So this is "start converting threads as people update",
  /// not "encrypt everything now".
  ///
  /// That is why it no longer needs a minimum-version gate, and why a
  /// user who never updates keeps working chat instead of a thread full
  /// of base64.
  ///
  /// The order:
  ///
  ///   1. Ship a version that READS envelopes. Writes stay plaintext.
  ///      Nothing changes for anybody. ← done
  ///   2. Create the readiness table, ship a version that announces
  ///      itself and checks before sealing.
  ///   3. Turn this on. Threads convert themselves, oldest adopters
  ///      first. Nobody is forced to update.
  ///   4. Backfill the historical messages last, and only behind a
  ///      version floor — re-encrypting history is the step that DOES
  ///      take it away from anyone on an older build.
  ///
  /// Step 3 is what this is. It is not reversible for messages already
  /// sent — a sealed message stays sealed — so what makes it safe to
  /// turn on this early is not caution about timing, it is that
  /// ChatReadiness refuses to seal to anybody who has not announced
  /// themselves. Early adopters simply find each other.
  ///
  /// ── WHAT TO WATCH AFTER SHIPPING ─────────────────────────────────
  ///
  /// Nothing seals until two people on this build message each other,
  /// so the first days look exactly like today. The query at the foot
  /// of supabase/sql/chat-crypto-readiness.sql says how far it has got.
  ///
  /// If something is wrong, setting this back to false stops any NEW
  /// message being sealed — but it does not unseal what already was,
  /// and an app already on a shelf keeps the old value. That is the
  /// whole reason the readiness check exists rather than a flag day.
  static const bool encryptChatMessages = true;


  /// Community gallery on events: the tab on the event detail screen and the
  /// "Share photos" buttons on the events list.
  ///
  /// Turning this off also drops the tab count on the event detail screen, so
  /// the TabController, the tabs and the TabBarView stay in agreement.
  static const bool eventCommunityGallery = true;
}
