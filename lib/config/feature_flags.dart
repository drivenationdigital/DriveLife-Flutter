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
  /// OFF while it is being tested. Buy Tickets behaves exactly as it always
  /// did: it opens whatever `ticket_url` the events API sends, in the
  /// device's browser. Turn this back on — one word — to restore the native
  /// flow; everything behind it is built and unchanged.
  ///
  /// Nothing is stranded by leaving it off. A cart is only created once a
  /// buyer commits to the native path, so with this false the app never
  /// opens one, never reserves stock and never talks to the checkout API.
  ///
  /// When it goes back on: tickets, details and Stripe payment all happen in
  /// the app, and two things still leave it on purpose — an event whose
  /// organiser takes PayPal, Square or Mollie (their own merchant accounts,
  /// browser SDKs, no native equivalent, so the whole checkout opens in an
  /// in-app browser rather than quietly dropping a method they switched on),
  /// and an organiser's external ticketing link, which is somebody else's
  /// site.
  static const bool nativeTicketSelection = false;

  /// Community gallery on events: the tab on the event detail screen and the
  /// "Share photos" buttons on the events list.
  ///
  /// Turning this off also drops the tab count on the event detail screen, so
  /// the TabController, the tabs and the TabBarView stay in agreement.
  static const bool eventCommunityGallery = true;
}
