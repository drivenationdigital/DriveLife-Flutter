import 'package:drivelife/screens/discover/discover_filters.dart';
import 'package:drivelife/screens/discover/discover_place.dart';
import 'package:drivelife/screens/discover/discover_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the Discover results sheet.
///
/// These exist because of a sheet that froze. Its resting height is also its
/// minChildSize, and it was derived from the measured bottom inset — which
/// collapses to zero the moment a keyboard appears. Opening the location
/// search focuses a text field, so every search moved the minimum underneath
/// a live DraggableScrollableSheet. Its controller kept the extent it already
/// had, that extent was now below the new minimum, and the sheet stopped
/// responding to drags. After a few searches it could not be opened at all.
///
/// Note how the surface is configured: via `tester.view`, not by wrapping the
/// tree in a MediaQuery. MaterialApp installs its own MediaQuery from the
/// view and an ancestor one is simply ignored, so the obvious version of this
/// test measures the default 800x600 test window no matter what it is handed,
/// and passes whatever the code does.
void main() {
  /// Configures the surface as a 390x844 phone with a home indicator.
  ///
  /// A keyboard consumes `padding.bottom` — it goes to zero — while
  /// `viewPadding.bottom` keeps reporting the device's real inset. Setting
  /// both is the point: a fake that only moved viewInsets would not reproduce
  /// the original bug.
  void surface(WidgetTester tester, {required bool keyboard}) {
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(390, 844)
      ..viewPadding = const FakeViewPadding(top: 47, bottom: 34)
      ..padding = FakeViewPadding(top: 47, bottom: keyboard ? 0 : 34)
      ..viewInsets = FakeViewPadding(bottom: keyboard ? 336 : 0);
    addTearDown(tester.view.reset);
  }

  /// Renders the sheet's own resting-height calculation and reports it.
  Future<double> restingHeight(WidgetTester tester) async {
    late double captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = DiscoverResultsSheet.collapsedFor(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets('resting height ignores the keyboard', (tester) async {
    surface(tester, keyboard: false);
    final atRest = await restingHeight(tester);

    surface(tester, keyboard: true);
    final withKeyboard = await restingHeight(tester);

    // Identical, not merely close. Any drift at all is enough to push the
    // sheet's extent outside its own bounds and freeze it.
    expect(withKeyboard, atRest);
  });

  testWidgets('resting height leaves room for the floating nav', (
    tester,
  ) async {
    surface(tester, keyboard: false);

    final pixels = await restingHeight(tester) * 844;

    // The cards have to clear the bar the shell floats over this screen; if
    // they do not, the results are permanently half-hidden behind it.
    expect(pixels, greaterThan(DiscoverResultsSheet.footerClearance + 96));
  });

  testWidgets('resting height never takes more than half the screen', (
    tester,
  ) async {
    // A short device: without the clamp the arithmetic wants most of the
    // screen, and the map it would be covering is the point of the screen.
    tester.view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(320, 480)
      ..viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);

    expect(await restingHeight(tester), lessThanOrEqualTo(0.5));
  });

  testWidgets('opens past the height where its layout changes', (
    tester,
  ) async {
    final places = [
      for (var i = 0; i < 6; i++)
        DiscoverPlace.fromVenue({
          'ID': i,
          'title': 'Venue $i',
          'latitude': 54.0 + i / 100,
          'longitude': -1.0,
        })!,
    ];

    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              DiscoverResultsSheet(
                places: places,
                loading: false,
                filters: DiscoverFilters.initial,
                selected: null,
                onTap: (_) {},
                onOpen: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    surface(tester, keyboard: false);
    await pump();
    await tester.pumpAndSettle();

    // Collapsed, the results are a horizontal strip. Dragged up they become
    // a list — so a chevron appearing is proof the sheet actually moved.
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    await tester.fling(find.text('6 nearby'), const Offset(0, -400), 900);
    await tester.pumpAndSettle();

    expect(
      find.byIcon(Icons.chevron_right_rounded),
      findsWidgets,
      reason:
          'the sheet could not be dragged past the height at which the strip '
          'becomes a list - swapping those children mid-drag cancels the '
          'gesture, and it snaps back every time',
    );
  });

  testWidgets('still opens after a keyboard has come and gone', (
    tester,
  ) async {
    final places = [
      for (var i = 0; i < 6; i++)
        DiscoverPlace.fromVenue({
          'ID': i,
          'title': 'Venue $i',
          'latitude': 54.0 + i / 100,
          'longitude': -1.0,
        })!,
    ];

    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              DiscoverResultsSheet(
                places: places,
                loading: false,
                filters: DiscoverFilters.initial,
                selected: null,
                onTap: (_) {},
                onOpen: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    surface(tester, keyboard: false);
    await pump();
    await tester.pumpAndSettle();

    // The location search autofocuses a field, so this happens on every
    // single search. Three of them.
    for (var i = 0; i < 3; i++) {
      surface(tester, keyboard: true);
      await pump();
      await tester.pumpAndSettle();

      surface(tester, keyboard: false);
      await pump();
      await tester.pumpAndSettle();
    }

    await tester.fling(find.text('6 nearby'), const Offset(0, -400), 900);
    await tester.pumpAndSettle();

    expect(
      find.byIcon(Icons.chevron_right_rounded),
      findsWidgets,
      reason: 'a keyboard moved the sheet minimum and froze it',
    );
  });
}
