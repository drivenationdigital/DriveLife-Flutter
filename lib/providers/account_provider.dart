// providers/account_manager.dart
import 'dart:convert';
import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/models/account_model.dart';
import 'package:drivelife/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class AccountManager extends ChangeNotifier {
  List<Account> _accounts = [];
  int _activeAccountIndex = 0;

  List<Account> get accounts => _accounts;
  Account? get activeAccount =>
      _accounts.isEmpty ? null : _accounts[_activeAccountIndex];
  User? get activeUser => activeAccount?.user;
  String? get activeToken => activeAccount?.token;

  List<Account> get userAccounts =>
      _accounts.where((a) => a.isUserAccount).toList();
  List<Account> get entityAccounts =>
      _accounts.where((a) => a.isEntityAccount).toList();

  // Get entities for specific user
  List<Account> getEntitiesForUser(int userId) {
    return _accounts.where((a) => a.parentUserId == userId).toList();
  }

  // Get parent user account
  Account? getParentAccount(Account entityAccount) {
    if (entityAccount.parentUserId == null) return null;
    return _accounts.firstWhere(
      (a) => a.isUserAccount && a.user.id == entityAccount.parentUserId,
      orElse: () => entityAccount,
    );
  }

  // ✅ Fix loadManagedEntities to properly handle entity accounts
  Future<void> loadManagedEntities(int userId, String token) async {
    // NEW: TEMPORARILY DISABLE ENTITY LOADING AND REMOVE ALL ENTITY ACCOUNTS FOR THIS USER
    _accounts.removeWhere((a) => a.isEntityAccount && a.parentUserId == userId);
    notifyListeners();
    return;

    try {
      print('🔄 Loading managed entities for user $userId...');

      // Fetch clubs/venues where user is owner/admin
      final entities = await _fetchManagedEntities(userId, token);

      print('📊 Fetched ${entities.length} entities from API');

      // ✅ Remove OLD entities for this user ONLY (not all entities)
      _accounts.removeWhere(
        (a) => a.isEntityAccount && a.parentUserId == userId,
      );

      print('🗑️ Removed old entities for user $userId');

      // Add new entities
      for (var entity in entities) {
        print(
          '➕ Processing entity: ${entity['user']['username']} (Type: ${entity['type']})',
        );
        final entityType = entity['type'] == 'club'
            ? AccountType.club
            : AccountType.venue;

        await addEntityAccount(
          token: entity['token'],
          entityUser: User.fromJson(entity['user']),
          parentUserId: userId,
          type: entityType,
          entityMeta: entity['meta'],
        );

        print(
          '✅ Added ${entityType.toString()}: ${entity['user']['username']}',
        );
      }

      print('✅ Loaded ${entities.length} entities for user $userId');
    } catch (e) {
      print('❌ Error loading managed entities: $e');
    }
  }

  // ✅ Add this method to clean up duplicates (run once)
  Future<void> cleanupDuplicates() async {
    print('🧹 Cleaning up duplicate accounts...');

    final seen = <int, Set<AccountType>>{};
    final toRemove = <int>[];

    for (var i = 0; i < _accounts.length; i++) {
      final account = _accounts[i];
      final userId = account.user.id;
      final type = account.accountType;

      if (seen[userId] == null) {
        seen[userId] = {type};
      } else if (seen[userId]!.contains(type)) {
        // Duplicate found
        print('🗑️ Found duplicate: ${account.user.username} ($type)');
        toRemove.add(i);
      } else {
        seen[userId]!.add(type);
      }
    }

    // Remove duplicates in reverse order
    for (var i in toRemove.reversed) {
      _accounts.removeAt(i);
    }

    print('✅ Removed ${toRemove.length} duplicates');

    await _saveAccounts();
    notifyListeners();
  }

  // ✅ Make sure addEntityAccount doesn't add duplicates
  Future<void> addEntityAccount({
    required String token,
    required User entityUser,
    required int parentUserId,
    required AccountType type,
    required Map<String, dynamic> entityMeta,
  }) async {
    print(
      '➕ Adding entity: ${entityUser.username}, Type: $type, UserID: ${entityUser.id}',
    );

    // ✅ Check if this exact entity already exists
    final existingIndex = _accounts.indexWhere(
      (a) => a.user.id == entityUser.id && a.accountType == type,
    );

    if (existingIndex != -1) {
      print('⚠️ Entity already exists at index $existingIndex - SKIPPING');
      return; // ✅ Don't update, just skip
    }

    final account = Account(
      token: token,
      user: entityUser,
      lastUsed: DateTime.now(),
      accountType: type,
      parentUserId: parentUserId,
      entityMeta: entityMeta,
    );

    _accounts.add(account);
    print('✅ Added ${type.toString()} account: ${entityUser.username}');

    await _saveAccounts();
    notifyListeners();
  }

  /// Refresh managed entities for a specific user
  Future<void> refreshManagedEntities(int userId, String token) async {
    print('🔄 Refreshing entities for user $userId');

    try {
      final response = await http.get(
        Uri.parse(
          'https://www.carevents.com/uk/wp-json/app/v1/managed-entities',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final entities = data['entities'] as List;

          // ✅ Check if active account is an entity being removed
          final currentAccount = activeAccount;
          final isActiveEntityBeingRemoved =
              currentAccount != null &&
              currentAccount.isEntityAccount &&
              currentAccount.parentUserId == userId;

          // ✅ If removing active entity, switch to parent user first
          if (isActiveEntityBeingRemoved) {
            final parentIndex = _accounts.indexWhere(
              (acc) => acc.isUserAccount && acc.user.id == userId,
            );
            if (parentIndex != -1) {
              await switchAccount(parentIndex);
            }
          }

          // Remove old entities for this user
          _accounts.removeWhere(
            (acc) => acc.isEntityAccount && acc.parentUserId == userId,
          );

          // ✅ Reset index after removal to stay safe
          if (_activeAccountIndex >= _accounts.length) {
            _activeAccountIndex = _accounts.length - 1;
          }

          // Add refreshed entities
          for (var entity in entities) {
            final entityType = entity['type'] == 'club'
                ? AccountType.club
                : AccountType.venue;

            final token = entity['token'];
            final userData = entity['user'];
            final meta = entity['meta'];

            final user = User.fromJson(userData);

            final account = Account(
              token: token,
              user: user,
              lastUsed: DateTime.now(),
              accountType: entityType,
              parentUserId: userId,
              entityMeta: meta,
            );

            _accounts.add(account);
            print(
              '✅ Refreshed ${entityType.toString().split('.').last}: ${user.username}',
            );
          }

          // ✅ If we were on an entity, try to switch back to the refreshed one
          if (isActiveEntityBeingRemoved && entities.isNotEmpty) {
            final refreshedEntityIndex = _accounts.indexWhere(
              (acc) =>
                  acc.isEntityAccount &&
                  acc.entityMeta?['club_post_id'] ==
                      currentAccount.entityMeta?['club_post_id'],
            );
            if (refreshedEntityIndex != -1) {
              await switchAccount(refreshedEntityIndex);
            }
          }

          await _saveAccounts();
          notifyListeners();
          print('✅ Entities refreshed successfully');
        }
      }
    } catch (e) {
      print('❌ Error refreshing entities: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchManagedEntities(
    int userId,
    String token,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v1/managed-entities'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('📡 Fetching managed entities for user $userId');
      print('📊 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Fetched ${data['total']} entities');
        return List<Map<String, dynamic>>.from(data['entities'] ?? []);
      } else {
        print('❌ Failed to fetch entities: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Error fetching entities: $e');
      return [];
    }
  }

  // Load all accounts from storage
  Future<void> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final accountsJson = prefs.getStringList('accounts') ?? [];
    final activeIndex = prefs.getInt('activeAccountIndex') ?? 0;

    _accounts = accountsJson
        .map((json) => Account.fromJson(jsonDecode(json)))
        .toList();

    // 🔄 MIGRATION: Check for old token in secure storage
    await _migrateOldAccount();

    if (_accounts.isNotEmpty) {
      _activeAccountIndex = activeIndex.clamp(0, _accounts.length - 1);
    } else {
      _activeAccountIndex = 0;
    }

    notifyListeners();
  }

  // Add migration method
  Future<void> _migrateOldAccount() async {
    final storage = FlutterSecureStorage();
    final oldToken = await storage.read(key: 'token');
    final oldUserData = await storage.read(key: 'user_data');

    if (oldToken != null && oldUserData != null) {
      print('🔄 Migrating old account to AccountManager...');

      try {
        final userData = jsonDecode(oldUserData);
        final oldAccount = Account(
          token: oldToken,
          user: User.fromJson(userData),
          lastUsed: DateTime.now(),
        );

        // Check if this account already exists (by user ID)
        final exists = _accounts.any(
          (acc) => acc.user.id == oldAccount.user.id,
        );

        if (!exists) {
          _accounts.add(oldAccount);
          print('✅ Old account migrated: ${oldAccount.user.username}');
        }

        // Clean up old storage
        await storage.delete(key: 'token');
        await storage.delete(key: 'user_data');

        // Save to new storage
        await _saveAccounts();
      } catch (e) {
        print('❌ Error migrating old account: $e');
      }
    }
  }

  // Add new account
  Future<void> addAccount(String token, User user) async {
    final account = Account(token: token, user: user, lastUsed: DateTime.now());

    _accounts.add(account);
    _activeAccountIndex = _accounts.length - 1;
    await _saveAccounts();
    notifyListeners();
  }

  // Switch to account
  // In account_manager.dart - FIXED:
  Future<void> switchAccount(int index) async {
    if (index < 0 || index >= _accounts.length) return;

    _activeAccountIndex = index;

    // ✅ Keep all the account data, just update lastUsed
    _accounts[index] = Account(
      token: _accounts[index].token,
      user: _accounts[index].user,
      lastUsed: DateTime.now(),
      accountType: _accounts[index].accountType, // ✅ Keep the type!
      parentUserId: _accounts[index].parentUserId, // ✅ Keep parent!
      entityMeta: _accounts[index].entityMeta, // ✅ Keep meta!
    );

    await _saveAccounts();
    print(
      '✅ Switched to ${_accounts[index].accountType}: ${_accounts[index].user.username}',
    );
    notifyListeners();
  }

  // Remove account
  Future<void> removeAccount(int index) async {
    if (index < 0 || index >= _accounts.length) return;

    _accounts.removeAt(index);
    if (_activeAccountIndex >= _accounts.length) {
      _activeAccountIndex = _accounts.isEmpty ? 0 : _accounts.length - 1;
    }

    await _saveAccounts();
    notifyListeners();
  }

  // Update active account's user data
  void updateActiveUser(User updatedUser) {
    if (activeAccount == null) return;

    _accounts[_activeAccountIndex] = Account(
      token: activeAccount!.token,
      user: updatedUser,
      lastUsed: DateTime.now(),
    );
    _saveAccounts();
    notifyListeners();
  }

  // Save to storage
  Future<void> _saveAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final accountsJson = _accounts
        .map((account) => jsonEncode(account.toJson()))
        .toList();

    await prefs.setStringList('accounts', accountsJson);
    await prefs.setInt('activeAccountIndex', _activeAccountIndex);
  }

  // Clear all accounts
  Future<void> clearAll() async {
    _accounts.clear();
    _activeAccountIndex = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accounts');
    await prefs.remove('activeAccountIndex');
    notifyListeners();
  }
}
