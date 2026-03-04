import 'dart:convert';
import 'dart:io';
import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLogger {
  static final AuthService _authService = AuthService();

  static const _queueKey = 'pending_error_logs';

  static Future<void> logError({
    required String error,
    required String context,
    Map<String, dynamic>? meta,
  }) async {
    final log = {
      'error': error,
      'context': context,
      'meta': meta ?? {},
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      final sent = await _sendLog(log);
      if (!sent) {
        await _queueLog(log); // offline — save for later
      }
    } catch (_) {
      await _queueLog(log); // failed — save for later
    }
  }

  // Call this on app start and when connectivity is restored
  static Future<void> flushQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_queueKey) ?? [];
    if (raw.isEmpty) return;

    final remaining = <String>[];

    for (final item in raw) {
      try {
        final log = jsonDecode(item) as Map<String, dynamic>;
        final sent = await _sendLog(log);
        if (!sent) remaining.add(item); // still failing, keep it
      } catch (_) {
        remaining.add(item);
      }
    }

    await prefs.setStringList(_queueKey, remaining);
  }

  static Future<bool> _sendLog(Map<String, dynamic> log) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getParentUser();

      if (token == null || user == null) {
        return false; // Can't log without auth info
      }

      final version = (await PackageInfo.fromPlatform()).version;

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v1/log-error'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'user_id': user['id'],
              'error': log['error'],
              'context': log['context'],
              'platform': Platform.isIOS ? 'ios' : 'android',
              'app_version': version,
              'meta': log['meta'] ?? {},
              'occurred_at': log['timestamp'],
            }),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _queueLog(Map<String, dynamic> log) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_queueKey) ?? [];
      queue.add(jsonEncode(log));
      // Cap queue at 50 to avoid unbounded growth
      if (queue.length > 50) queue.removeAt(0);
      await prefs.setStringList(_queueKey, queue);
    } catch (_) {}
  }

}
