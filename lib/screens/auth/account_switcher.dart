import 'package:drivelife/providers/account_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';

class AccountSwitcherSheet extends StatelessWidget {
  const AccountSwitcherSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final accountManager = Provider.of<AccountManager>(context);
    final theme = Provider.of<ThemeProvider>(context);

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
                    'Switch Account',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.textColor,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Account List
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: accountManager.accounts.length,
              itemBuilder: (context, index) {
                final account = accountManager.accounts[index];
                final isActive =
                    index ==
                    accountManager.accounts.indexOf(
                      accountManager.activeAccount!,
                    );

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.primaryColor.withOpacity(0.1),
                    backgroundImage: account.user.profileImage != null
                        ? NetworkImage(account.user.profileImage!)
                        : null,
                    child: account.user.profileImage == null
                        ? Text(
                            account.user.firstName[0].toUpperCase(),
                            style: TextStyle(color: theme.primaryColor),
                          )
                        : null,
                  ),
                  title: Text(
                    account.user.fullName,
                    style: TextStyle(
                      fontWeight: isActive
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text('@${account.user.username}'),
                  trailing: isActive
                      ? Icon(Icons.check_circle, color: theme.primaryColor)
                      : null,
                  onTap: isActive
                      ? null
                      : () async {
                          // Show loading
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) =>
                                Center(child: CircularProgressIndicator(
                                color: Color(0xFFAE9159),
                              )),
                          );

                          await accountManager.switchAccount(index);

                          if (context.mounted) {
                            // Close loading dialog
                            Navigator.pop(context);
                            // Close account switcher
                            Navigator.pop(context);

                            // Force reload entire app
                            Navigator.pushNamedAndRemoveUntil(
                              context,
                              AppRoutes.home,
                              (route) => false,
                            );
                          }
                        },
                );
              },
            ),

            const Divider(height: 1),

            // Add Account Button
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
                  await accountManager.clearAll();
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    AppRoutes.login,
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
