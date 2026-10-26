import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import 'view_profile_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;

    if (userProvider.isLoading) {
      return Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: Text(
            'Please login to view your profile',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return ViewProfileScreen(
      userId: user.id,
      username: user.username.toString(),
      // true, because this is a pushed route now rather than a bottom-bar
      // tab. The account avatar moved to the header, so there is no shell
      // header above this screen any more — with showAppBar false it had
      // no header and no way back at all.
      showAppBar: true,
    );
  }
}
