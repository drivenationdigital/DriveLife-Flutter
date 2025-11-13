import 'dart:convert';
import 'package:http/http.dart' as http;

class _CacheItem {
  final Map<String, dynamic> data;
  final DateTime timestamp;
  _CacheItem({required this.data, required this.timestamp});
}

class UserAPI {
  static const String _baseUrl = 'https://www.carevents.com/uk';
  static final Map<String, _CacheItem> _profileCache = {};

  /// 🔹 Get user by ID
  static Future<Map<String, dynamic>?> getUserById(String id) async {
    try {
      final now = DateTime.now();

      // If exists AND not expired (10 minutes example)
      if (_profileCache.containsKey(id)) {
        final item = _profileCache[id]!;
        if (now.difference(item.timestamp).inMinutes < 10) {
          return item.data;
        }
      }

      final uri = Uri.parse(
        '$_baseUrl/wp-json/app/v2/get-user-profile-next?user_id=$id',
      );
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Cache it
        _profileCache[id] = _CacheItem(data: data, timestamp: now);
        return data;
      }
      print('Failed to get user by ID: ${response.statusCode}');
      return null;
    } catch (e) {
      print('Error fetching user by ID: $e');
      return null;
    }
  }

  /// 🔹 Get user by username
  static Future<Map<String, dynamic>?> getUserByUsername(
    String username,
  ) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/wp-json/app/v2/get-user-profile-next?username=$username',
      );
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      print('Failed to get user by username: ${response.statusCode}');
      return null;
    } catch (e) {
      print('Error fetching user by username: $e');
      return null;
    }
  }
}
