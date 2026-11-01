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
