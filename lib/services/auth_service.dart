import 'dart:convert';
import 'package:drivelife/models/user_model.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const String _apiUrl = 'https://www.carevents.com/uk';
  final _storage = const FlutterSecureStorage();
  AccountManager? _accountManager;

  static const _tokenKey = 'token';
  static const _userKey = 'user_data';

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  void setAccountManager(AccountManager manager) {
    _accountManager = manager;
  }

  /// Login user and cache token + user profile
  Future<bool> login(String email, String password) async {
    try {
      print('🔐 Attempting login for $email');
      final uri = Uri.parse(
        '$_apiUrl/wp-json/ticket_scanner/v1/verify_user/?email=$email&password=$password',
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        print('✅ [AuthService] Login response: $data');

        final token = data['token'];
        if (token == null || token.isEmpty) return false;

        // Fetch user profile
        final userProfile = await _getUserProfileWithToken(token);
        if (userProfile == null) return false;

        if (_accountManager != null) {
          print('✅ Adding account to AccountManager');
          print('📊 Current accounts: ${_accountManager!.accounts.length}');
          await _accountManager!.addAccount(token, User.fromJson(userProfile));
          print('📊 After adding: ${_accountManager!.accounts.length}');
        } else {
          print('⚠️ AccountManager is NULL - using fallback storage');
          await _storage.write(key: _tokenKey, value: token);
          await _storage.write(key: _userKey, value: jsonEncode(userProfile));
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

  Future<Map<String, dynamic>> registerUser({
    required String fullName,
    required String email,
    required String password,
    required String country,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/wp-json/app/v1/register-user'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'full_name': fullName,
          'email': email,
          'password': password,
          'country': country,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode != 201) {
        return {
          'success': false,
          'message': data['message'] ?? 'An error occurred',
          'code': data['code'] ?? 'unknown_error',
        };
      }

      return data;
    } catch (error) {
      return {
        'success': false,
        'message': 'Network error: ${error.toString()}',
        'code': 'network_error',
      };
    }
  }

  /// Get cached token
  Future<String?> getToken() async {
    if (_accountManager != null) {
      return _accountManager!.activeToken;
    }
    // Fallback to old storage
    return await _storage.read(key: _tokenKey);
  }

  Future<String?> getParentUserToken() async {
    // if active account is club, return parent user token
    if (_accountManager != null && _accountManager!.activeAccount != null) {
      final active = _accountManager!.activeAccount!;
      if (active.isClubAccount && active.parentUserId != null) {
        final parentAccount = _accountManager!.accounts.firstWhere(
          (acc) => acc.user.id == active.parentUserId,
        );

        return parentAccount.token;
      }
    }
  }

  /// Get cached user (no network call)
  Future<Map<String, dynamic>?> getUser() async {
    if (_accountManager != null) {
      return _accountManager!.activeUser?.toJson();
    }

    // Fallback to old storage
    final data = await _storage.read(key: _userKey);
    if (data == null) return null;
    return jsonDecode(data);
  }

  /// ✅ Fetch user profile with specific token
  Future<Map<String, dynamic>?> _getUserProfileWithToken(String token) async {
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
        return data['user'];
      } else {
        print('Failed to get profile: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching profile: $e');
      return null;
    }
  }

  /// ✅ Fetch fresh user profile from API using active token
  Future<Map<String, dynamic>?> getUserProfile() async {
    final token = await getToken();
    if (token == null) return null;

    final profile = await _getUserProfileWithToken(token);

    // Update account manager if available
    if (profile != null && _accountManager != null) {
      _accountManager!.updateActiveUser(User.fromJson(profile));
    }

    return profile;
  }

  /// Save session manually (for custom login flows)
  Future<void> saveSession(String token, Map<String, dynamic> user) async {
    if (_accountManager != null) {
      await _accountManager!.addAccount(token, User.fromJson(user));
    } else {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _userKey, value: jsonEncode(user));
    }
  }

  /// Check login state
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Logout (clear everything)
  Future<void> logout() async {
    if (_accountManager != null) {
      final activeIndex = _accountManager!.accounts.indexOf(
        _accountManager!.activeAccount!,
      );
      await _accountManager!.removeAccount(activeIndex);
    } else {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    }
  }
}
