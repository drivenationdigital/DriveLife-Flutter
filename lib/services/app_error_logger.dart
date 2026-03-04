import 'dart:convert';
import 'dart:io';
import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class AppLogger {
  static final AuthService _authService = AuthService();

  static Future<void> logError({
    required String error,
    required String context,
    Map<String, dynamic>? meta,
  }) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getParentUser();

      if (token == null || user == null) {
        return; // Can't log without auth info
      }

      final version = (await PackageInfo.fromPlatform()).version;

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v1/log-error'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': user['ID'],
          'error': error,
          'context': context,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'app_version': version,
          'meta': meta ?? {},
        }),
      );
    } catch (_) {
      // Never let the logger itself crash the app
    }
  }
}
