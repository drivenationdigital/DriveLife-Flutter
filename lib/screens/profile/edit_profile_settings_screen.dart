import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/services/auth_service.dart';
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
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
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

      // Clear auth token
      await _authService.logout();

      // Clear user from provider
      if (context.mounted) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        userProvider.clearUser();
      }

      print('✅ [HomeTabs] Logout successful');

      // Navigate to login and clear navigation stack
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.login,
          (route) => false, // Remove all routes
        );
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
          IconButton(
            icon: const Icon(Icons.qr_code, color: Colors.black),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black),
            onPressed: () {},
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
