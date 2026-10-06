import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Something new worth pointing at, once.
///
/// [id] is written to disk, so it is permanent: renaming one re-shows the tip
/// to everybody who had already dismissed it. Retiring a feature means
/// deleting the entry, never reusing its id for something else.
///
/// Suffix the id with a number so the same spot can carry a second tip later
/// ('poll-composer-1' → 'poll-composer-2') without either one resurrecting the
/// other.
@immutable
class FeatureTip {
  final String id;
  final String title;
  final String body;

  const FeatureTip({required this.id, required this.title, required this.body});
}

/// Every tip the app knows about.
///
/// One place, so what is currently being advertised can be read off in a
/// glance rather than hunted through the widget tree.
abstract final class FeatureTips {
  /// The composer's Poll button.
  static const poll = FeatureTip(
    id: 'poll-composer-1',
    title: 'Polls are here',
    body:
        'Add a poll to your post and let people vote from the comments. '
        'Choose how long it runs — a winner is shown when it closes.',
  );

  /// Everything above, for the reset in settings.
  static const List<FeatureTip> all = [poll];
}

/// Which feature tips a member has already been shown.
///
/// Built to cost nothing once the tips have been seen, which is the state the
/// app is in for all but a few minutes of its life:
///
/// * one preferences read at launch, off the first frame;
/// * the answer lives in a Set in memory, so asking is a hash lookup;
/// * dismissing updates memory and notifies immediately and writes to disk
///   unawaited — a lost write costs one extra showing, never a stalled tap;
/// * widgets subscribe through `context.select`, so marking one tip seen does
///   not rebuild anything that was not showing it.
class FeatureTipsProvider extends ChangeNotifier {
  static const String _seenKey = 'feature_tips_seen';
  static const String _enabledKey = 'feature_tips_enabled';

  Set<String> _seen = <String>{};
  bool _enabled = true;

  /// False until the first read finishes.
  ///
  /// Nothing shows before then. A tip that appears and vanishes half a second
  /// into a cold start — because the answer arrived late — is worse than one
  /// that waits for the next visit.
  bool _ready = false;

  /// The tip currently on screen, if any.
  ///
  /// Two callouts at once is not a tutorial, it is a mess. The first target to
  /// claim the screen holds it until it is dismissed.
  String? _showing;

  bool get ready => _ready;

  /// Whether tips are wanted at all. Off is a setting, not a state.
  bool get enabled => _enabled;

  /// Whether this tip still has something to say.
  bool shouldShow(FeatureTip tip) =>
      _ready && _enabled && !_seen.contains(tip.id);

  /// Whether this tip may open its callout right now.
  bool canPresent(FeatureTip tip) =>
      shouldShow(tip) && (_showing == null || _showing == tip.id);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _seen = (prefs.getStringList(_seenKey) ?? const []).toSet();
      _enabled = prefs.getBool(_enabledKey) ?? true;
    } catch (_) {
      // Unreadable preferences mean we cannot tell what has been seen.
      // Showing nothing is the quiet failure; showing everything again would
      // pester people who have dismissed it all already.
      _seen = <String>{};
      _enabled = false;
    }

    _ready = true;
    notifyListeners();
  }

  /// Claims the screen for this tip. Returns false if another holds it.
  bool claim(FeatureTip tip) {
    if (_showing != null && _showing != tip.id) return false;

    if (_showing != tip.id) {
      _showing = tip.id;
      // No notify: the caller is mid-build or mid-frame, and nothing else
      // needs to know which tip happens to be open.
    }

    return true;
  }

  void release(FeatureTip tip) {
    if (_showing == tip.id) _showing = null;
  }

  /// Done with this one, for good.
  void markSeen(FeatureTip tip) {
    if (_showing == tip.id) _showing = null;
    if (!_seen.add(tip.id)) return;

    notifyListeners();
    unawaited(_persistSeen());
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;

    _enabled = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (_) {
      // Kept in memory for this session either way.
    }
  }

  /// Forgets every dismissal, so the tips run again.
  Future<void> resetAll() async {
    _seen = <String>{};
    _showing = null;
    _enabled = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_seenKey);
      await prefs.setBool(_enabledKey, true);
    } catch (_) {
      // Reset for this session at least.
    }
  }

  Future<void> _persistSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_seenKey, _seen.toList());
    } catch (_) {
      // The tip shows once more next launch. Not worth surfacing.
    }
  }
}
