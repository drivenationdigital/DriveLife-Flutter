import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';

class NotificationsAPI {
  static const String _baseUrl = 'https://www.carevents.com/uk/wp-json/app/v1';
  static final AuthService _auth = AuthService();

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
        return data;
      } else {
        print('Failed to load notifications: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching notifications: $e');
    }
    return null;
  }
}
