import 'package:drivelife/models/account_model.dart';
import 'package:drivelife/providers/account_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';

class EntitySwitcherSheet extends StatelessWidget {
  const EntitySwitcherSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final accountManager = Provider.of<AccountManager>(context);
    final theme = Provider.of<ThemeProvider>(context);

    // Safety check - close sheet if no accounts
    if (accountManager.activeAccount == null ||
        accountManager.accounts.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pop(context);
        }
      });
      return SizedBox.shrink();
    }

    final activeAccount = accountManager.activeAccount!;
    final currentUserId = activeAccount.isEntityAccount
        ? activeAccount.parentUserId!
        : activeAccount.user.id;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Switch Profile',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Current user + their entities
            _buildUserSection(
              context,
              userId: currentUserId,
              accounts: accountManager.accounts,
              activeAccount: activeAccount,
            ),

            // Other user accounts
            if (accountManager.userAccounts.length > 1) ...[
              const Divider(height: 1),
              _buildOtherUsersSection(
                context,
                currentUserId: currentUserId,
                userAccounts: accountManager.userAccounts,
                activeAccount: activeAccount,
              ),
            ],

            const Divider(height: 1),

            // Add Account
            ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.primaryColor.withOpacity(0.1),
                child: Icon(Icons.add, color: theme.primaryColor),
              ),
              title: Text(
                'Add Account',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.primaryColor,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.login);
              },
            ),

            const SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.red.withOpacity(0.1),
                child: Icon(Icons.logout, color: Colors.red),
              ),
              title: Text(
                'Logout All Accounts',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Logout All'),
                    content: const Text(
                      'Remove all accounts from this device?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Logout All'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && context.mounted) {
                  Navigator.pop(
                    context,
                  ); // ✅ Close the entity switcher sheet first

                  await accountManager.clearAll();

                  if (context.mounted) {
                    // ✅ Use pushNamedAndRemoveUntil to clear all navigation stack
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pushNamedAndRemoveUntil(
                      AppRoutes.login,
                      (route) => false,
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserSection(
    BuildContext context, {
    required int userId,
    required List<Account> accounts,
    required Account activeAccount,
  }) {
    final accountManager = Provider.of<AccountManager>(context, listen: false);

    // Get main user account for this userId
    final userAccount = accounts.firstWhere(
      (a) => a.isUserAccount && a.user.id == userId,
    );

    // ✅ Get entities ONLY for this specific user
    final entities = accounts
        .where((a) => a.isEntityAccount && a.parentUserId == userId)
        .toList();

    print(
      '👤 User ${userAccount.user.username} has ${entities.length} entities',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main user account
        _buildAccountTile(
          context,
          account: userAccount,
          isActive:
              userAccount.user.id == activeAccount.user.id &&
              activeAccount.isUserAccount,
          icon: Icons.person,
        ),

        // User's clubs/venues
        // if (entities.isNotEmpty) ...[
        //   Padding(
        //     padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        //     child: Text(
        //       'YOUR PAGES',
        //       style: TextStyle(
        //         fontSize: 11,
        //         fontWeight: FontWeight.w600,
        //         color: Colors.grey,
        //         letterSpacing: 0.5,
        //       ),
        //     ),
        //   ),
        //   ...entities.map((entity) {
        //     print(
        //       '🏢 Entity: ${entity.user.username}, Type: ${entity.accountType}, ID: ${entity.user.id}',
        //     );

        //     return _buildAccountTile(
        //       context,
        //       account: entity,
        //       isActive:
        //           entity.user.id == activeAccount.user.id &&
        //           entity.accountType == activeAccount.accountType,
        //       icon: entity.isClubAccount ? Icons.car_repair : Icons.place,
        //       isEntity: true,
        //     );
        //   }).toList(),
        // ],
      ],
    );
  }

  Widget _buildOtherUsersSection(
    BuildContext context, {
    required int currentUserId,
    required List<Account> userAccounts,
    required Account activeAccount,
  }) {
    // ✅ Only show OTHER user accounts, not the current one
    final otherUsers = userAccounts
        .where((a) => a.user.id != currentUserId)
        .toList();

    if (otherUsers.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'OTHER ACCOUNTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...otherUsers
            .map(
              (account) => _buildAccountTile(
                context,
                account: account,
                isActive:
                    account.user.id == activeAccount.user.id &&
                    activeAccount.isUserAccount,
                icon: Icons.person,
              ),
            )
            .toList(),
      ],
    );
  }

  Widget _buildAccountTile(
    BuildContext context, {
    required Account account,
    required bool isActive,
    required IconData icon,
    bool isEntity = false,
  }) {
    final theme = Provider.of<ThemeProvider>(context);
    final accountManager = Provider.of<AccountManager>(context, listen: false);

    String subtitle = '';
    if (account.isUserAccount) {
      subtitle = '@${account.user.username}';
    } else if (account.isClubAccount) {
      final memberCount = account.entityMeta?['member_count'] ?? 0;
      subtitle = '$memberCount members';
    } else if (account.isVenueAccount) {
      subtitle = 'Venue';
    }

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: isEntity ? 18 : 20,
        backgroundColor: theme.primaryColor.withOpacity(0.1),
        backgroundImage: account.user.profileImage != null
            ? NetworkImage(account.user.profileImage!)
            : null,
        child: account.user.profileImage == null
            ? Icon(icon, color: theme.primaryColor, size: isEntity ? 16 : 20)
            : null,
      ),
      title: Text(
        account.user.fullName.isNotEmpty
            ? account.user.fullName
            : account.user.username,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          fontSize: isEntity ? 14 : 16,
        ),
      ),
      subtitle: Text(subtitle, style: TextStyle(fontSize: isEntity ? 12 : 14)),
      trailing: isActive
          ? Icon(Icons.check_circle, color: theme.primaryColor)
          : null,
      onTap: isActive
          ? null
          : () => _switchToAccount(context, account, accountManager),
    );
  }

  Future<void> _switchToAccount(
    BuildContext context,
    Account account,
    AccountManager accountManager,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator(color: Color(0xFFAE9159))),
    );

    final index = accountManager.accounts.indexOf(account);

    await accountManager.switchAccount(index);

    if (context.mounted) {
      Navigator.pop(context); // Close loading
      Navigator.pop(context); // Close switcher
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.home,
        (route) => false,
      );
    }
  }
}
