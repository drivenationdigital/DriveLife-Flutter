import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How far through each video somebody has watched.
///
/// ── WHY THIS IS ON THE DEVICE AND NOT THE SERVER ────────────────────
///
/// For now, because there is no endpoint. When there is one, this
/// becomes the cache in front of it rather than being replaced: a
/// resume position has to be readable BEFORE the network answers, or
/// the player starts at zero and jumps a second later, which is worse
/// than not resuming at all.
///
/// ── WHAT IT DELIBERATELY DOES NOT REMEMBER ──────────────────────────
///
/// A position within a few seconds of the start, and a position within
/// the last thirty seconds of the end.
///
/// The first because resuming at 0:03 is not resuming, it is noise in
/// the UI telling somebody they have watched something they have not.
/// The second because finishing a video and being offered to resume it
/// at 58:40 is the app failing to notice you are done. Past that point
/// it is marked [finished] instead, which is its own answer - and the
/// one a list draws a "Watched" note from.
class WatchProgress {
  WatchProgress._();

  static const String _key = 'video_watch_progress_v1';

  /// Below this, there is nothing worth resuming.
  static const int _minimumSeconds = 10;

  /// Within this much of the end, treat it as watched.
  static const int _finishedSlack = 30;

  /// The value stored for a video that was watched to the end.
  ///
  /// ── WHY A SENTINEL AND NOT A SECOND STORE ──────────────────────
  ///
  /// Every reader of this map already asks whether the value is above
  /// zero before it draws anything - a progress bar needs a position,
  /// and a negative one is not a position. So a negative marker rides
  /// along in the existing map, read by the screens that care about
  /// it and ignored by the ones that do not, without a single call
  /// site having to change and without a second thing to keep in step
  /// with this one.
  ///
  /// It is also safe in the other direction: a build of the app older
  /// than this one reads -1, finds it below [_minimumSeconds], and
  /// starts the video at the beginning. The worst case is a missing
  /// badge, not a video that opens at minus one second.
  static const int finished = -1;

  /// How many videos to remember at once.
  ///
  /// Positions used to be deleted on completion, so the store could
  /// only ever hold what was part-watched - a handful. Keeping the
  /// finished ones means it grows with every video anybody ever gets
  /// to the end of, and it is one JSON string rewritten on each save.
  /// Five hundred is far more than anybody will scroll back through
  /// and still only a few kilobytes.
  static const int _maxEntries = 500;

  /// Cached in memory so a list of cards does not hit disk per card.
  static Map<String, int>? _cache;

  static Future<Map<String, int>> _all() async {
    final cached = _cache;

    if (cached != null) return cached;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);

      if (raw == null || raw.isEmpty) return _cache = {};

      final decoded = jsonDecode(raw);

      if (decoded is! Map) return _cache = {};

      return _cache = {
        for (final entry in decoded.entries)
          '${entry.key}': int.tryParse('${entry.value}') ?? 0,
      };
    } catch (e) {
      // A corrupt store is not worth a crash on a screen that works
      // perfectly well starting every video at the beginning.
      debugPrint('[watch] could not read progress: $e');

      return _cache = {};
    }
  }

  /// Where to resume [postId], or null to start at the beginning.
  static Future<int?> positionFor(String postId) async {
    final all = await _all();
    final seconds = all[postId];

    // finished is checked by name rather than left to the bound
    // below it. Both reject it, but only one of them says why.
    if (seconds == null ||
        seconds == finished ||
        seconds < _minimumSeconds) {
      return null;
    }

    return seconds;
  }

  /// Everything known, for drawing progress bars on a row of cards.
  static Future<Map<String, int>> positions() => _all();

  /// Records where they got to.
  ///
  /// Called often - once every few seconds while something plays - so
  /// it writes to memory every time and to disk only when the value
  /// has actually moved. SharedPreferences serialises the whole map on
  /// every write, and doing that at 1Hz while a video plays is a
  /// measurable cost for no benefit.
  static Future<void> save({
    required String postId,
    required int seconds,
    required int durationSeconds,
  }) async {
    if (postId.isEmpty) return;

    final all = await _all();

    // ── FINISHED IS AN ANSWER, NOT AN ABSENCE ──────────────────
    //
    // This used to delete the entry, which did stop a card showing a
    // 99% bar forever - but it also threw away the fact that the
    // video had been watched at all. A finished video and one nobody
    // has ever opened were indistinguishable, so no list could say
    // which was which.
    //
    // [finished] keeps the fact and still draws no bar, because every
    // bar in the app is guarded on a position above zero.
    if (durationSeconds > 0 && seconds >= durationSeconds - _finishedSlack) {
      if (all[postId] == finished) return;

      _touch(all, postId, finished);
      _trim(all);

      await _flush(all);

      return;
    }

    if (seconds < _minimumSeconds) return;

    // Only on a real change, and only per whole second.
    if (all[postId] == seconds) return;

    _touch(all, postId, seconds);
    _trim(all);

    await _flush(all);
  }

  /// Writes a value and moves it to the end of the map.
  ///
  /// Dart maps keep insertion order and jsonEncode writes them in that
  /// order, so re-inserting is what makes the order mean "least
  /// recently touched first" - which is the only thing [_trim] has to
  /// go on. Storing a timestamp per video would be a second number to
  /// keep correct for a decision that is made once every few hundred
  /// videos.
  static void _touch(Map<String, int> all, String postId, int value) {
    all
      ..remove(postId)
      ..[postId] = value;
  }

  /// Keeps the store down to [_maxEntries], oldest out first.
  ///
  /// Finished marks go before positions, whatever their age: a
  /// "Watched" note is a nicety, where losing a resume point is
  /// something somebody would actually notice - they would come back
  /// to a video and find it starting again from the beginning.
  static void _trim(Map<String, int> all) {
    var excess = all.length - _maxEntries;

    if (excess <= 0) return;

    final doomed = <String>{};

    for (final finishedOnly in [true, false]) {
      for (final entry in all.entries) {
        if (excess == 0) break;
        if (doomed.contains(entry.key)) continue;
        if (finishedOnly && entry.value != finished) continue;

        doomed.add(entry.key);
        excess--;
      }
    }

    all.removeWhere((key, _) => doomed.contains(key));
  }

  /// Forgets one video, for a "start from the beginning" control.
  static Future<void> clear(String postId) async {
    final all = await _all();

    if (all.remove(postId) != null) await _flush(all);
  }

  static Future<void> _flush(Map<String, int> all) async {
    _cache = all;

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_key, jsonEncode(all));
    } catch (e) {
      // The in-memory copy still works for this session.
      debugPrint('[watch] could not save progress: $e');
    }
  }

  @visibleForTesting
  static void resetForTest() => _cache = null;
}
