import 'package:drivelife/main.dart' show BottomNavProvider;
import 'package:drivelife/widgets/feed/hot_right_now.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Tests for the "Hot right now" shortcuts on the feed.
///
/// These exist because the tiles navigated with bare integers — 1, 2, 3, from
/// a bottom bar that has since been reordered twice. The numbers stayed valid
/// and quietly started meaning something else: "Find Events" opened the map
/// by accident, "Popular Venues" opened Groups, "Discover Groups" opened
/// Photos. Nothing crashed, nothing looked broken, and it survived two rounds
/// of changes before anyone noticed.
///
/// So each tile is held to its destination here. Tapping is the test, not
/// reading the callback: it is the tap that was wrong.
///
/// Each card puts a full-bleed InkWell over itself, so a tap aimed at the
/// label lands on that instead — hence warnIfMissed. The tap still reaches
/// the handler, which is what these assert.
///
/// "Your Garage" is not here. It pushes GarageListScreen rather than moving
/// the navigation, and that screen needs providers and a network this
/// harness has no business standing up. It is covered below only as far as
/// having a label and being present.
void main() {
  /// Renders the row over a real provider and returns it, so a tap can be
  /// checked against where it actually went.
  Future<BottomNavProvider> pumpRow(WidgetTester tester) async {
    final nav = BottomNavProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<BottomNavProvider>.value(
        value: nav,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: HotRightNow())),
        ),
      ),
    );
    await tester.pump();

    return nav;
  }

  testWidgets('Find Events opens the Events section of Home', (tester) async {
    final nav = await pumpRow(tester);

    await tester.tap(find.text('Find Events'), warnIfMissed: false);
    await tester.pump();

    // Both halves: Events is a section of Home, so landing on Home with the
    // wrong section showing would be just as wrong as landing elsewhere.
    expect(nav.currentIndex, BottomNavProvider.home);
    expect(nav.homeSection, BottomNavProvider.events);
  });

  testWidgets('Popular Venues opens the Places section of Home', (
    tester,
  ) async {
    final nav = await pumpRow(tester);

    await tester.tap(find.text('Popular Venues'), warnIfMissed: false);
    await tester.pump();

    // Both halves: Places is a section of Home, so landing on Home with the
    // wrong section showing would be just as wrong as landing elsewhere.
    expect(nav.currentIndex, BottomNavProvider.home);
    expect(nav.homeSection, BottomNavProvider.places);
  });

  testWidgets('Discover Groups opens Groups', (tester) async {
    final nav = await pumpRow(tester);

    await tester.tap(find.text('Discover Groups'), warnIfMissed: false);
    await tester.pump();

    expect(nav.currentIndex, BottomNavProvider.groups);
  });

  testWidgets('every tile has a label and goes somewhere', (tester) async {
    await pumpRow(tester);

    expect(HotRightNow.items, isNotEmpty);

    for (final shortcut in HotRightNow.items) {
      expect(
        shortcut.title.trim(),
        isNotEmpty,
        reason: 'a tile with no label is a tile nobody can describe',
      );
      expect(find.text(shortcut.title), findsOneWidget);
    }
  });
}
