import 'package:drivelife/screens/clubs/add_club_screen.dart';
import 'package:drivelife/screens/clubs/club_creation_screen.dart';
import 'package:flutter/material.dart';

/// Starts a new club or group.
///
/// Two steps, and both are needed: the sheet asks what KIND of group this
/// is and creates the row, and the screen after it fills the row in. A
/// caller that pushed CreateClubScreen on its own would land somebody on
/// an edit form for a club that does not exist yet.
///
/// One place for that sequence so the entry points — the Create menu and
/// the "Run a club?" card on the home page — cannot drift apart, which is
/// how one of them ends up skipping the sheet.
Future<void> openClubCreator(BuildContext context) async {
  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const ClubTypeSelectionSheet(),
  );

  // Backed out of the sheet, or it closed without creating anything.
  if (!context.mounted || result == null || result['clubId'] == null) return;

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CreateClubScreen(existingClubId: result['clubId']),
    ),
  );
}
