import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const String _apiUrl = 'https://www.carevents.com/uk';
  final _storage = const FlutterSecureStorage();

  static const _tokenKey = 'token';
  static const _userKey = 'user_data';

  /// ✅ Login user and cache token + user profile
  Future<bool> login(String email, String password) async {
    try {
      final uri = Uri.parse(
        '$_apiUrl/wp-json/ticket_scanner/v1/verify_user/?email=$email&password=$password',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final token = data['token'];
        if (token == null || token.isEmpty) return false;

        // ✅ Save token securely
        await _storage.write(key: _tokenKey, value: token);

        // ✅ Immediately fetch user profile and save it
        final user = await getUserProfile();
        if (user != null) {
          await _storage.write(key: _userKey, value: jsonEncode(user));
        }

        return true;
      } else {
        print('Login failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  /// ✅ Get cached token
  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// ✅ Get cached user (no network call)
  Future<Map<String, dynamic>?> getUser() async {
    final data = await _storage.read(key: _userKey);
    if (data == null) return null;
    return jsonDecode(data);
  }

  /// ✅ Fetch fresh user profile from API using stored token
  Future<Map<String, dynamic>?> getUserProfile() async {
    final token = await getToken();
    if (token == null) return null;

    try {
      final uri = Uri.parse('$_apiUrl/wp-json/app/v2/get-user-profile/');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'];

        // ✅ Update cached user
        if (user != null) {
          await _storage.write(key: _userKey, value: jsonEncode(user));
        }

        return user;
      } else {
        print('Failed to get profile: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching profile: $e');
      return null;
    }
  }

  /// ✅ Save session manually (for custom login flows)
  Future<void> saveSession(String token, Map<String, dynamic> user) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user));
  }

  /// ✅ Check login state
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// ✅ Logout (clear everything)
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
