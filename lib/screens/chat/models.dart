import 'package:drivelife/screens/chat/SupabaseClasses.dart';

class Conversation {
  final String id;
  final List<String> participantIds;
  final DateTime updatedAt;
  final bool isGroup; // ← NEW
  final String? groupName; // ← NEW
  final String? createdBy; // ← NEW

  Conversation({
    required this.id,
    required this.participantIds,
    required this.updatedAt,
    this.isGroup = false,
    this.groupName,
    this.createdBy,
  });

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
    );
  }
}
