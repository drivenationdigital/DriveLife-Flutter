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

    // int? userIdInt;
    // final userId = user.id;
    // if (userId != null) {
    //   if (userId is int) {
    //     userIdInt = userId;
    //   } else if (userId is String) {
    //     userIdInt = int.tryParse(userId);
    //   } else {
    //     userIdInt = int.tryParse(userId.toString());
    //   }
    // }

    // ✅ Pass showAppBar: false to hide the app bar
    return ViewProfileScreen(
      userId: user.id,
      username: user.username?.toString() ?? '',
      showAppBar: false, // ✅ Don't show app bar (HomeTabs will handle it)
    );
  }
}
