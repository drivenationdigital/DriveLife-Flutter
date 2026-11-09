import 'package:drivelife/api/test_location_api.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/services/upload_quality_prefs.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/widgets/shared_header_actions.dart';
import 'package:drivelife/screens/account-settings/interests_screen.dart';
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
            'Interests & Notifications',
            () => NavigationHelper.navigateTo(
              context,
              const InterestsScreen(),
            ),
          ),
          const SizedBox(height: 8),
          _buildMenuItem(
            context,
            'Account Settings and Privacy',
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
          // Draws nothing unless the server says this account is an
          // administrator, so it costs non-admins one request and no pixels.
          const _TestLocationTile(),
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

/// Pretend to be in another country.
///
/// ADMINS ONLY, and it is the SERVER that decides: this tile renders an empty
/// box until a fetch comes back saying `available`. Nothing here reads
/// isAdmin, so revoking admin rights removes the option without a new build.
///
/// Why it exists: which events, venues, tracks and clubs somebody sees — and
/// the point every radius is measured from — all come from their stored
/// location. There was no way to see what an American user sees from a desk
/// in Britain, which is how the US event catalogue came to be a narrow strip
/// through Colorado without anybody noticing.
///
/// It does NOT touch the real stored location. That row is written whenever
/// the phone gets a fix and is read by a dozen features; this is a separate
/// override the region queries prefer, so "Use my real location" restores it
/// exactly rather than approximately.
class _TestLocationTile extends StatefulWidget {
  const _TestLocationTile();

  @override
  State<_TestLocationTile> createState() => _TestLocationTileState();
}

class _TestLocationTileState extends State<_TestLocationTile> {
  TestLocationState _state = const TestLocationState();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await TestLocationApi.fetch();
    if (!mounted) return;
    setState(() => _state = state);
  }

  Future<void> _set(String? key) async {
    setState(() => _saving = true);

    final ok = await TestLocationApi.set(key);

    if (!mounted) return;

    if (!ok) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not change the test location')),
      );
      return;
    }

    await _load();

    if (!mounted) return;

    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          key == null
              ? 'Back to your real location'
              : 'Now browsing as if you were there. Reopen Events, Places or '
                    'Groups to see it.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    if (!_state.available) return const SizedBox.shrink();

    final current = _state.current;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public, size: 17, color: theme.primaryColor),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Browse as another country',
                  style: TextStyle(fontSize: 16, color: Colors.black),
                ),
              ),
              if (_saving)
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.primaryColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Admin only. Changes which events, venues, tracks and groups you '
            'see, and where distances are measured from. Your real location '
            'is left alone.',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                theme,
                label: 'My real location',
                selected: current == null,
                onTap: () => _set(null),
              ),
              for (final region in _state.regions)
                _chip(
                  theme,
                  // The site is the part that matters and is not always
                  // guessable from a city name.
                  label: '${region.label} · ${region.site}',
                  selected: current == region.key,
                  onTap: () => _set(region.key),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(
    ThemeProvider theme, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? theme.primaryColor.withValues(alpha: 0.12)
          : const Color(0xFFF4F4F4),
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? theme.primaryColor : Colors.transparent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _saving ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? const Color(0xFF6A5520) : Colors.grey.shade800,
            ),
          ),
        ),
      ),
    );
  }
}
