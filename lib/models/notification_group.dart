/// Collapsing a run of notifications about the same thing into one row.
///
/// ── WHY THIS IS A UI CONCERN AND NOTHING ELSE ───────────────────────
///
/// The rows stay exactly as they are in the database. Ten people liking
/// a post is ten facts, ten read flags and ten things the server may
/// later need to count, and collapsing them at the source would throw
/// nine of them away to save one line on a screen.
///
/// So this groups what has already arrived, for display, and the
/// grouping lives and dies with the list it was built from.
///
/// ── WHY ONLY LIKES ──────────────────────────────────────────────────
///
/// A like carries no information beyond who. Twenty of them on one post
/// is one fact said twenty times, and a feed that says it twenty times
/// buries everything else under it.
///
/// Everything else here carries something per row that grouping would
/// destroy:
///
///   comment   the words are the point, and "and 18 others commented"
///             is a notification you have to open to learn anything
///             from
///   tag       each tag is a different photo, in a different place
///   follow    the row has a Follow Back button on it, and there is no
///             such thing as following three people with one tap
///
/// Instagram draws the same line in the same place, for the same
/// reason.
library;

/// One run of the name line, and whether it is somebody's name.
///
/// The names are drawn in bold and everything joining them is not —
/// ", ", " and ", "18 others". Bolding the lot made the connectives
/// look like part of a name, which on a line of names is exactly the
/// thing a reader is trying to tell apart.
typedef NameChunk = ({String text, bool bold});

/// One row of the notifications list: a single notification, or several
/// about the same thing.
class NotificationGroup {
  /// Newest first, which is the order the list arrived in.
  final List<Map<String, dynamic>> members;

  const NotificationGroup(this.members);

  /// The one that stands for the group: its newest.
  ///
  /// Its avatar, its timestamp and its entity are what the row shows,
  /// so the row reads as "this just happened" rather than dating itself
  /// to whenever the first of them did.
  Map<String, dynamic> get newest => members.first;

  /// Whether this is more than one notification.
  ///
  /// False for a group of several notifications from ONE person — see
  /// [actorNames]. There is nobody to say "and 1 other" about, so it is
  /// drawn as the single row it reads as.
  bool get isGrouped => actorNames.length > 1;

  /// Unread if ANY of them is.
  ///
  /// The row is one thing to the person reading it, and showing it as
  /// read because the oldest of nineteen had been seen would hide the
  /// eighteen that had not.
  bool get anyUnread => members.any((m) => '${m['is_read']}' != '1');

  /// The distinct people, newest first.
  ///
  /// By id, not by name: two people called Dave are two people, and the
  /// same person's id arriving twice is one. The id is what the server
  /// is sure about.
  List<String> get actorNames {
    final seen = <String>{};
    final names = <String>[];

    for (final member in members) {
      final initiator = member['entity']?['initiator_data'];
      final map = initiator is Map ? initiator : const {};

      final id = '${map['id'] ?? ''}';
      final name = '${map['display_name'] ?? ''}'.trim();

      // No id means nothing can be deduped on, so it is kept — a name
      // shown twice is better than a person dropped.
      if (id.isNotEmpty && !seen.add(id)) continue;

      names.add(name.isEmpty ? 'Someone' : name);
    }

    return names;
  }

  /// "Ali", "Ali and Sam", "Ali, Sam and 18 others" — in pieces, so
  /// the names can be drawn bold and the joins between them plain.
  ///
  /// ── BUILT AS A LIST, NOT AS CASES ───────────────────────────────
  ///
  /// The same assembly EventAttendance.summary uses, for the same
  /// reason: written as a branch per shape it comes out as "Ali, Sam
  /// are going" and "Ali and Sam and 18 others", each individually
  /// defensible and both wrong read aloud.
  ///
  /// Two names at most. This is the start of a sentence, not a list of
  /// everybody, and the third name pushes the thing they all did off
  /// the end of the line.
  List<NameChunk> get nameChunks {
    final names = actorNames;

    if (names.isEmpty) return const [(text: 'Someone', bold: true)];
    if (names.length == 1) return [(text: names.first, bold: true)];

    final shown = names.take(2).toList();
    final rest = names.length - shown.length;

    if (rest == 0) {
      return [
        (text: shown.first, bold: true),
        (text: ' and ', bold: false),
        (text: shown.last, bold: true),
      ];
    }

    return [
      (text: shown.first, bold: true),
      (text: ', ', bold: false),
      (text: shown.last, bold: true),
      (text: ' and $rest ${rest == 1 ? 'other' : 'others'}', bold: false),
    ];
  }

  /// The same line as one string.
  ///
  /// What the message is built to start with, and what its length is
  /// measured against when the tile slices the rest off — so the two
  /// have to come from the same place. See [nameChunks].
  String get nameLine => nameChunks.map((c) => c.text).join();
}

/// The notification types that are collapsed. See the note above.
const Set<String> _groupable = {'like'};

/// One list of rows from one list of notifications.
///
/// Order is preserved: a group takes the position of its newest member,
/// so nothing jumps up the list by having been liked again. Anything
/// not groupable comes back as a group of one, so the caller has a
/// single shape to draw rather than two.
List<NotificationGroup> groupNotifications(List<dynamic> raw) {
  final out = <NotificationGroup>[];

  // Key to its position in [out], so a later member can be appended to
  // a group already placed rather than starting a second one further
  // down.
  final index = <String, int>{};

  for (final item in raw) {
    if (item is! Map) continue;

    final notification = Map<String, dynamic>.from(item);
    final type = '${notification['type'] ?? ''}';

    if (!_groupable.contains(type)) {
      out.add(NotificationGroup([notification]));

      continue;
    }

    final entity = notification['entity'];
    final map = entity is Map ? entity : const {};

    // The entity TYPE is in the key as well as the id. A like on post
    // 91 and a like on comment 91 are different things, and the ids
    // come from different tables that know nothing about each other.
    final key = '$type|${map['entity_type'] ?? ''}|${map['entity_id'] ?? ''}';

    final at = index[key];

    if (at == null) {
      index[key] = out.length;
      out.add(NotificationGroup([notification]));
    } else {
      out[at] = NotificationGroup([...out[at].members, notification]);
    }
  }

  return out;
}
