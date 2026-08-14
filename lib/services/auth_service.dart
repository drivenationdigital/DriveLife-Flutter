import 'dart:convert';
import 'package:drivelife/models/user_model.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Why a login attempt ended the way it did.
///
/// Kept distinct so the UI never reports "wrong password" for a failure that
/// had nothing to do with the password — the ambiguity that made login
/// problems undiagnosable in the field.
enum LoginOutcome {
  success,

  /// The server refused the credentials, or returned no token.
  invalidCredentials,

  /// Credentials were accepted and a token issued, but the profile could not
  /// be loaded. Usually means the account is not resolvable on the site this
  /// build points at (see `_apiUrl`) rather than a bad password.
  profileUnavailable,

  /// Request never completed: offline, DNS, TLS, timeout, malformed response.
  networkError,
}

class LoginResult {
  final LoginOutcome outcome;
  final String? detail;

  const LoginResult(this.outcome, [this.detail]);

  bool get isSuccess => outcome == LoginOutcome.success;
}

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

  /// Login user and cache token + user profile.
  ///
  /// [identifier] is whatever the user typed — email or username. It must not
  /// be pre-trimmed of anything but surrounding whitespace, and [password] must
  /// not be trimmed at all: WordPress stores passwords verbatim, so trimming
  /// silently locks out anyone whose password has a leading/trailing space.
  Future<LoginResult> login(String identifier, String password) async {
    try {
      print('🔐 Attempting login for $identifier');

      // Credentials MUST go through queryParameters so they are percent-encoded.
      // Interpolating them straight into the URL corrupts any password
      // containing & (truncates), # (truncates, and the tail never leaves the
      // device), + (becomes a space) or a %XX sequence (silently decoded).
      final uri = Uri.parse(
        '$_apiUrl/wp-json/ticket_scanner/v1/verify_user/',
      ).replace(queryParameters: {'email': identifier, 'password': password});

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        print('Login failed: HTTP ${response.statusCode} — ${response.body}');
        return LoginResult(
          LoginOutcome.invalidCredentials,
          'Server rejected the login (HTTP ${response.statusCode}).',
        );
      }

      final data = jsonDecode(response.body);
      final token = data['token'];
      if (token == null || token.isEmpty) {
        // ce_verify_user answers 200 for every failure and puts the reason in
        // `error` ("No user found with that email or username" / "Password is
        // incorrect"), or in `message` for a soft-deleted account. Surface it
        // rather than guessing — that distinction is the whole diagnosis.
        print('Login failed: no token in response — $data');
        return LoginResult(
          LoginOutcome.invalidCredentials,
          (data['error'] ?? data['message'])?.toString(),
        );
      }

      // Credentials were accepted. Anything that fails from here on is NOT a
      // wrong password, and must not be reported as one.
      final userProfile = await _getUserProfileWithToken(token);
      if (userProfile == null) {
        print(
          '⚠️ [AuthService] Authenticated but no profile from $_apiUrl — '
          'account may not exist on this site',
        );
        return LoginResult(
          LoginOutcome.profileUnavailable,
          'Signed in, but your profile could not be loaded from this site.',
        );
      }

      if (_accountManager != null) {
        await _accountManager!.addAccount(token, User.fromJson(userProfile));
      } else {
        print('⚠️ AccountManager is NULL - using fallback storage');
        await _storage.write(key: _tokenKey, value: token);
        await _storage.write(key: _userKey, value: jsonEncode(userProfile));
      }

      return const LoginResult(LoginOutcome.success);
    } catch (e) {
      print('Login error: $e');
      return LoginResult(LoginOutcome.networkError, e.toString());
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

    // Fallback to active token
    return await getToken();
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

  // Get parent user (for club accounts)
  Future<Map<String, dynamic>?> getParentUser() async {
    if (_accountManager != null && _accountManager!.activeAccount != null) {
      final active = _accountManager!.activeAccount!;
      if (active.isClubAccount && active.parentUserId != null) {
        final parentAccount = _accountManager!.accounts.firstWhere(
          (acc) => acc.user.id == active.parentUserId,
        );

        return parentAccount.user.toJson();
      }
    }

    // Fallback to active user
    return await getUser();
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

  // verify email token
  Future<Map<String, dynamic>> verifyEmailToken(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/wp-json/app/v1/verify-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      );

      final data = jsonDecode(response.body);
      print('✅ Email verification response: $data');
      if (response.statusCode == 200) {
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Unknown error',
        };
      }

      return {'success': false, 'message': 'Failed to verify email'};
    } catch (e) {
      print('❌ Email verification error: $e');
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> sendPasswordReset(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/wp-json/app/v1/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Unknown error',
        };
      }

      return {'success': false, 'message': 'Failed to send reset email'};
    } catch (e) {
      print('❌ Password reset error: $e');
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> resetPassword({
    required String key,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/wp-json/app/v1/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'key': key, 'new_password': newPassword}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': data['success'] ?? false,
          'message': data['message'] ?? 'Unknown error',
        };
      }

      return {'success': false, 'message': 'Failed to reset password'};
    } catch (e) {
      print('❌ Password reset error: $e');
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }
}
