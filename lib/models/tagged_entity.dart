class TaggedEntity {
  final int index; // Which image (0, 1, 2...)
  final String id;
  final String type; // 'user', 'car', 'event'
  final String label;
  final String? imageUrl;
  final double? x;
  final double? y;

  TaggedEntity({
    required this.index,
    required this.id,
    required this.type,
    required this.label,
    this.imageUrl,
    this.x,
    this.y,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'id': id,
    'type': type,
    'label': label,
    'image_url': imageUrl,
    'x': x,
    'y': y,
  };
}
