import 'package:drivelife/models/tag_suggestion.dart';
import 'package:drivelife/models/tagged_entity.dart';

/// What saving should do about the post's place.
enum PostLocationAction {
  /// Nothing. There was none and none was chosen, or what is on screen
  /// is only an offer.
  leave,

  /// Write the chosen place, with its venue or track id.
  set,

  /// Empty the columns — the place was taken off.
  clear,
}

/// Everything saving the tag screen has to do, worked out in one place.
///
/// ── WHY THIS IS NOT IN THE WIDGET ───────────────────────────────────
///
/// Every bug this screen has had was in exactly this decision, and each
/// one looked identical from outside: "removing a tag does nothing".
///
///   - a guess was re-applied on save, so a removed venue came back
///   - a tag with no label was skipped on load, so it had no row id and
///     could never be removed
///   - a picked vehicle kept its guessed flag, so it was drawn as an
///     offer and filtered back out of the save
///   - removing the place called nothing at all, because the write was
///     inside `if (location != null)`
///
/// None of those are reachable by a widget test without a signed-in
/// account, a real post and a photo with GPS in it. As a pure function
/// they are four assertions.
class PostTagPlan {
  /// Tags to send. Already excludes anything the post has, so a person
  /// tag is never re-sent and moved to the first photo.
  final List<TaggedEntity> add;

  /// Row ids to delete.
  final List<int> remove;

  final PostLocationAction location;

  /// The place to write, when [location] is [PostLocationAction.set].
  final TagSuggestion? place;

  const PostTagPlan({
    required this.add,
    required this.remove,
    required this.location,
    this.place,
  });
}

/// Works out what to save.
///
/// [editing] is the whole of the difference between the two flows. On
/// the way out of posting a guess is applied — that is the point of
/// having found it. Afterwards it is only an offer: by then the post
/// has whatever it is going to have, so anything still marked as a
/// guess is something that was removed or never taken, and writing it
/// would put it straight back.
///
/// [tagIds] is what the post already has, keyed 'type:entityId'. A key
/// in there and not in the held lists is a removal; a held tag not in
/// there is an addition.
///
/// [hadPlace] and [placeRemoved] exist because a place is columns on
/// the post rather than a tag row, so there is no id to delete and
/// clearing means writing an empty name. Without knowing it was
/// deliberately taken off, saving cannot tell "they removed it" from
/// "there was never one" — and clearing in the second case would wipe a
/// place the composer set.
PostTagPlan planPostTags({
  required bool editing,
  required List<TaggedEntity> events,
  required List<TaggedEntity> vehicles,
  required List<TaggedEntity> people,
  required Map<String, int> tagIds,
  required Set<String> guessedIds,
  TagSuggestion? place,
  bool hadPlace = false,
  bool placeRemoved = false,
}) {
  bool isOffer(TaggedEntity t) => editing && guessedIds.contains(t.id);

  final held = <TaggedEntity>[
    ...events.where((t) => !isOffer(t)),
    ...vehicles.where((t) => !isOffer(t)),
    // A person is never a guess: there is no path that tags one
    // automatically, so nothing filters here.
    ...people,
  ];

  final kept = held.map(_key).toSet();

  final remove = <int>[
    for (final entry in tagIds.entries)
      if (!kept.contains(entry.key)) entry.value,
  ];

  final add = held.where((t) => !tagIds.containsKey(_key(t))).toList();

  // An offer is not a place, however it looks on screen.
  final chosen = (place != null && editing && place.guessed) ? null : place;

  final PostLocationAction action;

  if (chosen != null) {
    action = PostLocationAction.set;
  } else if (placeRemoved || hadPlace) {
    action = PostLocationAction.clear;
  } else {
    action = PostLocationAction.leave;
  }

  return PostTagPlan(
    add: add,
    remove: remove,
    location: action,
    place: chosen,
  );
}

String _key(TaggedEntity t) => '${t.type}:${t.id}';
