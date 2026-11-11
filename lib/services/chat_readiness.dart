import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Whether a conversation can be sealed yet.
///
/// ── THE PROBLEM THIS SOLVES ─────────────────────────────────────────
///
/// Encryption is decided by the sender; readability belongs to the
/// receiver. Seal a message to somebody on an older build and
/// `dl1.<key>.<base64>` sits in their thread for good — their app reads
/// `content` straight out of Supabase and has never heard of an
/// envelope. Nothing server-side can undo it, because the damage is in
/// an app that already shipped.
///
/// The alternative was forcing everybody to update before anybody got
/// encryption. Instead each client records that it can open an
/// envelope, and a sender seals only when EVERY participant says so.
/// Threads convert themselves as people update, and somebody who never
/// updates keeps plaintext rather than having their chat broken.
///
/// See supabase/sql/chat-crypto-readiness.sql.
///
/// ── WHY CACHING IS SAFE HERE ────────────────────────────────────────
///
/// The dangerous mistake is believing somebody can read an envelope
/// when they cannot. That needs a client to go BACKWARDS — to have set
/// the flag and then be running an older build — which app stores do
/// not allow. So a cached "yes" cannot rot into a wrong answer.
///
/// A stale "no" is harmless: the thread sends plaintext a little longer
/// than it needed to, and picks the change up next launch.
class ChatReadiness {
  const ChatReadiness._();

  static const String _table = 'chat_crypto_readiness';

  /// Answers already worked out, keyed by conversation id.
  ///
  /// Only ever grows within a session. See the note above on why a
  /// cached true cannot become wrong.
  static final Map<String, bool> _sealable = <String, bool>{};

  /// In-flight lookups, so a thread that sends several messages quickly
  /// does not run the same two queries several times.
  static final Map<String, Future<bool>> _inFlight = <String, Future<bool>>{};

  /// The user id already announced, so this runs once per session
  /// rather than on every chat screen.
  static String? _announcedFor;

  /// Records that this build can open an envelope.
  ///
  /// Never throws and never blocks anything: a failure here means other
  /// people keep sending this user plaintext, which is exactly today's
  /// behaviour.
  ///
  /// Call after the Supabase session is established — the row is
  /// written as the signed-in user and RLS refuses it otherwise.
  static Future<void> announce(String myUserId) async {
    if (myUserId.isEmpty || _announcedFor == myUserId) return;

    // Set before the await, so two screens racing at startup do not both
    // write. A failure below clears it again so the next attempt runs.
    _announcedFor = myUserId;

    try {
      String? build;

      try {
        build = (await PackageInfo.fromPlatform()).version;
      } catch (_) {
        // Only ever for reading by hand. Not worth failing over.
      }

      await SupabaseConfig.client.from(_table).upsert({
        'user_id': myUserId,
        'can_read': true,
        if (build != null) 'app_build': build,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      _announcedFor = null;
      debugPrint('[ChatReadiness] could not announce: $e');
    }
  }

  /// Whether every participant can open an envelope.
  ///
  /// False on any doubt — a missing row, a thread that cannot be read,
  /// a table that does not exist yet, a network failure. Every one of
  /// those means "send plaintext", which is what the app did before
  /// encryption existed and is never the wrong answer, only sometimes a
  /// conservative one.
  static Future<bool> everyoneCanRead(String conversationId) {
    if (conversationId.isEmpty) return Future<bool>.value(false);

    final cached = _sealable[conversationId];
    if (cached != null) return Future<bool>.value(cached);

    return _inFlight[conversationId] ??= _resolve(conversationId)
        .whenComplete(() => _inFlight.remove(conversationId));
  }

  /// How long the two lookups get before the answer is "plaintext".
  ///
  /// sendMessage awaits this, so without a bound a stalled connection
  /// would mean a message that never sends. Sealing is the thing worth
  /// giving up here: a plaintext message that arrives beats an
  /// encrypted one that does not.
  ///
  /// A timeout is NOT cached — it lands in the catch below, which
  /// returns false without recording it, so the next send tries again.
  static const Duration _timeout = Duration(seconds: 6);

  static Future<bool> _resolve(String conversationId) async {
    try {
      final conversation = await SupabaseConfig.client
          .from('conversations')
          .select('participant_ids')
          .eq('id', conversationId)
          .maybeSingle()
          .timeout(_timeout);

      if (conversation == null) return false;

      final participants = <String>{
        ...List<dynamic>.from(
          conversation['participant_ids'] as List<dynamic>? ??
              const <dynamic>[],
        ).map((dynamic id) => '$id'),
      }..removeWhere((String id) => id.isEmpty);

      // A thread with nobody in it is a broken row, not a green light.
      if (participants.isEmpty) return false;

      final rows = await SupabaseConfig.client
          .from(_table)
          .select('user_id')
          .inFilter('user_id', participants.toList())
          .eq('can_read', true)
          .timeout(_timeout);

      final ready = <String>{
        ...List<dynamic>.from(rows as List<dynamic>).map(
          (dynamic row) => '${(row as Map<String, dynamic>)['user_id']}',
        ),
      };

      // containsAll rather than a length comparison: the query could
      // return a duplicate or an id that is not in this thread at all,
      // and either would make counts agree while the answer was wrong.
      final sealable = ready.containsAll(participants);

      _sealable[conversationId] = sealable;

      if (kDebugMode) {
        final waiting = participants.difference(ready);

        debugPrint(
          '[ChatReadiness] $conversationId — '
          '${sealable ? 'all ${participants.length} can read, sealing' : 'waiting on ${waiting.join(', ')}'}',
        );
      }

      return sealable;
    } catch (e) {
      // Most likely the table does not exist yet, which is precisely
      // when plaintext is the right answer.
      debugPrint('[ChatReadiness] lookup failed, sending plaintext: $e');
      return false;
    }
  }

  /// Drops what is remembered. For sign-out and account switching.
  static void forget() {
    _sealable.clear();
    _inFlight.clear();
    _announcedFor = null;
  }
}
