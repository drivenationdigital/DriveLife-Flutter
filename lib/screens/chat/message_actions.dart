/// The rules behind the long-press menu: what may be done to a message,
/// and how its reactions are counted.
///
/// Its own file, taking plain values rather than a ChatMessage, so the
/// rules can be read and tested without a Supabase client in the room —
/// the same reason message_grouping.dart exists.
library;

/// How long after sending a message may still be taken back.
///
/// MUST MATCH the interval in the "messages: delete my own, briefly"
/// policy in supabase/sql/message-reactions-and-delete.sql. The policy is
/// what enforces this; the number here only decides whether the app
/// bothers to offer the option. If the two drift, the menu offers a
/// Delete that the database silently refuses — an update that matches no
/// row is not an error, so nothing would surface except a message that
/// stubbornly stays.
///
/// Fifteen minutes: long enough to catch the message you regret, short
/// enough that a conversation somebody has already read stays a record of
/// what was said.
const Duration kMessageDeleteWindow = Duration(minutes: 15);

/// A reaction as it is drawn: one emoji, how many people, whether you are
/// one of them.
class ReactionSummary {
  final String emoji;
  final int count;

  /// Whether the signed-in user is among them — the bubble outlines it,
  /// and tapping removes rather than adds.
  final bool mine;

  const ReactionSummary({
    required this.emoji,
    required this.count,
    required this.mine,
  });

  @override
  bool operator ==(Object other) =>
      other is ReactionSummary &&
      other.emoji == emoji &&
      other.count == count &&
      other.mine == mine;

  @override
  int get hashCode => Object.hash(emoji, count, mine);

  @override
  String toString() => 'ReactionSummary($emoji x$count${mine ? ', mine' : ''})';
}

/// Whether [myUserId] may still take this message back.
///
/// False for anybody else's message at any age, and false for an already
/// deleted one — a tombstone has nothing left to remove.
bool canDeleteMessage({
  required String senderId,
  required DateTime createdAt,
  required String myUserId,
  required bool alreadyDeleted,
  DateTime? now,
}) {
  if (alreadyDeleted) return false;
  if (senderId != myUserId) return false;

  final age = (now ?? DateTime.now()).difference(createdAt);

  // Negative ages happen: an optimistic message carries a local clock
  // that can sit a moment ahead of the server's. Still inside the window,
  // which is what isNegative covers — comparing straight against the
  // duration would say no.
  return age.isNegative || age <= kMessageDeleteWindow;
}

/// Whether a message can be reacted to at all.
///
/// Deleted messages cannot. Your own can — people react to their own
/// messages and it is not worth forbidding.
bool canReactToMessage({required bool alreadyDeleted}) => !alreadyDeleted;

/// Count a message's reactions into what the bubble draws.
///
/// Ordered by count, then by the emoji itself so the row does not shuffle
/// between rebuilds when two are level. Both matter: a list that reorders
/// under the thumb is worse than one in an arbitrary but stable order.
List<ReactionSummary> summariseReactions(
  Iterable<({String emoji, String userId})> reactions,
  String myUserId,
) {
  final counts = <String, int>{};
  final mine = <String>{};

  for (final r in reactions) {
    counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    if (r.userId == myUserId) mine.add(r.emoji);
  }

  final out = counts.entries
      .map(
        (e) => ReactionSummary(
          emoji: e.key,
          count: e.value,
          mine: mine.contains(e.key),
        ),
      )
      .toList();

  out.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.emoji.compareTo(b.emoji);
  });

  return out;
}

/// The emoji offered on a long press.
///
/// Six, because the row has to fit across a phone beside a close button
/// without scrolling, and because a picker with everything in it turns a
/// one-tap gesture into a decision.
const List<String> kQuickReactions = ['❤️', '😂', '😮', '😢', '👍', '🔥'];
