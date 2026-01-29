import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/models/user_model.dart';
import 'package:drivelife/services/firebase_messaging_service.dart';
import 'package:drivelife/services/location_service.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class UserProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  User? _user;
  bool _loading = false;
  bool _refreshing = false;

  User? get user => _user;
  bool get isLoading => _loading;
  bool get isRefreshing => _refreshing;
  bool get isLoggedIn => _user != null;

  // Convert to Map for backward compatibility
  Map<String, dynamic>? get userMap => _user?.toJson();

  /// 🔹 Fetch user from API (using saved token)
  Future<void> loadUser() async {
    _loading = true;
    notifyListeners();

    try {
      final profile = await _auth.getUserProfile();
      if (profile != null) {
        _user = User.fromJson(profile);
        _loading = false;
        notifyListeners();

        // Only proceed with permissions if user is loaded
        if (_user != null) {
          final userId = _user!.id;

          // Request and associate FCM token (notifications)
          _setupNotifications(userId);

          // Request and update location
          _setupLocation(userId);
        }
      } else {
        _loading = false;
        notifyListeners();
      }
    } catch (e) {
      print('Error loading user: $e');
      _loading = false;
      notifyListeners();
    }
  }

  /// 🔄 Refresh user data WITHOUT losing current data
  /// This keeps the old data visible while fetching new data
  Future<void> refreshUser() async {
    if (_user == null) {
      // If no user, just load normally
      return loadUser();
    }

    print('🔄 Refreshing user data...');
    _refreshing = true;
    notifyListeners();

    try {
      final profile = await _auth.getUserProfile();
      if (profile != null) {
        _user = User.fromJson(profile);
        print('✅ User data refreshed');
      }
    } catch (e) {
      print('❌ Error refreshing user: $e');
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// 🔄 Force refresh with loading state
  /// This shows loading indicator
  Future<void> forceRefresh() async {
    print('🔄 Force refreshing user data...');
    _loading = true;
    notifyListeners();

    try {
      final profile = await _auth.getUserProfile();
      if (profile != null) {
        _user = User.fromJson(profile);
        print('✅ User data force refreshed');
      }
    } catch (e) {
      print('❌ Error force refreshing user: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 🔹 Update specific user fields locally (optimistic update)
  void updateUserField(String field, dynamic value) {
    if (_user == null) return;

    switch (field) {
      case 'firstName':
        _user = _user!.copyWith(firstName: value);
        break;
      case 'lastName':
        _user = _user!.copyWith(lastName: value);
        break;
      case 'email':
        _user = _user!.copyWith(email: value);
        break;
      case 'username':
        _user = _user!.copyWith(username: value);
        break;
      case 'profileImage':
        _user = _user!.copyWith(profileImage: value);
        break;
      case 'coverImage':
        _user = _user!.copyWith(coverImage: value);
        break;
      case 'verified':
        _user = _user!.copyWith(verified: value);
        break;
      default:
        print('⚠️ Unknown field: $field');
    }
    notifyListeners();
  }

  /// 🔹 Update entire user object (optimistic update)
  void updateUser(User updatedUser) {
    _user = updatedUser;
    notifyListeners();
  }

  /// 🔹 Update profile image
  Future<void> updateProfileImage(String imageUrl) {
    updateUserField('profileImage', imageUrl);
    // Optionally sync with backend
    return Future.value();
  }

  /// 🔹 Update cover image
  Future<void> updateCoverImage(String imageUrl) {
    updateUserField('coverImage', imageUrl);
    // Optionally sync with backend
    return Future.value();
  }

  /// 🔹 Add follower (optimistic update)
  void addFollower(String userId) {
    if (_user == null) return;
    final updatedFollowers = List<String>.from(_user!.followers);
    if (!updatedFollowers.contains(userId)) {
      updatedFollowers.add(userId);
      _user = _user!.copyWith(followers: updatedFollowers);
      notifyListeners();
    }
  }

  /// 🔹 Remove follower (optimistic update)
  void removeFollower(String userId) {
    if (_user == null) return;
    final updatedFollowers = List<String>.from(_user!.followers);
    updatedFollowers.remove(userId);
    _user = _user!.copyWith(followers: updatedFollowers);
    notifyListeners();
  }

  /// 🔹 Add following (optimistic update)
  void addFollowing(String userId) {
    if (_user == null) return;
    final updatedFollowing = List<String>.from(_user!.following);
    if (!updatedFollowing.contains(userId)) {
      updatedFollowing.add(userId);
      _user = _user!.copyWith(following: updatedFollowing);
      notifyListeners();
    }
  }

  /// 🔹 Remove following (optimistic update)
  void removeFollowing(String userId) {
    if (_user == null) return;
    final updatedFollowing = List<String>.from(_user!.following);
    updatedFollowing.remove(userId);
    _user = _user!.copyWith(following: updatedFollowing);
    notifyListeners();
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
          final newLocation = LastLocation(
            latitude: coords['latitude']!,
            longitude: coords['longitude']!,
            updatedAt: DateTime.now().toIso8601String(),
            country: 'GB', // You might want to get this from coords
          );
          _user = _user!.copyWith(lastLocation: newLocation);
          notifyListeners();
          print('✅ User data updated locally with new location');
        }

        print('✅ Location updated on server');
      }
    } catch (e) {
      print('❌ Error setting up location: $e');
    }
  }

  /// 🔹 Set user manually (e.g. after login)
  void setUser(Map<String, dynamic> userData) {
    _user = User.fromJson(userData);
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
