/// The content shapes a group page shows, shared by global groups and
/// clubs.
///
/// Both now serve the same four tabs from different sources — a global
/// group matches its vehicles by rule, a club takes its members' — but
/// what arrives at the widget is identical, so the models and the
/// widgets are shared and only the fetch differs.
///
/// Named without "GlobalGroup" for exactly that reason: these describe
/// a car in a group, not a car in one kind of group.
library;

/// Who made something, as a group page shows them.
class GroupUser {
  final int id;
  final String name;

  /// "Dan P." — built server-side so the app and a notification cannot
  /// disagree about how somebody's name is shortened.
  final String shortName;
  final String? avatar;

  const GroupUser({
    required this.id,
    required this.name,
    required this.shortName,
    this.avatar,
  });

  static GroupUser? fromJson(dynamic json) {
    if (json is! Map) return null;

    final map = Map<String, dynamic>.from(json);

    return GroupUser(
      id: (map['id'] as num?)?.toInt() ?? 0,
      name: map['name'] as String? ?? '',
      shortName: map['short_name'] as String? ?? map['name'] as String? ?? '',
      avatar: map['avatar'] as String?,
    );
  }
}

/// A vehicle in a group's garage.
class GroupVehicle {
  final int id;
  final String title;
  final String? year;
  final String? image;

  /// Direct likes on the vehicle only.
  ///
  /// NOT the leaderboard score on a vehicle page, which also counts
  /// people who liked a post of the car — so this reads lower, on
  /// purpose, rather than costing a three-way union per tile.
  final int likes;

  final int mods;
  final GroupUser? owner;

  const GroupVehicle({
    required this.id,
    required this.title,
    this.year,
    this.image,
    this.likes = 0,
    this.mods = 0,
    this.owner,
  });

  factory GroupVehicle.fromJson(Map<String, dynamic> json) => GroupVehicle(
    id: (json['id'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    year: json['year'] as String?,
    image: json['image'] as String?,
    likes: (json['likes'] as num?)?.toInt() ?? 0,
    mods: (json['mods'] as num?)?.toInt() ?? 0,
    owner: GroupUser.fromJson(json['owner']),
  );
}

/// A spot, as the grid needs it.
class GroupSpot {
  final int postId;
  final String? vehicle;
  final String? location;
  final String? image;
  final GroupUser? user;

  const GroupSpot({
    required this.postId,
    this.vehicle,
    this.location,
    this.image,
    this.user,
  });

  factory GroupSpot.fromJson(Map<String, dynamic> json) => GroupSpot(
    postId: (json['post_id'] as num?)?.toInt() ?? 0,
    vehicle: json['vehicle'] as String?,
    location: json['location'] as String?,
    image: json['image'] as String?,
    user: GroupUser.fromJson(json['user']),
  );
}

/// A post or a spot in a group's Latest feed.
class GroupPost {
  final int postId;
  final String itemType;

  /// auto | member | curated — how this came to be in the group.
  final String source;

  final String caption;
  final String? image;
  final String? location;
  final String? spottedVehicle;
  final DateTime? happenedAt;
  final int likes;
  final int comments;
  final bool isLiked;
  final GroupUser? user;

  const GroupPost({
    required this.postId,
    this.itemType = 'post',
    this.source = 'auto',
    this.caption = '',
    this.image,
    this.location,
    this.spottedVehicle,
    this.happenedAt,
    this.likes = 0,
    this.comments = 0,
    this.isLiked = false,
    this.user,
  });

  factory GroupPost.fromJson(Map<String, dynamic> json) => GroupPost(
    postId: (json['post_id'] as num?)?.toInt() ?? 0,
    itemType: json['item_type'] as String? ?? 'post',
    source: json['source'] as String? ?? 'auto',
    caption: json['caption'] as String? ?? '',
    image: json['image'] as String?,
    location: json['location'] as String?,
    spottedVehicle: json['spotted_vehicle'] as String?,
    happenedAt: DateTime.tryParse(json['happened_at'] as String? ?? ''),
    likes: (json['likes'] as num?)?.toInt() ?? 0,
    comments: (json['comments'] as num?)?.toInt() ?? 0,
    isLiked: json['is_liked'] == true,
    user: GroupUser.fromJson(json['user']),
  );
}

/// An event on a group page. Nothing produces these for a global group.
class GroupEvent {
  final int id;
  final String title;
  final String? location;
  final String? distance;
  final DateTime? startsAt;

  const GroupEvent({
    required this.id,
    required this.title,
    this.location,
    this.distance,
    this.startsAt,
  });

  factory GroupEvent.fromJson(Map<String, dynamic> json) => GroupEvent(
    id: (json['id'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    location: json['location'] as String?,
    distance: json['distance']?.toString(),
    startsAt: DateTime.tryParse(json['starts_at'] as String? ?? ''),
  );
}
