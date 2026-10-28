import 'dart:io';

import 'package:drivelife/screens/chat/message_actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// The long-press rules.
///
/// Arithmetic and sorting, so cheap to pin — and worth pinning, because
/// the delete window exists twice. The real one is an RLS policy; this is
/// only the app deciding whether to offer the option. If they drift, the
/// menu offers a Delete that the database refuses by matching no row,
/// which is not an error and therefore surfaces as nothing at all except
/// a message that will not go away.
void main() {
  final sentAt = DateTime(2026, 10, 28, 12, 0);

  bool canDelete({
    String sender = 'me',
    String me = 'me',
    bool deleted = false,
    Duration age = Duration.zero,
  }) => canDeleteMessage(
    senderId: sender,
    createdAt: sentAt,
    myUserId: me,
    alreadyDeleted: deleted,
    now: sentAt.add(age),
  );

  group('taking a message back', () {
    test('mine, just sent', () {
      expect(canDelete(), isTrue);
    });

    test('mine, inside the window', () {
      expect(
        canDelete(age: kMessageDeleteWindow - const Duration(minutes: 1)),
        isTrue,
      );
      expect(canDelete(age: kMessageDeleteWindow), isTrue);
    });

    test('mine, past the window', () {
      expect(
        canDelete(age: kMessageDeleteWindow + const Duration(seconds: 1)),
        isFalse,
      );
      expect(canDelete(age: const Duration(days: 1)), isFalse);
    });

    test('somebody else\'s, however new', () {
      expect(canDelete(sender: 'them'), isFalse);
      expect(
        canDelete(sender: 'them', age: const Duration(seconds: 1)),
        isFalse,
      );
    });

    test('already deleted', () {
      // A tombstone has nothing left to take back, and offering Delete on
      // one is an update that matches no row.
      expect(canDelete(deleted: true), isFalse);
    });

    test('a message from the near future is still mine to delete', () {
      // Optimistic sends carry a local clock, which can sit a moment
      // ahead of the server's. Comparing the duration straight against
      // the window says no to a negative age; this says yes.
      expect(canDelete(age: const Duration(seconds: -2)), isTrue);
    });
  });

  group('reacting', () {
    test('not to a deleted message', () {
      expect(canReactToMessage(alreadyDeleted: true), isFalse);
      expect(canReactToMessage(alreadyDeleted: false), isTrue);
    });
  });

  group('counting reactions', () {
    List<ReactionSummary> summarise(List<(String, String)> rows) =>
        summariseReactions(rows.map((r) => (emoji: r.$1, userId: r.$2)), 'me');

    test('nothing in, nothing out', () {
      expect(summarise([]), isEmpty);
    });

    test('one emoji from several people counts once, with a total', () {
      final out = summarise([('❤️', 'a'), ('❤️', 'b'), ('❤️', 'c')]);

      expect(out, [const ReactionSummary(emoji: '❤️', count: 3, mine: false)]);
    });

    test('mine is marked', () {
      final out = summarise([('❤️', 'a'), ('❤️', 'me')]);

      expect(out.single.mine, isTrue);
      expect(out.single.count, 2);
    });

    test('mine on one emoji does not mark another', () {
      final out = summarise([('❤️', 'me'), ('😂', 'a')]);

      expect(out.firstWhere((r) => r.emoji == '❤️').mine, isTrue);
      expect(out.firstWhere((r) => r.emoji == '😂').mine, isFalse);
    });

    test('ordered by count, commonest first', () {
      final out = summarise([
        ('😂', 'a'),
        ('❤️', 'b'),
        ('❤️', 'c'),
        ('❤️', 'd'),
        ('👍', 'e'),
        ('👍', 'f'),
      ]);

      expect(out.map((r) => r.emoji).toList(), ['❤️', '👍', '😂']);
    });

    test('a tie keeps a stable order', () {
      // Without the tie-break the row reorders between rebuilds, which
      // moves a target out from under a thumb already on its way down.
      final rows = [('😂', 'a'), ('❤️', 'b'), ('👍', 'c')];

      final first = summarise(rows).map((r) => r.emoji).toList();
      final again = summarise(
        rows.reversed.toList(),
      ).map((r) => r.emoji).toList();

      expect(again, first);
    });
  });

  test('the app window and the RLS policy agree', () {
    // The one that bites. The delete window exists twice: here, deciding
    // whether to offer the option, and in the policy, deciding whether
    // to allow it. The policy wins — and it refuses by matching no row,
    // which is not an error. So if this number grows past the policy's,
    // the menu offers a Delete that silently does nothing and the only
    // symptom is a message that will not go away.
    const sql = 'supabase/sql/message-reactions-and-delete.sql';
    final file = File(sql);

    expect(
      file.existsSync(),
      isTrue,
      reason: '$sql is where the policy lives; if it moved, move this',
    );

    final match = RegExp(
      r"created_at > now\(\) - interval '(\d+) minutes'",
    ).firstMatch(file.readAsStringSync());

    expect(
      match,
      isNotNull,
      reason: 'the delete policy no longer reads as a minutes interval',
    );

    expect(
      int.parse(match!.group(1)!),
      kMessageDeleteWindow.inMinutes,
      reason:
          'the policy allows a different window from the one the app '
          'offers',
    );
  });

  test('the quick row fits on a phone', () {
    // Six, laid out beside a close button without scrolling. More than
    // this and the row either scrolls or the targets get too small to
    // hit, and a long-press menu that needs aiming is worse than a list.
    expect(kQuickReactions, hasLength(6));
    expect(kQuickReactions.toSet(), hasLength(6), reason: 'no duplicates');
  });
}
