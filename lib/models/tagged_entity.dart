class TaggedEntity {
  final int index; // Which image (0, 1, 2...)
  final String id;
  final String type; // 'user', 'car', 'event'
  final String label;
  final double? x;
  final double? y;

  TaggedEntity({
    required this.index,
    required this.id,
    required this.type,
    required this.label,
    this.x,
    this.y,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'id': id,
    'type': type,
    'label': label,
    'x': x,
    'y': y,
  };
}
