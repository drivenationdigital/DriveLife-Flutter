import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';

class NotificationsAPI {
  static const String _baseUrl = 'https://www.carevents.com/uk/wp-json/app/v1';
  static final AuthService _auth = AuthService();

  /// Get user notifications
  static Future<Map<String, dynamic>?> getUserNotifications({
    bool loadOldNotifications = false,
  }) async {
    try {
      final user = await _auth.getUser();
      if (user == null) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/get-notifications'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': user['id'],
          'load_old_notifications': loadOldNotifications,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print(data);
        return data;
      } else {
        print('Failed to load notifications: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching notifications: $e');
    }
    return null;
  }

  /// Get unread notification count
  static Future<int> getNotificationCount() async {
    try {
      final user = await _auth.getUser();
      if (user == null) return 0;

      final response = await http.post(
        Uri.parse('$_baseUrl/get-new-notifications-count'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': user['id']}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final count = data['count'];
        return count is int ? count : int.tryParse(count.toString()) ?? 0;
      }
    } catch (e) {
      print('Error fetching notification count: $e');
    }
    return 0;
  }

  /// Mark all notifications as read
  static Future<bool> markMultipleNotificationsAsRead() async {
    try {
      final user = await _auth.getUser();
      if (user == null) return false;

      final response = await http.post(
        Uri.parse('$_baseUrl/bulk-notifications-read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': user['id']}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error marking notifications as read: $e');
      return false;
    }
  }
}
