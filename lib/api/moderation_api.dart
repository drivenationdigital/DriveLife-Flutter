import 'dart:convert';

import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Why somebody is reporting something.
///
/// A fixed list, matching dl_report_reasons() in
/// php-api/endpoints/moderation.php. The server rejects anything else,
/// which is deliberate: free text reads better on one report and is
/// useless across a thousand — it cannot be counted, sorted or routed.
enum ReportReason {
  spam('spam', 'Spam or unwanted selling'),
  harassment('harassment', 'Harassment or bullying'),
  hate('hate', 'Hate speech'),
  violence('violence', 'Violence or threats'),
  sexual('sexual', 'Nudity or sexual content'),
  selfHarm('self_harm', 'Self-harm or suicide'),
  scam('scam', 'Scam or fraud'),
  impersonation('impersonation', 'Pretending to be someone else'),
  childSafety('child_safety', 'Something involving a child'),
  other('other', 'Something else');

  /// What the server stores.
  final String id;

  /// What the person choosing reads.
  final String label;

  const ReportReason(this.id, this.label);
}

/// Blocking and reporting.
class ModerationAPI {
  static final AuthService _auth = AuthService();

  static String get _base => AppEnvironment.wordpressBase;

  static Future<Map<String, String>?> _headers() async {
    final token = await _auth.getToken();
    if (token == null) return null;

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Who I have blocked, as ids, remembered between calls.
  ///
  /// Null until the first load. A Set rather than a List because every
  /// use of it is a membership test.
  static Set<int>? _blockedIds;

  /// Block somebody. Safe to call when they are already blocked.
  ///
  /// The server records this in WordPress and mirrors it into Supabase,
  /// which is what stops them sending — see supabase/sql/user-blocks.sql.
  /// The mirror is what makes a block more than a muted notification.
  static Future<bool> block(int userId) async {
    final ok = await _post('block', {'user_id': userId});
    if (ok) _blockedIds = {...?_blockedIds, userId};
    return ok;
  }

  static Future<bool> unblock(int userId) async {
    final ok = await _post('unblock', {'user_id': userId});
    if (ok) _blockedIds?.remove(userId);
    return ok;
  }

  /// The ids I have blocked.
  ///
  /// Cached, because the question "have I blocked this person" is asked
  /// once per thread opened and the answer changes only when this device
  /// changes it — block() and unblock() above keep the set in step
  /// without a round trip.
  ///
  /// Only blocks I MADE. Whether somebody has blocked ME is deliberately
  /// not knowable here: the server does not return it, and a send that
  /// is refused arrives as a message that failed, which is what every
  /// other platform shows.
  static Future<Set<int>> blockedIds({bool refresh = false}) async {
    final cached = _blockedIds;
    if (cached != null && !refresh) return cached;

    final rows = await blockedUsers();
    final ids = rows
        .map((row) => row['id'] is int ? row['id'] as int : -1)
        .where((id) => id > 0)
        .toSet();

    _blockedIds = ids;
    return ids;
  }

  /// Forget the cache. Called when the signed-in account changes, since
  /// one person's blocks are not another's.
  static void forgetBlocked() => _blockedIds = null;

  /// Report something.
  ///
  /// [subjectId] is a String because what it identifies differs: a
  /// WordPress post id is an int and a Supabase message id is a uuid.
  ///
  /// [context] is the surrounding messages for a reported message. It
  /// is stored with the report and survives the message being deleted —
  /// which matters, because a deleted message is often exactly the one
  /// somebody reported.
  static Future<bool> report({
    required String subjectType,
    required String subjectId,
    required ReportReason reason,
    String? detail,
    int? subjectUserId,
    List<Map<String, dynamic>>? context,
  }) => _post('report', {
    'subject_type': subjectType,
    'subject_id': subjectId,
    'reason': reason.id,
    if (detail != null && detail.trim().isNotEmpty) 'detail': detail.trim(),
    if (subjectUserId != null) 'subject_user_id': subjectUserId,
    if (context != null) 'context': context,
  });

  /// Who this person has blocked.
  ///
  /// Only the blocks they made. Who has blocked THEM is deliberately
  /// not available — no platform offers that, for good reasons.
  static Future<List<Map<String, dynamic>>> blockedUsers() async {
    try {
      final headers = await _headers();
      if (headers == null) return const [];

      final response = await http.get(
        Uri.parse('$_base/wp-json/app/v2/moderation/blocks'),
        headers: headers,
      );

      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return const [];

      return (body['blocked'] as List? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (e) {
      debugPrint('[Moderation] blocks threw: $e');
      return const [];
    }
  }

  static Future<bool> _post(String path, Map<String, dynamic> body) async {
    try {
      final headers = await _headers();
      if (headers == null) return false;

      final response = await http.post(
        Uri.parse('$_base/wp-json/app/v2/moderation/$path'),
        headers: headers,
        body: jsonEncode(body),
      );

      debugPrint(
        '[Moderation] $path -> ${response.statusCode} ${response.body}',
      );

      if (response.statusCode != 200) return false;

      final decoded = jsonDecode(response.body);
      return decoded is Map && decoded['success'] == true;
    } catch (e) {
      debugPrint('[Moderation] $path threw: $e');
      return false;
    }
  }
}
