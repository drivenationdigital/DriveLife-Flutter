import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which flagged messages this person has already chosen to look at.
///
/// Tapping View used to last only as long as the screen, so closing the
/// thread put the warning back over something already read. That reads as
/// the app having forgotten rather than having protected anybody.
///
/// WHY THIS IS LOCAL AND NOT A TABLE
///
/// It is a record of what one person on one device has already seen. It
/// is nobody else's business, it does not need to survive a reinstall,
/// and syncing it would mean a write to Supabase every time somebody
/// taps View. The same reasoning every other platform applies to
/// "show sensitive content" state.
///
/// Keyed per account, because this app switches accounts and one
/// person's choice to look at something is not another's.
class RevealedMessages {
  RevealedMessages._();

  /// Keeping every id forever would grow without bound. 500 is far more
  /// than anybody will reveal, and the oldest falling off only means an
  /// ancient message is covered again — the warning reappearing on
  /// something from last year is a tolerable failure.
  static const int _limit = 500;

  static String _key(String userId) => 'revealed_messages_$userId';

  /// Insertion-ordered, so trimming drops the oldest. A Set because
  /// every read of it is a membership test.
  static final Map<String, Set<String>> _cache = {};

  /// Load this account's set. Cached, so the thread reads it once.
  static Future<Set<String>> forUser(String userId) async {
    final cached = _cache[userId];
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key(userId)) ?? const <String>[];

    final set = ids.toSet();
    _cache[userId] = set;
    return set;
  }

  /// Whatever has already been loaded for this account.
  ///
  /// Synchronous, for build(): a widget cannot await, and a warning that
  /// flashes on for one frame before disappearing is worse than one that
  /// appears a moment late.
  static Set<String> cachedFor(String userId) =>
      _cache[userId] ?? const <String>{};

  /// Remember that this message has been looked at.
  static Future<void> add(String userId, String messageId) async {
    final set = await forUser(userId);
    if (!set.add(messageId)) return;

    var ids = set.toList();
    if (ids.length > _limit) {
      ids = ids.sublist(ids.length - _limit);
      _cache[userId] = ids.toSet();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(userId), ids);
  }

  /// Drop the in-memory copy without touching what is on disk.
  ///
  /// Reopening the thread after a restart is exactly this, so it is what
  /// the persistence test needs in order to test persistence rather than
  /// the cache sitting in front of it.
  @visibleForTesting
  static void debugForgetCache() => _cache.clear();

  /// Forget everything for one account.
  ///
  /// Not called by anything yet. It exists because "clear what I have
  /// revealed" is the obvious thing a privacy setting would want, and
  /// the alternative is somebody later writing it against the raw key.
  static Future<void> clear(String userId) async {
    _cache.remove(userId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }
}
