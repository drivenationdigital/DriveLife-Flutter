import 'package:drivelife/screens/discover/discover_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the Discover location gate.
///
/// Discover is built entirely around "what is near me" — every fetch is a
/// radius around a point — so without a position there is nothing to show.
/// The part worth pinning down is that each obstacle offers the button that
/// actually clears it: "Open settings" for something the app can still ask
/// for sends people on a detour, and "Allow" for a permanently refused
/// permission is a button that visibly does nothing when pressed.
void main() {
  Future<void> show(WidgetTester tester, DiscoverAccess access) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoverLocationGate(access: access, onResolve: () async {}),
      ),
    );
  }

  testWidgets('shows a spinner while the first check runs', (tester) async {
    await show(tester, DiscoverAccess.checking);

    // Not a permission prompt: the screen does not yet know one is needed,
    // and flashing "Allow location" at someone who has already allowed it
    // reads as the app forgetting.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Turn on location'), findsNothing);
  });

  testWidgets('offers to ask again when permission was merely denied', (
    tester,
  ) async {
    await show(tester, DiscoverAccess.denied);

    expect(find.text('Allow location'), findsOneWidget);
  });

  testWidgets('sends you to app settings when denied forever', (tester) async {
    await show(tester, DiscoverAccess.deniedForever);

    // Asking again would return immediately without showing anything.
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('Allow location'), findsNothing);
  });

  testWidgets('sends you to location settings when services are off', (
    tester,
  ) async {
    await show(tester, DiscoverAccess.servicesOff);

    // The permission is not the problem here; the device's location is off,
    // and no amount of granting will help.
    expect(find.text('Open location settings'), findsOneWidget);
    expect(find.text('Allow location'), findsNothing);
  });

  testWidgets('every blocked state offers exactly one action', (tester) async {
    for (final access in [
      DiscoverAccess.denied,
      DiscoverAccess.deniedForever,
      DiscoverAccess.servicesOff,
    ]) {
      await show(tester, access);

      expect(
        find.byType(FilledButton),
        findsOneWidget,
        reason: '$access should offer one way out, not none and not a choice',
      );
      expect(find.text('Turn on location'), findsOneWidget);
    }
  });

  testWidgets('the action is wired up', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoverLocationGate(
          access: DiscoverAccess.denied,
          onResolve: () async => pressed++,
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(pressed, 1);
  });
}
