import 'package:drivelife/models/notification_group.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collapsing a run of notifications about the same thing into one row.
///
/// Worth testing hard because it is arithmetic dressed as a sentence:
/// "and 18 others" has to mean eighteen PEOPLE who are not the two
/// named, and every way of getting that wrong reads as a plausible
/// sentence about the wrong number.
void main() {
  Map<String, dynamic> like({
    required int actor,
    required String name,
    String entityType = 'post',
    int entityId = 91,
    String read = '1',
    String type = 'like',
  }) => {
    'type': type,
    'is_read': read,
    'date': '2026-11-20 09:00:00',
    'entity': {
      'entity_type': entityType,
      'entity_id': entityId,
      'initiator_data': {'id': actor, 'display_name': name},
    },
  };

  List<String> lines(List<dynamic> raw) =>
      groupNotifications(raw).map((g) => g.nameLine).toList();

  group('what gets collapsed', () {
    test('likes on one post become one row', () {
      final rows = groupNotifications([
        like(actor: 1, name: 'Ali'),
        like(actor: 2, name: 'Sam'),
        like(actor: 3, name: 'Jo'),
      ]);

      expect(rows.length, 1);
      expect(rows.first.members.length, 3);
      expect(rows.first.nameLine, 'Ali, Sam and 1 other');
    });

    test('likes on different posts stay apart', () {
      expect(
        lines([
          like(actor: 1, name: 'Ali', entityId: 91),
          like(actor: 2, name: 'Sam', entityId: 92),
        ]),
        ['Ali', 'Sam'],
      );
    });

    test('the same id on different entity types is not the same thing', () {
      // Post 91 and comment 91 come from different tables that know
      // nothing about each other, so the id alone proves nothing.
      expect(
        lines([
          like(actor: 1, name: 'Ali', entityType: 'post', entityId: 91),
          like(actor: 2, name: 'Sam', entityType: 'comment', entityId: 91),
        ]),
        ['Ali', 'Sam'],
      );
    });

    test('comments are never collapsed', () {
      // The words are the point. "and 18 others commented" is a
      // notification you have to open to learn anything from.
      final rows = groupNotifications([
        like(actor: 1, name: 'Ali', type: 'comment'),
        like(actor: 2, name: 'Sam', type: 'comment'),
      ]);

      expect(rows.length, 2);
    });

    test('follows are never collapsed', () {
      // The row has a Follow Back button on it, and there is no such
      // thing as following three people with one tap.
      final rows = groupNotifications([
        like(actor: 1, name: 'Ali', type: 'follow'),
        like(actor: 2, name: 'Sam', type: 'follow'),
      ]);

      expect(rows.length, 2);
    });
  });

  group('the sentence', () {
    List<Map<String, dynamic>> many(int n) => List.generate(
      n,
      (i) => like(actor: i + 1, name: 'P${i + 1}'),
    );

    test('one', () {
      expect(groupNotifications(many(1)).first.nameLine, 'P1');
    });

    test('two, joined by and, with no comma', () {
      expect(groupNotifications(many(2)).first.nameLine, 'P1 and P2');
    });

    test('three, where the tail is singular', () {
      expect(
        groupNotifications(many(3)).first.nameLine,
        'P1, P2 and 1 other',
      );
    });

    test('twenty, where the tail is everybody not named', () {
      // Two named, eighteen counted. Naming two and then saying "and
      // 20 others" is the classic off-by-two here.
      expect(
        groupNotifications(many(20)).first.nameLine,
        'P1, P2 and 18 others',
      );
    });
  });

  group('which pieces are bold', () {
    // Only the names. Bolding ", " and " and " made them look like
    // part of a name, on a line whose entire job is listing names.
    List<Map<String, dynamic>> many(int n) =>
        List.generate(n, (i) => like(actor: i + 1, name: 'P${i + 1}'));

    List<String> boldOf(int n) => groupNotifications(many(n))
        .first
        .nameChunks
        .where((c) => c.bold)
        .map((c) => c.text)
        .toList();

    List<String> plainOf(int n) => groupNotifications(many(n))
        .first
        .nameChunks
        .where((c) => !c.bold)
        .map((c) => c.text)
        .toList();

    test('two names are bold and the and is not', () {
      expect(boldOf(2), ['P1', 'P2']);
      expect(plainOf(2), [' and ']);
    });

    test('the comma and the tail are not bold either', () {
      expect(boldOf(20), ['P1', 'P2']);
      expect(plainOf(20), [', ', ' and 18 others']);
    });

    test('a lone name is bold and nothing else is there', () {
      expect(boldOf(1), ['P1']);
      expect(plainOf(1), isEmpty);
    });

    test('the pieces always rebuild the line exactly', () {
      // The tile slices the message at nameLine.length, so a chunk
      // that does not round-trip cuts the sentence in the wrong place.
      for (final n in [1, 2, 3, 20]) {
        final g = groupNotifications(many(n)).first;

        expect(g.nameChunks.map((c) => c.text).join(), g.nameLine);
      }
    });
  });

  group('the awkward ones', () {
    test('one person liking twice is one person', () {
      // Should not happen, and the row must not read "Ali and Ali".
      final rows = groupNotifications([
        like(actor: 1, name: 'Ali'),
        like(actor: 1, name: 'Ali'),
      ]);

      expect(rows.length, 1);
      expect(rows.first.nameLine, 'Ali');

      // And it is not drawn as a group: there is nobody to be "other"
      // than, so it reads as the single notification it is.
      expect(rows.first.isGrouped, isFalse);
    });

    test('a missing name is not a missing person', () {
      expect(
        groupNotifications([
          like(actor: 1, name: ''),
          like(actor: 2, name: 'Sam'),
        ]).first.nameLine,
        'Someone and Sam',
      );
    });

    test('rows with no id are kept rather than deduped away', () {
      // Nothing can be deduped on, and a name shown twice is better
      // than a person dropped out of a count.
      final rows = groupNotifications([
        {
          'type': 'like',
          'entity': {
            'entity_type': 'post',
            'entity_id': 91,
            'initiator_data': {'display_name': 'Ali'},
          },
        },
        {
          'type': 'like',
          'entity': {
            'entity_type': 'post',
            'entity_id': 91,
            'initiator_data': {'display_name': 'Sam'},
          },
        },
      ]);

      expect(rows.first.nameLine, 'Ali and Sam');
    });

    test('rubbish in the list is skipped, not crashed on', () {
      expect(groupNotifications(['nonsense', 42, null]), isEmpty);
    });
  });

  group('what the row shows', () {
    test('the newest stands for the group', () {
      final rows = groupNotifications([
        like(actor: 1, name: 'Ali'),
        like(actor: 2, name: 'Sam'),
      ]);

      // First in, which is newest in the list as it arrives. Its
      // avatar and its timestamp are the row's.
      expect(
        rows.first.newest['entity']['initiator_data']['display_name'],
        'Ali',
      );
    });

    test('one unread among them makes the row unread', () {
      // Drawn as read because the oldest of nineteen had been seen
      // would hide the eighteen that had not.
      final rows = groupNotifications([
        like(actor: 1, name: 'Ali', read: '1'),
        like(actor: 2, name: 'Sam', read: '0'),
      ]);

      expect(rows.first.anyUnread, isTrue);
    });

    test('all read is read', () {
      final rows = groupNotifications([
        like(actor: 1, name: 'Ali', read: '1'),
        like(actor: 2, name: 'Sam', read: '1'),
      ]);

      expect(rows.first.anyUnread, isFalse);
    });

    test('order is kept, and a group sits where its newest did', () {
      // A second like does not drag the post up the list past things
      // that happened after the first one.
      expect(
        lines([
          like(actor: 1, name: 'Ali', entityId: 91),
          like(actor: 2, name: 'Sam', entityId: 92),
          like(actor: 3, name: 'Jo', entityId: 91),
        ]),
        ['Ali and Jo', 'Sam'],
      );
    });
  });
}
