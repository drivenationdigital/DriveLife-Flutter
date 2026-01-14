import 'package:flutter/material.dart';
import '../utils/navigation_helper.dart';
import 'account-settings/manage_social_links_screen.dart';
import 'account-settings/my_details_screen.dart';
import 'account-settings/username_screen.dart';
import 'account-settings/app_permissions_screen.dart';
import 'account-settings/account_settings_screen.dart';
import 'account-settings/edit_profile_images_screen.dart';

class EditProfileSettingsScreen extends StatelessWidget {
  const EditProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black),
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
          _buildMenuItem(
            context,
            'Account Settings',
            () => NavigationHelper.navigateTo(
              context,
              const AccountSettingsScreen(),
            ),
          ),
          _buildMenuItem(
            context,
            'App Permissions',
            () => NavigationHelper.navigateTo(
              context,
              const AppPermissionsScreen(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    String title,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade300, width: 1),
            top: BorderSide(color: Colors.grey.shade300, width: 1),
            left: BorderSide(color: Colors.grey.shade300, width: 1),
            right: BorderSide(color: Colors.grey.shade300, width: 1),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, color: Colors.black),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

class _DummyScreen extends StatelessWidget {
  final String title;

  const _DummyScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Image.asset('assets/logo-dark.png', height: 18),
      ),
      body: Center(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, color: Colors.black),
        ),
      ),
    );
  }
}
