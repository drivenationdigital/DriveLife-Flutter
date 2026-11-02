/// One thing somebody did, that we think another person would like to
/// see.
///
/// The server does the describing: by the time a row reaches here it has
/// already been turned from `(verb, object_type, object_id)` into words
/// and a picture, because resolving an object id means a query per
/// object type and that belongs next to the database.
///
/// So this model is deliberately dumb. It carries [action] ("added a car
/// to their garage") and [why] ("Because you own a Porsche") as finished
/// strings rather than enums the app would have to translate, which also
/// means the admin test page and the app explain a match with the same
/// sentence — they are built by the same function.
class ActivityItem {
  /// The `ce_user_activity` row id. What a response is recorded against.
  final int id;

  /// The logged verb: `added_vehicle`, `logged_spot`, `joined_group`,
  /// `added_dream`, `created_gallery`. Kept for the icon and for
  /// debugging a bad match; the readable version is [action].
  final String verb;

  /// What they did, as a phrase that follows a name: "Dan Smith" +
  /// "added a car to their garage".
  final String action;

  /// The thing itself — "2019 Porsche 911", a spotted vehicle, a group
  /// name.
  final String title;

  /// A variant, a location, a group strapline. Often absent.
  final String? subtitle;

  final String? image;

  /// Why this person is being shown this, in full: "Because you liked a
  /// Porsche". Null only if the server could not work it out.
  final String? why;

  /// How strong the interest behind it was, 0-100, relative to this
  /// person's strongest interest. Shown to admins while this is being
  /// tested — it is the number that says whether the ordering is sane.
  final int score;

  /// Who did it.
  final ActivityActor? user;

  /// What tapping it should open: `vehicle`, `post`, `group`, `gallery`.
  final String targetType;

  /// Always a String on the wire. The two routes disagree about the type
  /// they want — postDetail calls toString() on what it is given and
  /// vehicleDetail does not — so the coercion happens at the call site,
  /// where the route is known.
  final String targetId;

  final DateTime? createdAt;

  const ActivityItem({
    required this.id,
    required this.verb,
    required this.action,
    required this.title,
    this.subtitle,
    this.image,
    this.why,
    this.score = 0,
    this.user,
    required this.targetType,
    required this.targetId,
    this.createdAt,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> json) {
    return ActivityItem(
      id: _int(json['id']),
      verb: (json['verb'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: _text(json['subtitle']),
      image: _text(json['image']),
      why: _text(json['why']),
      score: _int(json['score']),
      user: json['user'] is Map
          ? ActivityActor.fromJson(Map<String, dynamic>.from(json['user']))
          : null,
      targetType: (json['target_type'] ?? '').toString(),
      targetId: (json['target_id'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
    );
  }

  /// How long ago, short enough for a line of metadata.
  String get ago {
    final when = createdAt;

    if (when == null) return '';

    final gap = DateTime.now().difference(when);

    if (gap.inMinutes < 1) return 'just now';
    if (gap.inMinutes < 60) return '${gap.inMinutes}m';
    if (gap.inHours < 24) return '${gap.inHours}h';
    if (gap.inDays < 7) return '${gap.inDays}d';
    if (gap.inDays < 365) return '${(gap.inDays / 7).floor()}w';

    return '${(gap.inDays / 365).floor()}y';
  }
}

/// Whoever did the thing. The same shape `dl_groups_user_block()`
/// returns everywhere else in the app.
class ActivityActor {
  final int id;
  final String name;
  final String? username;
  final String? image;

  const ActivityActor({
    required this.id,
    required this.name,
    this.username,
    this.image,
  });

  factory ActivityActor.fromJson(Map<String, dynamic> json) {
    return ActivityActor(
      id: _int(json['id']),
      name: (json['name'] ?? '').toString(),
      username: _text(json['username']),
      // 'avatar' FIRST, because that is what dl_groups_user_block()
      // actually calls it — the other two were guesses at a shape this
      // endpoint never sends, so every card drew an empty circle.
      image: _text(
        json['avatar'] ?? json['profile_image'] ?? json['image'],
      ),
    );
  }
}

/// A make the viewer is into, and how strongly, relative to their
/// strongest.
///
/// Shown in the tab header so somebody testing this can tell a bad match
/// from a bad profile. That distinction is most of the value of the
/// experiment: a feed full of the wrong cars because the matcher is
/// broken and a feed full of the wrong cars because we think you like
/// Vauxhalls need completely different fixes.
class ActivityInterest {
  final String make;
  final int strength;

  const ActivityInterest({required this.make, required this.strength});

  factory ActivityInterest.fromJson(Map<String, dynamic> json) {
    return ActivityInterest(
      make: (json['make'] ?? '').toString(),
      strength: _int(json['strength']),
    );
  }
}

/// A whole answer from the feed endpoint.
///
/// [reason] carries WHY a feed is empty, which the app needs because the
/// three empties call for three different sentences: the tables are not
/// installed, we know nothing about you, or we know and have nothing new.
class ActivityFeed {
  final List<ActivityItem> items;
  final List<ActivityInterest> interests;

  /// `not_installed`, `no_interests`, `nothing_new`, or null when there
  /// are items.
  final String? reason;

  const ActivityFeed({
    this.items = const [],
    this.interests = const [],
    this.reason,
  });

  bool get isEmpty => items.isEmpty;
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();

  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// Null for anything the server left empty, so the UI can use `??`
/// rather than checking for empty strings everywhere.
String? _text(dynamic value) {
  final text = value?.toString().trim() ?? '';

  return text.isEmpty ? null : text;
}

/// A group, event or venue suggested off the back of an activity
/// somebody said they liked.
///
/// "If you like this, you might like these." One flat shape for all
/// three kinds, because they sit in one list and differ only in [type]
/// and in how confident [why] is allowed to sound.
///
/// That last part matters more than it looks. A group match is a direct
/// hit — groups ARE makes and models. An event match is either "mentions
/// Porsche" or merely "on near you", and the server words those
/// differently on purpose. If the make-matched rows get tapped and the
/// nearby ones do not, that is the finding, and it is only legible
/// because the two never pretended to be the same claim.
class ActivityRelated {
  /// `person`, `group`, `event` or `venue`.
  final String type;

  /// A slug for a group, a post id for an event or venue. Always a
  /// String on the wire; the call site knows which it wants.
  final String id;

  final String title;

  /// A strapline for a group; "14 Jun · 23 miles away" for a place.
  final String? subtitle;

  final String? image;

  /// Why this is here: "A group for Mazda", "Mentions Porsche", or just
  /// "Near you" when proximity is the only claim being made.
  final String why;

  /// 3 model group, 2 rule match or make named in the text, 1 marque
  /// group, 0 near you and nothing more.
  final int strength;

  /// The region an event or venue belongs to: 'GB', 'US'. Null for a
  /// group, which is global and has none.
  ///
  /// Needed to open one. Post ids are per-blog, so an event id without
  /// a site is ambiguous across countries.
  final String? site;

  const ActivityRelated({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.image,
    required this.why,
    this.strength = 0,
    this.site,
  });

  factory ActivityRelated.fromJson(Map<String, dynamic> json) {
    return ActivityRelated(
      type: (json['type'] ?? '').toString(),
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: _text(json['subtitle']),
      image: _text(json['image']),
      why: (json['why'] ?? '').toString(),
      strength: _int(json['strength']),
      site: _text(json['site']),
    );
  }

  /// Whether this is a match on taste rather than on geography alone.
  /// Drawn differently, so the difference is visible while testing.
  bool get isTasteMatch => strength > 0;
}

/// What came back for one card.
class ActivityRelatedSet {
  final List<ActivityRelated> items;

  /// The make it all hangs off, already cased for a sentence.
  final String make;

  /// False when we have no location for this person, so the events and
  /// venues are missing rather than absent. An empty list and an
  /// unlocatable user look identical without this.
  final bool located;

  const ActivityRelatedSet({
    this.items = const [],
    this.make = '',
    this.located = true,
  });
}
