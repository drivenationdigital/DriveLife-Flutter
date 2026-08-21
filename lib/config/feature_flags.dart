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
  /// Hidden pending rework. While this is false the nav has five items and
  /// Profile sits at index 4 — see HomeTabsState.\_profileIndex.
  static const bool mediaTab = false;

  /// Community gallery on events: the tab on the event detail screen and the
  /// full-screen gallery reached from the events list.
  ///
  /// Hidden pending rework. The API methods in EventsAPI are left in place.
  static const bool eventCommunityGallery = false;
}
