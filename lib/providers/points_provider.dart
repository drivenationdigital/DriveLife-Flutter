import 'package:drivelife/api/points_api.dart';
import 'package:flutter/foundation.dart';

/// The signed-in user's points balance, in one place.
///
/// WHY THIS EXISTS
///
/// The header pill used to hold the balance in HomeTabs' own State and
/// fetch it on launch and on resume. Points are earned deep inside other
/// screens — adding a vehicle, posting, guessing the car — and none of
/// those can reach into that State, so the number sat visibly wrong
/// until the app was backgrounded and brought back. It was reported as
/// "a little delayed", which is the generous reading of "stale until you
/// leave the app".
///
/// Anything that awards points calls [refresh]; the pill watches. The
/// server is still the only thing that decides a balance — this never
/// adds up an award locally, because the rules that can refuse one
/// (daily caps, per-vehicle uniqueness) live there, and a header that
/// optimistically counted a capped award would be lying until the next
/// fetch corrected it.
class PointsProvider extends ChangeNotifier {
  int _current = 0;
  int _lifetime = 0;

  // ── A reward waiting to be shown ───────────────────────────────────
  //
  // Posts and galleries are published by BACKGROUND PROVIDERS, long
  // after the composer that started them has been popped. There is no
  // context to show a dialog from at the moment the server pays, and
  // the screen that would have shown it no longer exists.
  //
  // So the award is queued here instead and the app shell — which is
  // always mounted and already watches this provider for the header
  // pill — shows it. One mechanism serves posts, galleries and
  // anything else that earns points away from a live screen.

  int _pendingPoints = 0;
  String? _pendingReason;

  /// Points earned but not yet shown to the user. Zero means nothing
  /// is waiting.
  int get pendingPoints => _pendingPoints;

  /// What they were for, for the reward's subtitle.
  String? get pendingReason => _pendingReason;

  /// Queue a reward and refresh the balance behind it.
  ///
  /// Ignores a zero, so callers can hand over whatever the server
  /// said without first checking whether it paid — a request that hit
  /// a daily cap returns 0 and must show nothing.
  void queueReward(int points, String reason) {
    if (points <= 0) {
      // Still worth a refresh: a capped award pays nothing, but
      // something else may have moved the balance since.
      refresh();
      return;
    }

    _pendingPoints = points;
    _pendingReason = reason;
    notifyListeners();

    refresh();
  }

  /// Called by the shell once the reward has been shown.
  ///
  /// Silent — notifying here would rebuild the shell immediately after
  /// a dialog closed, for a change nothing renders.
  void clearPendingReward() {
    _pendingPoints = 0;
    _pendingReason = null;
  }

  /// Spendable. What the header shows.
  int get current => _current;

  /// Ever earned. What the leaderboard ranks on.
  int get lifetime => _lifetime;

  bool _loading = false;
  bool _loaded = false;

  /// Whether a balance has come back yet.
  ///
  /// Not the same question as "is it zero". Somebody who has never
  /// earned anything genuinely has nought, and showing them a skeleton
  /// for ever because the number happens to match the starting value
  /// would be worse than showing a wrong one.
  bool get loaded => _loaded;

  /// Re-read the balance from the server.
  ///
  /// Safe to call from anywhere, as often as you like: overlapping calls
  /// collapse into the first, and a balance that has not moved does not
  /// notify, so a rebuild only happens when the number on screen is
  /// actually about to change.
  // ── What each action is worth ──────────────────────────────────────
  //
  // Held here because four screens need it — the Create sheet, the
  // empty-garage card, the last step of signup and the rules toast —
  // and every one of them used to carry its own copy of the numbers.
  //
  // Starts on the fallback rather than on nothing, so a screen built
  // before the fetch lands shows today's real amounts instead of
  // zeroes, and corrects itself a moment later if the server disagrees.

  PointsRules _rules = PointsRules.fallback;

  /// The current rewards. Never null, never zero.
  PointsRules get rules => _rules;

  bool _rulesLoaded = false;
  bool _loadingRules = false;

  /// Fetch the rules once per successful load.
  ///
  /// Once is enough on success: they change when somebody edits the
  /// server, which is not something that happens while an app is open.
  ///
  /// A FAILURE IS RETRIED. The flag is only set once an answer has
  /// actually arrived, so an app launched on a dead connection tries
  /// again the next time the shell asks — which is on resume from the
  /// background. Until then it keeps showing the fallback, which holds
  /// the real amounts, so nothing is ever blank or wrong-by-default.
  ///
  /// _loadingRules is separate, and is what stops two calls in flight
  /// at once while the first is still waiting.
  Future<void> loadRules() async {
    if (_rulesLoaded || _loadingRules) return;

    _loadingRules = true;

    try {
      final fetched = await PointsAPI.rules();

      // Null means it could not be fetched. Keep the fallback and
      // leave _rulesLoaded false so the next call tries again.
      if (fetched == null) return;

      _rulesLoaded = true;

      // Only notify on a real difference — the fallback and the server
      // usually agree, and a rebuild of every screen that watches this
      // for an identical answer is work nobody asked for.
      if (fetched.summary != _rules.summary ||
          !_sameAmounts(fetched.amounts, _rules.amounts)) {
        _rules = fetched;
        notifyListeners();
      }
    } finally {
      _loadingRules = false;
    }
  }

  static bool _sameAmounts(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;

    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }

    return true;
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;

    try {
      final mine = await PointsAPI.mine();

      // The first answer always notifies, even when it matches the zero
      // this started on: that notification is what replaces the
      // skeleton. Only an unchanged balance on a LATER refresh is
      // allowed to stay quiet.
      final changed =
          !_loaded || mine.current != _current || mine.lifetime != _lifetime;

      _current = mine.current;
      _lifetime = mine.lifetime;

      // Set even when the request failed and PointsAPI handed back an
      // empty. A balance that will not load is a stale number; a
      // skeleton that will not resolve is a broken header.
      _loaded = true;

      if (changed) notifyListeners();
    } finally {
      _loading = false;
    }
  }
}
