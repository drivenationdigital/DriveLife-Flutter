import 'package:drivelife/screens/chat/inbox_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pills above the inbox.
///
/// Small rules, but the one that matters is the empty state: a filter
/// that hides everything and then says "No messages yet" is telling the
/// user something untrue about their inbox, and the way out of it — tap
/// All — is not discoverable unless the copy names the filter.
void main() {
  bool matches(InboxFilter f, {bool group = false, int unread = 0}) =>
      matchesInboxFilter(f, isGroup: group, unreadCount: unread);

  group('All', () {
    test('keeps everything', () {
      expect(matches(InboxFilter.all), isTrue);
      expect(matches(InboxFilter.all, group: true), isTrue);
      expect(matches(InboxFilter.all, unread: 9), isTrue);
      expect(matches(InboxFilter.all, group: true, unread: 9), isTrue);
    });
  });

  group('Unread', () {
    test('keeps a conversation with anything waiting', () {
      expect(matches(InboxFilter.unread, unread: 1), isTrue);
      expect(matches(InboxFilter.unread, unread: 99), isTrue);
    });

    test('drops one with nothing waiting', () {
      expect(matches(InboxFilter.unread), isFalse);
      expect(matches(InboxFilter.unread, group: true), isFalse);
    });

    test('does not care whether it is a group', () {
      expect(matches(InboxFilter.unread, group: true, unread: 2), isTrue);
    });
  });

  group('Groups', () {
    test('keeps groups, read or not', () {
      expect(matches(InboxFilter.groups, group: true), isTrue);
      expect(matches(InboxFilter.groups, group: true, unread: 3), isTrue);
    });

    test('drops one-to-one conversations', () {
      expect(matches(InboxFilter.groups), isFalse);
      expect(matches(InboxFilter.groups, unread: 5), isFalse);
    });
  });

  group('the empty state', () {
    test('every filter has its own line', () {
      final lines = InboxFilter.values.map(emptyInboxMessage).toSet();

      expect(
        lines,
        hasLength(InboxFilter.values.length),
        reason: 'two filters share an empty message, so one of them lies',
      );
    });

    test('only All claims the inbox is empty', () {
      // The specific wrong thing: "No messages yet" under Unread, with
      // four read conversations sitting behind the filter.
      expect(emptyInboxMessage(InboxFilter.all), contains('No messages'));

      for (final f in InboxFilter.values.where((f) => f != InboxFilter.all)) {
        expect(
          emptyInboxMessage(f),
          isNot(contains('No messages yet')),
          reason: '$f would claim the whole inbox is empty',
        );
      }
    });
  });

  test('every filter has a label, and none repeat', () {
    final labels = InboxFilter.values.map((f) => f.label).toList();

    expect(labels.every((l) => l.isNotEmpty), isTrue);
    expect(labels.toSet(), hasLength(labels.length));
  });
}
