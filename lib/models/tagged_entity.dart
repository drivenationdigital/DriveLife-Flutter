class TaggedEntity {
  final int index; // Which image (0, 1, 2...)
  final String id;
  final String type; // 'user', 'car', 'event'
  final String label;
  final String? imageUrl;
  final double? x;
  final double? y;

  /// The photo this tag is on, as a row id in the post's media.
  ///
  /// [index] is a position in a list the caller has to rebuild in the order
  /// the server returns it, which is a promise nothing was making. Sent where
  /// it is known; the server still accepts the index for everything else.
  final int? mediaId;

  /// The plate, for a vehicle tag.
  ///
  /// The server reads `registration` for car tags and falls back to it when
  /// the tag names no garage — a plate the scan read that matches nobody here.
  /// It was never sent, so that fallback had nothing to work with.
  final String registration;

  TaggedEntity({
    required this.index,
    required this.id,
    required this.type,
    required this.label,
    this.imageUrl,
    this.x,
    this.y,
    this.registration = '',
    this.mediaId,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'id': id,
    'type': type,
    'label': label,
    'image_url': imageUrl,
    'x': x,
    'y': y,
    if (mediaId != null) 'media_id': mediaId,
  };
}
