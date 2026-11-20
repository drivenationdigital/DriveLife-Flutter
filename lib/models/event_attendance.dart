/// Who is going to an event.
///
/// ── WHY THE FRIENDS COME FIRST ──────────────────────────────────────
///
/// A count of strangers is close to worthless. "412 going" tells you
/// the event exists, which you already knew, because you are looking at
/// it. What decides whether somebody drives an hour to a car meet is
/// whether anybody they know will be there.
///
/// So [friends] — the people you follow who are going — is the headline
/// and [count] is the footnote.
class EventAttendance {
  /// Whether YOU are going.
  final bool going;

  /// Everybody going, you included.
  final int count;

  /// People you follow who are going. Capped by the server at a
  /// handful, since this is a line of text and not a directory.
  final List<Attendee> friends;

  /// How many people you follow are going, including any beyond the
  /// few named. [friends] is a sample; this is the number.
  final int friendCount;

  /// You are going because you bought a ticket.
  ///
  /// ── WHY THIS LOCKS THE BUTTON ───────────────────────────────────
  ///
  /// Somebody who has paid is going whether or not a row in our table
  /// says so. Offering them a control that reads "You're going" and
  /// un-sets on tap invites exactly one question — have I just
  /// cancelled my ticket? They have not, and they cannot. But a button
  /// that looks like it might is worse than no button.
  ///
  /// The server refuses the un-set too, so this is which of two true
  /// things to show rather than the only thing stopping it.
  final bool viaTicket;

  const EventAttendance({
    this.going = false,
    this.count = 0,
    this.friends = const [],
    this.friendCount = 0,
    this.viaTicket = false,
  });

  static const EventAttendance none = EventAttendance();

  /// Can this person change their mind here?
  ///
  /// Everyone except ticket holders. A free event sells no tickets, so
  /// nobody on one is ever locked — the two cases are the same rule.
  bool get canToggle => !viaTicket;

  /// Everybody except you.
  ///
  /// What "and 3 others" has to count. Including yourself in it is the
  /// classic off-by-one in this sort of line — you know you are going.
  int get others => going ? (count - 1).clamp(0, count) : count;

  /// "You and Sam are going", "Sam, Alex and 4 others are going".
  ///
  /// ── BUILT AS A LIST, NOT AS CASES ───────────────────────────────
  ///
  /// Written as a branch per shape it came out as "You, Sam are going"
  /// and "Sam and Alex and 4 others are going" — each individually
  /// defensible and both obviously wrong read aloud. There are only
  /// three kinds of part: you, the people you follow, and a number for
  /// everyone else. Assembling those and punctuating once is the only
  /// version where every combination reads as English.
  ///
  /// Returns an empty string when there is nothing worth saying, so the
  /// caller leaves the row out rather than rendering "0 going".
  String get summary {
    // Two names at most. This is a line, not a directory; anybody
    // beyond that is counted instead.
    final names = friends
        .map((f) => f.firstName)
        .where((n) => n.isNotEmpty)
        .take(2)
        .toList();

    // Everybody going who is neither you nor named above.
    final rest = others - names.length;

    final parts = <String>[
      if (going) 'You',
      ...names,
      if (rest == 1) '1 other' else if (rest > 1) '$rest others',
    ];

    if (parts.isEmpty) return '';

    if (parts.length == 1) {
      if (going) return "You're going";

      // Nobody named, so the one part is a bare count — and "4 others"
      // is only "other" relative to somebody. With no names and no you,
      // there is nobody for them to be other than.
      if (names.isEmpty) {
        return count == 1 ? '1 person is going' : '$count people are going';
      }

      return '${parts.first} is going';
    }

    final last = parts.removeLast();

    return '${parts.join(', ')} and $last are going';
  }

  /// [meId] is the signed-in user, so they can be kept out of
  /// [friends].
  ///
  /// ── WHY THE CLIENT CHECKS SOMETHING THE SERVER ALREADY DOES ─────
  ///
  /// It does now. It did not when an account appeared in its own
  /// follow list, and the line came out as "You and drivelife are
  /// going" for drivelife — one person named twice, in a sentence
  /// whose only job is to say who ELSE will be there.
  ///
  /// This is the cheaper half of that fix and the half that does not
  /// wait for a deploy. It also holds for any future list that arrives
  /// with you in it, which is the sort of thing that comes back.
  ///
  /// Zero means nobody is signed in, and then nothing is filtered:
  /// there is no "you" in the sentence to be duplicated.
  factory EventAttendance.fromMap(Map<String, dynamic> map, {int meId = 0}) {
    int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

    final named = ((map['friends'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Attendee.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    final friends = named
        .where((a) => meId == 0 || a.id != meId)
        .toList();

    // Brought down by however many were dropped, so a count that was
    // counting you stops. clamp because a server that sends a count
    // smaller than its own list should not produce a negative one.
    final friendCount =
        (asInt(map['friend_count']) - (named.length - friends.length))
            .clamp(0, 1 << 30);

    return EventAttendance(
      going: map['going'] == true,
      count: asInt(map['count']),
      friends: friends,
      friendCount: friendCount,
      viaTicket: map['via_ticket'] == true,
    );
  }

  EventAttendance copyWith({bool? going, int? count}) => EventAttendance(
    going: going ?? this.going,
    count: count ?? this.count,
    friends: friends,
    friendCount: friendCount,
    viaTicket: viaTicket,
  );
}

/// One person going to an event.
class Attendee {
  final int id;
  final String name;
  final String username;
  final String image;

  const Attendee({
    this.id = 0,
    this.name = '',
    this.username = '',
    this.image = '',
  });

  /// What to call them in a sentence.
  ///
  /// A first name, because "Sam and Alex are going" is a sentence and
  /// "Samuel Hendricks-Whitby and Alexandra Bell are going" is a line
  /// that wraps. Falls back to the username, which is how somebody
  /// with no display name is known everywhere else in the app.
  String get firstName {
    final trimmed = name.trim();

    if (trimmed.isEmpty) return username.trim();

    return trimmed.split(RegExp(r'\s+')).first;
  }

  factory Attendee.fromMap(Map<String, dynamic> map) => Attendee(
    id: map['id'] is num
        ? (map['id'] as num).toInt()
        : int.tryParse('${map['id']}') ?? 0,
    name: '${map['name'] ?? ''}',
    username: '${map['username'] ?? ''}',
    image: '${map['image'] ?? ''}',
  );
}
