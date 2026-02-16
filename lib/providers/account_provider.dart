// providers/account_manager.dart
import 'dart:convert';
import 'package:drivelife/models/account_model.dart';
import 'package:drivelife/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountManager extends ChangeNotifier {
  List<Account> _accounts = [];
  int _activeAccountIndex = 0;

  List<Account> get accounts => _accounts;
  Account? get activeAccount =>
      _accounts.isEmpty ? null : _accounts[_activeAccountIndex];
  User? get activeUser => activeAccount?.user;
  String? get activeToken => activeAccount?.token;

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
  Future<void> switchAccount(int index) async {
    if (index < 0 || index >= _accounts.length) return;

    _activeAccountIndex = index;
    _accounts[index] = Account(
      token: _accounts[index].token,
      user: _accounts[index].user,
      lastUsed: DateTime.now(),
    );

    await _saveAccounts();
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
