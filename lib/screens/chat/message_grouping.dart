/// How consecutive messages are grouped into blocks in a thread.
///
/// Pulled out of ChatScreen because the list it serves is `reverse: true`:
/// index 0 is the newest message and sits at the BOTTOM of the screen, so
/// "the message above this one" is `i + 1` and "below" is `i - 1`. Getting
/// that backwards draws the avatar on the wrong end of a block and the
/// timestamp on the wrong message — wrong in a way that still renders, so
/// nothing fails and nobody notices until a screenshot looks odd.
///
/// Plain functions over two values rather than methods on ChatMessage, so
/// the rules can be tested without a Supabase client in the room.
library;

/// How long a gap before a message starts its own block rather than
/// continuing the last one.
///
/// A reply hours later belongs apart, with its own timestamp, instead of
/// being glued to the end of the morning's conversation.
const Duration kChatRunGap = Duration(minutes: 5);

/// Whether a message from [laterSender] at [laterAt] continues the block
/// started by [earlierSender] at [earlierAt].
bool continuesRun({
  required String earlierSender,
  required DateTime earlierAt,
  required String laterSender,
  required DateTime laterAt,
}) {
  if (earlierSender != laterSender) return false;

  // abs(), because nothing guarantees the pair arrives in order: a message
  // sent optimistically can carry a local timestamp a moment ahead of the
  // one the server gives the message before it.
  return laterAt.difference(earlierAt).abs() < kChatRunGap;
}

/// Whether two instants fall on the same calendar day, locally.
bool sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Where one message sits in its block.
class RunPosition {
  /// First of a block: this one carries the sender's name.
  final bool startsRun;

  /// Last of a block: this one carries the avatar, the timestamp and the
  /// squared-off corner that points at the sender.
  final bool endsRun;

  /// A day separator belongs above this message.
  final bool startsDay;

  const RunPosition({
    required this.startsRun,
    required this.endsRun,
    required this.startsDay,
  });
}

/// Where the message at [index] sits, given the whole list newest-first.
///
/// [senderOf] and [timeOf] read the two fields this needs off whatever
/// the list holds, so this file does not have to know the message type.
RunPosition runPositionAt<T>(
  List<T> newestFirst,
  int index, {
  required String Function(T) senderOf,
  required DateTime Function(T) timeOf,
}) {
  final current = newestFirst[index];

  // Newest first, so the message drawn ABOVE this one is the older one,
  // at a higher index.
  final above = index + 1 < newestFirst.length ? newestFirst[index + 1] : null;
  final below = index > 0 ? newestFirst[index - 1] : null;

  final startsRun =
      above == null ||
      !continuesRun(
        earlierSender: senderOf(above),
        earlierAt: timeOf(above),
        laterSender: senderOf(current),
        laterAt: timeOf(current),
      );

  final endsRun =
      below == null ||
      !continuesRun(
        earlierSender: senderOf(current),
        earlierAt: timeOf(current),
        laterSender: senderOf(below),
        laterAt: timeOf(below),
      );

  final startsDay =
      above == null || !sameCalendarDay(timeOf(above), timeOf(current));

  return RunPosition(
    startsRun: startsRun,
    endsRun: endsRun,
    startsDay: startsDay,
  );
}
