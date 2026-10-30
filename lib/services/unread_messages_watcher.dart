import 'dart:async';

import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the unread-message badge current while the inbox is closed.
///
/// It used not to need anything. The inbox was a section of Home, so it
/// was built into the IndexedStack from launch and its InboxNotifier sat
/// there pushing counts into UnreadCountProvider whether you were
/// looking at it or not.
///
/// Moving Messages out of the header tabs and into a pushed screen took
/// that away: the notifier is now created when the screen opens and
/// disposed when it closes, so the badge only changed if you went and
/// looked — which is the one moment it is of no use.
///
/// This is the part of that notifier worth keeping alive: one number,
/// refreshed when a message arrives.
class UnreadMessagesWatcher {
  final String myUserId;
  final UnreadCountProvider provider;
  final InboxRepository _repo;

  RealtimeChannel? _channel;

  /// Collapses a burst of inserts into one fetch.
  ///
  /// A group chat waking up delivers several rows in a second, and each
  /// one would otherwise cost a full get_inbox.
  Timer? _debounce;

  bool _disposed = false;

  UnreadMessagesWatcher({
    required this.myUserId,
    required this.provider,
    InboxRepository? repo,
  }) : _repo = repo ?? InboxRepository();

  /// Fetch once, then follow.
  Future<void> start() async {
    await refresh();
    if (_disposed) return;

    // No filter on the subscription. Realtime filters one column of one
    // table, and "messages in conversations I am part of" is a join it
    // cannot express — so this listens to inserts the database is
    // willing to show, which row level security already narrows to this
    // user's conversations. Without that policy in place it would be
    // every message in the project.
    _channel = SupabaseConfig.client.channel('unread-$myUserId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) => _schedule(),
      )
      ..subscribe();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), refresh);
  }

  /// Re-read the total. Safe to call from anywhere, any number of times.
  Future<void> refresh() async {
    if (_disposed) return;

    try {
      final previews = await _repo.getInbox(myUserId);
      if (_disposed) return;

      provider.update(previews.fold<int>(0, (sum, p) => sum + p.unreadCount));
    } catch (e) {
      // A stale badge is better than a crash on a screen that has
      // nothing to do with messaging.
      debugPrint('[Unread] refresh failed: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();

    final channel = _channel;
    _channel = null;
    if (channel != null) SupabaseConfig.client.removeChannel(channel);
  }
}
