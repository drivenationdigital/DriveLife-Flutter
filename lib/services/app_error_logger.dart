import 'dart:convert';
import 'dart:io';
import 'package:drivelife/config/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppLogger {
  static Future<void> logError({
    required String error,
    required String context,
    Map<String, dynamic>? meta,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;
      final token = prefs.getString('token') ?? '';
      final version = (await PackageInfo.fromPlatform()).version;

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v1/log-error'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': userId,
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
