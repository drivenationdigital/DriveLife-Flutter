import 'dart:io';
import 'package:drivelife/config/api_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';

class VersionCheckService {
  static Future<VersionCheckResult?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version; // e.g. "2.1.0"
      final platform = Platform.isIOS ? 'ios' : 'android';

      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/version?platform=$platform'),
      );

      if (res.statusCode != 200) return VersionCheckResult(message: 'Test', forceUpdate: true);

      final data = jsonDecode(res.body);
      final latestVersion = data['latest_version'] as String;
      final minVersion = data['min_version'] as String? ?? latestVersion;
      final forceUpdate = data['force_update'] as bool? ?? false;
      final message =
          data['message'] as String? ?? 'A new update is available.';
      final storeUrl = data['store_url'] as String?;

      final isOutdated = _isVersionBelow(currentVersion, latestVersion);
      final isForced = _isVersionBelow(currentVersion, minVersion);

      if (!isOutdated) return null;

      return VersionCheckResult(
        message: message,
        forceUpdate: forceUpdate || isForced,
        storeUrl: storeUrl,
      );
    } catch (e) {
      debugPrint('Version check failed: $e');
      return null;
    }
  }

  static bool _isVersionBelow(String current, String target) {
    final c = current.split('.').map(int.parse).toList();
    final t = target.split('.').map(int.parse).toList();
    for (int i = 0; i < t.length; i++) {
      final cv = i < c.length ? c[i] : 0;
      if (cv < t[i]) return true;
      if (cv > t[i]) return false;
    }
    return false;
  }
}

class VersionCheckResult {
  final String message;
  final bool forceUpdate;
  final String? storeUrl;

  const VersionCheckResult({
    required this.message,
    required this.forceUpdate,
    this.storeUrl,
  });
}
