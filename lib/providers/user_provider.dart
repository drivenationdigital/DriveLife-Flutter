import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/services/firebase_messaging_service.dart';
import 'package:drivelife/services/location_service.dart';
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

    try {
      final profile = await _auth.getUserProfile();
      _user = profile;
      _loading = false;
      notifyListeners();

      // Only proceed with permissions if user is loaded
      if (_user != null && _user!['id'] != null) {
        final userId = _user!['id'];

        // Request and associate FCM token (notifications)
        _setupNotifications(userId);

        // Request and update location
        _setupLocation(userId);
      }
    } catch (e) {
      print('Error loading user: $e');
      _loading = false;
      notifyListeners();
    }
  }

  /// Setup notifications - request permission and associate token
  Future<void> _setupNotifications(int userId) async {
    try {
      // Initialize Firebase Messaging (if not already)
      await FirebaseMessagingService.initialize();

      // Get FCM token
      final token = await FirebaseMessagingService.getToken();

      if (token != null) {
        print('📱 Associating device token with user $userId');
        await ProfileAPI.associateDeviceWithUser(
          deviceToken: token,
          userId: userId,
        );
        print('✅ Device token associated');
      }
    } catch (e) {
      print('❌ Error setting up notifications: $e');
    }
  }

  /// Setup location - request permission and update location
  Future<void> _setupLocation(int userId) async {
    try {
      print('📍 Requesting location permission...');

      // Request location permission
      final hasPermission = await LocationService.requestPermission();

      if (!hasPermission) {
        print('⚠️ Location permission denied by user');
        return;
      }

      print('✅ Location permission granted');

      // Get current location
      final coords = await LocationService.getCoordinates();

      if (coords != null) {
        print('📍 Got location: ${coords['latitude']}, ${coords['longitude']}');

        // Update location on server
        await ProfileAPI.updateLastLocation(coords: coords, userId: userId);

        if (_user != null) {
          _user!['last_location'] = [coords['latitude'], coords['longitude']];
          notifyListeners();
          print('✅ User data updated locally with new location');
          print('📍 New location: ${_user!['last_location']}');
        }

        print('✅ Location updated on server');
      }
    } catch (e) {
      print('❌ Error setting up location: $e');
    }
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

  void clearUser() {
    _user = null;
    print('🗑️ [UserProvider] User data cleared');
    notifyListeners();
  }
}
