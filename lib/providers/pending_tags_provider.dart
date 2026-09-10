import 'package:drivelife/api/media_api.dart';
import 'package:drivelife/models/media_models.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How many tags are waiting on this user, and how many of those they have not
/// laid eyes on yet.
///
/// Two different numbers, and the difference is the point. [pending] is the
/// real queue — everything still unanswered, which is what the Photos tab
/// shows. [unseen] is what the badge counts: things that have arrived since
/// they last looked.
///
/// A badge that simply mirrored the queue would never clear until every tag
/// was answered, so somebody who wants to decide later would carry a permanent
/// red dot and quickly learn to ignore it — at which point it stops working
/// for the tag that actually matters.
class PendingTagsProvider extends ChangeNotifier {
  static const String _seenKey = 'pending_tags_seen_ids';

  /// Keys of rows the user has already been shown.
  ///
  /// Kept as ids rather than a count or a timestamp: a count cannot tell
  /// "one answered, one arrived" from "nothing happened", and rows do not
  /// arrive in a reliable order.
  Set<String> _seen = {};

  List<PendingImage> _items = const [];

  bool _loaded = false;

  /// Everything still waiting to be answered.
  int get pending => _items.length;

  /// What the badge shows: waiting, and new since they last looked.
  int get unseen => _items.where((i) => !_seen.contains(_key(i))).length;

  /// A row's identity across refreshes.
  ///
  /// A gallery row is a tag, not a photo — the same photo can be in two
  /// galleries — so its tag id is what makes it itself.
  static String _key(PendingImage image) =>
      image.source == 'gallery' ? 'g${image.tagId}' : image.id;

  Future<void> _restore() async {
    if (_loaded) return;
    _loaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      _seen = (prefs.getStringList(_seenKey) ?? const []).toSet();
    } catch (_) {
      // A device that will not give us storage still gets a working badge,
      // it just forgets what was seen between launches.
    }
  }

  /// Reloads the queue. Quiet on failure — a badge is not worth an error.
  Future<void> refresh() async {
    await _restore();

    try {
      final result = await MediaAPI.getMatches(status: 'pending', limit: 50);
      _items = result.data;

      // Anything answered elsewhere stops being worth remembering, so the
      // stored set cannot grow without limit.
      final live = _items.map(_key).toSet();
      if (_seen.length > live.length) {
        _seen = _seen.intersection(live);
        await _persist();
      }

      notifyListeners();
    } catch (_) {
      // Leave the last known state alone.
    }
  }

  /// Marks everything currently waiting as seen.
  ///
  /// Called when the review queue is opened, not when a tag is answered:
  /// looking is what clears a badge, and deciding is a separate thing the user
  /// is allowed to put off.
  Future<void> markSeen() async {
    await _restore();

    final live = _items.map(_key).toSet();
    if (live.difference(_seen).isEmpty) return;

    _seen = live;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_seenKey, _seen.toList());
    } catch (_) {
      // Same as above — the badge still works for this session.
    }
  }

  /// Drops one row after it has been answered, without a round trip.
  void resolved(PendingImage image) {
    final key = _key(image);

    _items = _items.where((i) => _key(i) != key).toList();
    _seen.remove(key);

    notifyListeners();
    _persist();
  }
}
