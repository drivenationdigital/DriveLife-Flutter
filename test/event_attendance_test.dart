import 'package:drivelife/models/event_attendance.dart';
import 'package:flutter_test/flutter_test.dart';

/// The line under "I'm going".
///
/// A count of strangers is close to worthless — "412 going" tells you
/// the event exists, which you knew. What decides whether somebody
/// drives an hour to a meet is whether they will know anyone there, so
/// the names lead and the number follows.
///
/// Which makes this arithmetic: "and 3 others" has to mean three people
/// who are neither you nor already named, and getting that wrong is the
/// classic off-by-one in this sort of line.
void main() {
  Attendee person(String name) => Attendee(id: name.hashCode, name: name);

  EventAttendance at({
    bool going = false,
    int count = 0,
    List<Attendee> friends = const [],
  }) => EventAttendance(
    going: going,
    count: count,
    friends: friends,
    friendCount: friends.length,
  );

  group('nobody you know', () {
    test('an event with nobody going says nothing at all', () {
      // Not "0 going". An empty number is worse than an absent line.
      expect(at().summary, '');
    });

    test('one stranger', () {
      expect(at(count: 1).summary, '1 person is going');
    });

    test('several strangers', () {
      expect(at(count: 12).summary, '12 people are going');
    });

    test('just you', () {
      expect(at(going: true, count: 1).summary, "You're going");
    });

    test('you and one stranger', () {
      expect(at(going: true, count: 2).summary, 'You and 1 other are going');
    });

    test('you and several strangers', () {
      expect(at(going: true, count: 9).summary, 'You and 8 others are going');
    });
  });

  group('people you follow', () {
    test('one friend, nobody else', () {
      expect(
        at(count: 1, friends: [person('Sam Hall')]).summary,
        'Sam is going',
      );
    });

    test('two friends, nobody else', () {
      expect(
        at(count: 2, friends: [person('Sam Hall'), person('Alex Reed')]).summary,
        'Sam and Alex are going',
      );
    });

    test('one friend and strangers', () {
      expect(
        at(count: 5, friends: [person('Sam Hall')]).summary,
        'Sam and 4 others are going',
      );
    });

    test('one friend and exactly one stranger', () {
      expect(
        at(count: 2, friends: [person('Sam Hall')]).summary,
        'Sam and 1 other are going',
      );
    });

    test('you, a friend, and strangers', () {
      // Five going: you, Sam, and three others. You are not an "other".
      expect(
        at(going: true, count: 5, friends: [person('Sam Hall')]).summary,
        'You, Sam and 3 others are going',
      );
    });

    test('you and one friend, nobody else', () {
      expect(
        at(going: true, count: 2, friends: [person('Sam Hall')]).summary,
        'You and Sam are going',
      );
    });

    test('only the first two friends are named', () {
      // A line, not a directory. The rest become part of the count.
      final summary = at(
        count: 6,
        friends: [person('Sam Hall'), person('Alex Reed'), person('Jo Diaz')],
      ).summary;

      expect(summary, 'Sam, Alex and 4 others are going');
      expect(summary.contains('Jo'), isFalse);
    });
  });

  group('names', () {
    test('a first name is used, not the whole thing', () {
      // "Samuel Hendricks-Whitby and Alexandra Bell are going" is a
      // line that wraps; first names make a sentence.
      expect(person('Samuel Hendricks-Whitby').firstName, 'Samuel');
    });

    test('a single name is left alone', () {
      expect(person('Kesh').firstName, 'Kesh');
    });

    test('no display name falls back to the username', () {
      const attendee = Attendee(name: '', username: 'kesh_xn');

      expect(attendee.firstName, 'kesh_xn');
    });

    test('a nameless attendee does not produce a blank name', () {
      // They are counted rather than named, so the line never reads
      // " and 3 others are going".
      final summary = at(count: 4, friends: [const Attendee(id: 7)]).summary;

      expect(summary, '4 people are going');
    });
  });

  group('counting the others', () {
    test('you are not one of them', () {
      expect(at(going: true, count: 5).others, 4);
    });

    test('nor are you when you are the only one', () {
      expect(at(going: true, count: 1).others, 0);
    });

    test('everyone is an other when you are not going', () {
      expect(at(count: 5).others, 5);
    });

    test('a count that disagrees with going does not go negative', () {
      // The optimistic toggle can briefly produce this before the
      // server's recount lands.
      expect(at(going: true, count: 0).others, 0);
    });
  });

  group('a ticket is not a toggle', () {
    test('a ticket holder cannot change it', () {
      const held = EventAttendance(going: true, count: 5, viaTicket: true);

      expect(held.canToggle, isFalse);
    });

    test('somebody who merely tapped Going can', () {
      const tapped = EventAttendance(going: true, count: 5);

      expect(tapped.canToggle, isTrue);
    });

    test('and so can anybody not going yet', () {
      // A free event sells no tickets, so nobody on one is ever
      // locked — the two cases are the same rule.
      expect(const EventAttendance(count: 5).canToggle, isTrue);
    });

    test('it survives the optimistic toggle', () {
      // copyWith is what the screen uses to show the change before the
      // server answers. Dropping viaTicket there would unlock the
      // button for a frame, which is long enough to tap.
      const held = EventAttendance(going: true, count: 5, viaTicket: true);

      expect(held.copyWith(going: false, count: 4).viaTicket, isTrue);
    });

    test('it comes off the payload', () {
      final found = EventAttendance.fromMap(const {
        'going': true,
        'count': 3,
        'via_ticket': true,
      });

      expect(found.viaTicket, isTrue);
      expect(found.canToggle, isFalse);
    });

    test('a server that does not send it leaves the button working', () {
      // An older deployment. Defaulting to locked would freeze the
      // feature for everyone until the API caught up.
      final found = EventAttendance.fromMap(const {'going': true, 'count': 3});

      expect(found.viaTicket, isFalse);
      expect(found.canToggle, isTrue);
    });
  });

  group('reading the payload', () {
    test('the ordinary case', () {
      final found = EventAttendance.fromMap(const {
        'going': true,
        'count': 12,
        'friend_count': 2,
        'friends': [
          {'id': 1, 'name': 'Sam Hall', 'username': 'sam', 'image': ''},
          {'id': 2, 'name': 'Alex Reed', 'username': 'alex', 'image': ''},
        ],
      });

      expect(found.going, isTrue);
      expect(found.count, 12);
      expect(found.friends, hasLength(2));
      expect(found.summary, 'You, Sam, Alex and 9 others are going');
    });

    test('counts arriving as strings still count', () {
      // WordPress returns integers as strings more often than not.
      final found = EventAttendance.fromMap(const {
        'going': false,
        'count': '7',
        'friend_count': '0',
      });

      expect(found.count, 7);
    });

    test('an empty payload is the empty state', () {
      final found = EventAttendance.fromMap(const {});

      expect(found.going, isFalse);
      expect(found.count, 0);
      expect(found.summary, '');
    });
  });
}
