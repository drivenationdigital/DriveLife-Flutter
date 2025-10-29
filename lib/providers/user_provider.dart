import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class UserProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  Map<String, dynamic>? _user;
  bool _loading = false;

  Map<String, dynamic>? get user => _user;
  bool get isLoading => _loading;
  bool get isLoggedIn => _user != null;

  /// 🔹 Fetch user from API (using saved token)
  Future<void> loadUser() async {
    _loading = true;
    notifyListeners();

    final profile = await _auth.getUserProfile();
    _user = profile;
    _loading = false;
    notifyListeners();
  }

  /// 🔹 Set user manually (e.g. after login)
  void setUser(Map<String, dynamic> userData) {
    _user = userData;
    notifyListeners();
  }

  /// 🔹 Clear user on logout
  Future<void> logout() async {
    await _auth.logout();
    _user = null;
    notifyListeners();
  }
}
