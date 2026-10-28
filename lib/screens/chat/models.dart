class Conversation {
  final String id;
  final List<String> participantIds;
  final DateTime updatedAt;
  final bool isGroup;
  final String? groupName;
  final String? createdBy;

  /// A Cloudflare delivery URL, or null.
  ///
  /// A finished URL rather than an image id, because this row lives in
  /// Supabase and nothing there can call get_cloudflare_media_url. See
  /// CloudflareImages.uploadAndGetUrl.
  final String? groupImage;

  Conversation({
    required this.id,
    required this.participantIds,
    required this.updatedAt,
    this.isGroup = false,
    this.groupName,
    this.createdBy,
    this.groupImage,
  });

  Conversation copyWith({String? groupImage}) => Conversation(
    id: id,
    participantIds: participantIds,
    updatedAt: updatedAt,
    isGroup: isGroup,
    groupName: groupName,
    createdBy: createdBy,
    groupImage: groupImage ?? this.groupImage,
  );

  factory Conversation.fromMap(Map<String, dynamic> map) {
    // Supabase RPC can return bool as int (0/1) — handle both
    bool parseBool(dynamic val) {
      if (val is bool) return val;
      if (val is int) return val == 1;
      if (val is String) return val == 'true' || val == '1';
      return false;
    }

    return Conversation(
      id: map['id'] as String,
      participantIds: List<String>.from(map['participant_ids'] ?? []),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isGroup: parseBool(
        map['is_group'],
      ), // ← was: map['is_group'] as bool? ?? false
      groupName: map['group_name'] as String?,
      createdBy: map['created_by'] as String?,
      // Tolerated as missing. get_inbox has to be taught to return this
      // separately from the column existing — see
      // supabase/sql/group-image.sql — so for a while the table will
      // have it and the RPC will not.
      groupImage: map['group_image'] as String?,
    );
  }
}
