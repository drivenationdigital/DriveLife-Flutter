/// What a tag points at.
///
/// A vehicle is its own kind rather than a user with a registration attached:
/// a plate can be tagged without matching anyone's garage, which is why
/// [GalleryTag.entityId] may be 0 for one.
enum TagKind { member, vehicle }

/// One tag — on a whole gallery, or on a single photo in it.
///
/// The same shape serves both. What decides which is the `media_id` sent
/// alongside it when saving: 0 for the gallery, a photo row id for one photo.
class GalleryTag {
  final TagKind kind;

  /// The handle for a member, the registration for a vehicle.
  final String label;

  /// Display name for a member; make and model for a vehicle.
  final String subtitle;

  final String avatarUrl;

  /// Member id, or garage id for a vehicle. 0 for a registration that matches
  /// nothing in any garage — still worth storing, since that car may be
  /// registered here later.
  final int entityId;

  /// The plate as typed, for a vehicle. The server normalises it.
  final String registration;

  /// The member behind the tag: the tagged user, or a vehicle's owner.
  ///
  /// Null for a plate matching no garage — a real case, and what tells the app
  /// this tag is about no registered person.
  final int ownerId;
  final String ownerHandle;
  final String ownerAvatar;

  /// False while the tagged person has yet to accept.
  ///
  /// Tagging someone else is a request, not a statement, so it lands pending
  /// and stays invisible to everyone but the gallery's owner until they answer.
  /// Without this the owner had no way to tell a tag that was waiting from one
  /// that had failed — and it looked like failure.
  ///
  /// Defaults to true: a tag just built from a search result has not been near
  /// the server yet, and showing it as pending would be guessing.
  final bool approved;

  /// Whether this tag points at a member whose profile can be opened.
  bool get hasMember => ownerId > 0;

  const GalleryTag({
    required this.kind,
    required this.label,
    this.subtitle = '',
    this.avatarUrl = '',
    this.entityId = 0,
    this.registration = '',
    this.ownerId = 0,
    this.ownerHandle = '',
    this.ownerAvatar = '',
    this.approved = true,
  });

  /// 'user' or 'car', matching the tag table's entity_type.
  String get entityType => kind == TagKind.member ? 'user' : 'car';

  Map<String, dynamic> toJson() => {
    'entity_type': entityType,
    'entity_id': entityId,
    if (registration.isNotEmpty) 'registration': registration,
  };

  /// Rebuilds a tag the server sent back, so an existing tag can be shown and
  /// removed the same way as one just added.
  factory GalleryTag.fromJson(Map<String, dynamic> json) {
    final isVehicle = '${json['entity_type']}' == 'car';
    final owner = json['owner'];
    final hasOwner = owner is Map;

    return GalleryTag(
      kind: isVehicle ? TagKind.vehicle : TagKind.member,
      label: '${json['label'] ?? ''}',
      subtitle: '${json['subtitle'] ?? ''}',
      avatarUrl: '${json['image'] ?? ''}',
      entityId: int.tryParse('${json['entity_id']}') ?? 0,
      registration: '${json['registration'] ?? ''}',
      ownerId: hasOwner ? (int.tryParse('${owner['user_id']}') ?? 0) : 0,
      ownerHandle: hasOwner ? '${owner['name'] ?? ''}' : '',
      ownerAvatar: hasOwner ? '${owner['avatar'] ?? ''}' : '',
      // Absent means an older response that only ever returned approved rows.
      approved: json['approved'] == null || json['approved'] == true,
    );
  }

  /// Rebuilds a tag from the POST tag endpoint, which answers in a different
  /// shape to the gallery one.
  ///
  /// Same tag, same screens, two payloads — get-post-tags nests the thing
  /// tagged under `entity` and names a vehicle as one string with the plate in
  /// brackets, where galleries send the plate and the model apart. Reading it
  /// here rather than in each screen is what stops the post and gallery
  /// tagging UIs drifting into looking like two different features.
  factory GalleryTag.fromPostTag(Map<String, dynamic> json) {
    final type = '${json['type']}';
    final isVehicle = type != 'user';

    final entity = json['entity'];
    final map = entity is Map
        ? Map<String, dynamic>.from(entity)
        : <String, dynamic>{};

    final owner = map['owner'];
    final ownerMap = owner is Map ? Map<String, dynamic>.from(owner) : null;

    final registration = '${map['registration'] ?? ''}'.trim();
    final make = '${map['make'] ?? ''}'.trim();
    final model = '${map['model'] ?? ''}'.trim();
    final entityId = int.tryParse('${json['entity_id']}') ?? 0;

    return GalleryTag(
      kind: isVehicle ? TagKind.vehicle : TagKind.member,
      // The plate is the heading and the car is the line under it, the way a
      // gallery tag reads. A registration nobody has claimed has only the
      // plate, which is the whole of what was read off the photo.
      label: isVehicle
          ? (registration.isNotEmpty
                ? registration
                : '${map['name'] ?? 'Unknown vehicle'}')
          : '${map['name'] ?? ''}',
      subtitle: isVehicle
          ? [make, model].where((s) => s.isNotEmpty).join(' ')
          : '',
      avatarUrl: '${map['image'] ?? ''}',
      entityId: entityId,
      registration: isVehicle ? registration : '',
      ownerId: isVehicle
          ? (int.tryParse('${ownerMap?['id'] ?? 0}') ?? 0)
          : entityId,
      ownerHandle: isVehicle ? '${ownerMap?['name'] ?? ''}' : '',
      // The post endpoints call this profile_image where the gallery one calls
      // it avatar. Both are read rather than picking a side, because the two
      // shapes reach the same screens.
      ownerAvatar: isVehicle
          ? '${ownerMap?['profile_image'] ?? ownerMap?['avatar'] ?? ownerMap?['image'] ?? ''}'
          : '',
    );
  }

  /// Two tags are the same tag if they point at the same thing.
  bool matches(GalleryTag other) {
    if (kind != other.kind) return false;
    if (entityId > 0 || other.entityId > 0) return entityId == other.entityId;
    return label.toUpperCase() == other.label.toUpperCase();
  }
}
