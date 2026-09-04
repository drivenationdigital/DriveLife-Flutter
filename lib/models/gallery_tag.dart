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

  const GalleryTag({
    required this.kind,
    required this.label,
    this.subtitle = '',
    this.avatarUrl = '',
    this.entityId = 0,
    this.registration = '',
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

    return GalleryTag(
      kind: isVehicle ? TagKind.vehicle : TagKind.member,
      label: '${json['label'] ?? ''}',
      subtitle: '${json['subtitle'] ?? ''}',
      avatarUrl: '${json['image'] ?? ''}',
      entityId: int.tryParse('${json['entity_id']}') ?? 0,
      registration: '${json['registration'] ?? ''}',
    );
  }

  /// Two tags are the same tag if they point at the same thing.
  bool matches(GalleryTag other) {
    if (kind != other.kind) return false;
    if (entityId > 0 || other.entityId > 0) return entityId == other.entityId;
    return label.toUpperCase() == other.label.toUpperCase();
  }
}
