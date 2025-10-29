import 'dart:convert';
import 'package:http/http.dart' as http;

class UserAPI {
  static const String _baseUrl = 'https://www.carevents.com/uk';

  /// 🔹 Get user by ID
  static Future<Map<String, dynamic>?> getUserById(String id) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/wp-json/app/v2/get-user-profile-next?user_id=$id',
      );
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
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
