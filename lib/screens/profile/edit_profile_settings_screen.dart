import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/services/upload_quality_prefs.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/widgets/shared_header_actions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/navigation_helper.dart';
import '../account-settings/manage_social_links_screen.dart';
import '../account-settings/my_details_screen.dart';
import '../account-settings/username_screen.dart';
import '../account-settings/app_permissions_screen.dart';
import '../account-settings/account_settings_screen.dart';
import '../account-settings/edit_profile_images_screen.dart';

class EditProfileSettingsScreen extends StatelessWidget {
  final _authService = AuthService();
  EditProfileSettingsScreen({super.key});

  Future<void> _handleLogout(BuildContext context) async {
    final accountManager = context.read<AccountManager>();
    final hasMultipleAccounts = accountManager.accounts.length > 1;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: Text(
          hasMultipleAccounts
              ? 'Remove this account from the app?'
              : 'Are you sure you want to logout?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      print('🚪 [HomeTabs] Logging out...');

      // Get current account index before logout
      final activeAccount = accountManager.activeAccount;
      final currentIndex = accountManager.accounts.indexOf(activeAccount!);

      // Remove current account
      await accountManager.removeAccount(currentIndex);

      // Clear user from provider
      if (context.mounted) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        userProvider.clearUser();
      }

      print('✅ [HomeTabs] Logout successful');

      if (context.mounted) {
        if (accountManager.accounts.isEmpty) {
          // No accounts left - go to login
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.login,
            (route) => false,
          );
        } else {
          // Still have accounts - reload home with new active account
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.home,
            (route) => false,
          );
        }
      }
    } catch (e) {
      print('❌ [HomeTabs] Logout error: $e');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
           ...SharedHeaderIcons.actionIcons(
            iconColor: Colors.black,
            showQr: true,
            showNotifications: true,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        children: [
          _buildMenuItem(context, 'Edit Profile Images', () async {
            final result = await NavigationHelper.navigateTo(
              context,
              const EditProfileImagesScreen(),
            );

            // If images were updated, pop this screen too and pass result up
            if (result == true && context.mounted) {
              Navigator.pop(context, true);
            }
          }),
          const SizedBox(height: 8),
          _buildMenuItem(context, 'Manage Social Links', () async {
            final result = await NavigationHelper.navigateTo(
              context,
              const ManageSocialLinksScreen(),
            );

            // If links were updated, pop this screen too and pass result up
            if (result == true && context.mounted) {
              Navigator.pop(context, true);
            }
          }),
          const SizedBox(height: 8),
          _buildMenuItem(context, 'My Details', () async {
            final result = await NavigationHelper.navigateTo(
              context,
              const MyDetailsScreen(),
            );

            // If details were updated, pop this screen too and pass result up
            if (result == true && context.mounted) {
              Navigator.pop(context, true);
            }
          }),
          const SizedBox(height: 8),
          _buildMenuItem(context, 'Username', () async {
            final result = await NavigationHelper.navigateTo(
              context,
              const UsernameScreen(),
            );

            // If username was updated, pop this screen too and pass result up
            if (result == true && context.mounted) {
              Navigator.pop(context, true);
            }
          }),
          const SizedBox(height: 8),
          _buildMenuItem(
            context,
            'Account Settings',
            () => NavigationHelper.navigateTo(
              context,
              const AccountSettingsScreen(),
            ),
          ),
          const SizedBox(height: 8),
          const _UploadQualityTile(),
          const SizedBox(height: 8),
          _buildMenuItem(
            context,
            'App Permissions',
            () => NavigationHelper.navigateTo(
              context,
              const AppPermissionsScreen(),
            ),
          ),
          const SizedBox(height: 8),
          // ✅ Logout button - properly placed as separate menu item
          _buildMenuItem(
            context,
            'Logout',
            () => _handleLogout(context),
            isDestructive: true, // Optional: makes it red
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    String title,
    VoidCallback onTap, {
    bool isDestructive = false, // Optional parameter for styling logout button
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: isDestructive ? Colors.red : Colors.black,
                fontWeight: isDestructive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDestructive ? Colors.red : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

/// "High quality uploads" switch.
///
/// Self-contained state so the surrounding settings screen can stay a
/// StatelessWidget — the preference is read once on mount and written straight
/// through, nothing else on the screen depends on it.
class _UploadQualityTile extends StatefulWidget {
  const _UploadQualityTile();

  @override
  State<_UploadQualityTile> createState() => _UploadQualityTileState();
}

class _UploadQualityTileState extends State<_UploadQualityTile> {
  bool _value = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await UploadQualityPrefs.isHighQuality();
    if (!mounted) return;
    setState(() {
      _value = value;
      _loaded = true;
    });
  }

  Future<void> _set(bool value) async {
    setState(() => _value = value);
    await UploadQualityPrefs.setHighQuality(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'High quality uploads',
                  style: TextStyle(fontSize: 16, color: Colors.black),
                ),
                const SizedBox(height: 3),
                Text(
                  'Upload photos exactly as they were taken and videos in '
                  '1080p. Uses more data and takes longer to upload.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            // Disabled until the stored value is known, so it can't flash off
            // and be toggled against a value that has not loaded yet.
            value: _value,
            onChanged: _loaded ? _set : null,
            activeThumbColor: theme.primaryColor,
          ),
        ],
      ),
    );
  }
}
