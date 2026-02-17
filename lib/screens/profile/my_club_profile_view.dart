import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/screens/profile/view_club_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ClubProfileScreen extends StatelessWidget {
  const ClubProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accountManager = Provider.of<AccountManager>(context);
    final clubAccount = accountManager.activeAccount;

    if (clubAccount == null || !clubAccount.isClubAccount) {
      return const SizedBox.shrink();
    }

    final clubPostId = clubAccount.entityMeta?['club_post_id'];

    // ✅ Same pattern as ProfileScreen → ViewProfileScreen
    return ClubViewScreen(
      clubPostId: clubPostId,
      showAppBar: false, // HomeTabs handles the app bar
      isOwnClub: true, // Show owner UI
    );
  }
}
