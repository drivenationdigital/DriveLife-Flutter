import 'package:drivelife/widgets/nav/dl_top_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The unread badge on a top tab.
///
/// The height assertion is the one that matters. DlTopTabs declares
/// [DlTopTabs.height] to the sliver header above it, and a sliver believes
/// the number it is given: anything that makes the row taller than 56
/// overflows rather than growing the header. That is exactly how the 4px
/// overflow on Home, Places and Tracks happened, so the badge — which hangs
/// off the top of the icon chip — gets pinned here rather than eyeballed.
void main() {
  const tabs = [
    DlTopTab(label: 'For You', icon: 'assets/app-icons/01-Home.svg'),
    DlTopTab(label: 'Shop', icon: 'assets/app-icons/04-Basket.svg'),
    DlTopTab(label: 'Messages', glyph: Icons.chat_bubble),
  ];

  Widget wrap(Map<int, int> badges, {int selected = 0}) => MaterialApp(
    home: Scaffold(
      body: DlTopTabs(
        tabs: tabs,
        currentIndex: selected,
        onChanged: (_) {},
        badges: badges,
      ),
    ),
  );

  testWidgets('no badge when there is nothing unread', (tester) async {
    await tester.pumpWidget(wrap(const {}));
    expect(find.text('0'), findsNothing);

    // An explicit zero is the same as no entry at all — a tab does not get
    // a badge reading "0" the moment the count is wired up.
    await tester.pumpWidget(wrap(const {2: 0}));
    expect(find.text('0'), findsNothing);
  });

  testWidgets('shows the count', (tester) async {
    await tester.pumpWidget(wrap(const {2: 7}));
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('caps at 99+', (tester) async {
    // Uncapped, a four-digit badge widens the tab, and the row scrolls the
    // selected tab into view by measuring widths.
    await tester.pumpWidget(wrap(const {2: 2451}));

    expect(find.text('2451'), findsNothing);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('the badge does not make the row taller', (tester) async {
    for (final badges in <Map<int, int>>[
      {},
      {2: 1},
      {2: 99},
      {2: 1000},
      {0: 5, 1: 5, 2: 5},
    ]) {
      await tester.pumpWidget(wrap(badges));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.getSize(find.byType(DlTopTabs)).height,
        DlTopTabs.height,
        reason: 'badges: $badges',
      );
      expect(tester.takeException(), isNull, reason: 'badges: $badges');
    }
  });

  testWidgets('a badge on the selected tab lays out too', (tester) async {
    // The selected tab is the one that sizes differently, so it gets its
    // own pass.
    await tester.pumpWidget(wrap(const {2: 12}, selected: 2));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('12'), findsOneWidget);
    expect(tester.getSize(find.byType(DlTopTabs)).height, DlTopTabs.height);
    expect(tester.takeException(), isNull);
  });
}
