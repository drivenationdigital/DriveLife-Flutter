import 'package:drivelife/widgets/nav/dl_bottom_nav.dart';
import 'package:drivelife/widgets/nav/dl_top_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout tests for the navigation chrome.
///
/// These exist because of a real crash: the top tab row's underline asked for
/// `width: double.infinity` inside a horizontally scrolling Row, where the
/// available width genuinely IS infinite — so BoxConstraints asserted on the
/// first frame and took the app down on launch. Nothing caught it, because it
/// compiles perfectly and only fails when laid out.
///
/// A widget test is the cheapest thing that would have. Pumping the widget is
/// the whole assertion: `tester.takeException()` returns null only if layout
/// completed without throwing.
void main() {
  const tabs = [
    DlTopTab(label: 'For You', icon: 'assets/app-icons/01-Home.svg'),
    DlTopTab(label: 'Events', icon: 'assets/app-icons/02-Events.svg'),
    DlTopTab(label: 'Places', icon: 'assets/app-icons/03-Venues.svg'),
    DlTopTab(label: 'Groups', icon: 'assets/app-icons/07-groups.svg'),
  ];

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('DlTopTabs', () {
    testWidgets('lays out inside an unbounded horizontal scroll', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(DlTopTabs(tabs: tabs, currentIndex: 0, onChanged: (_) {})),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out with every tab selected in turn', (tester) async {
      // The selected tab is the one that sizes differently, so each has to be
      // laid out as the selected one at least once.
      for (var i = 0; i < tabs.length; i++) {
        await tester.pumpWidget(
          wrap(DlTopTabs(tabs: tabs, currentIndex: i, onChanged: (_) {})),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull, reason: 'selected index $i');
      }
    });

    testWidgets('survives a narrow screen', (tester) async {
      // The row must scroll rather than overflow: four word labels do not fit
      // a small phone, which is why it scrolls in the first place.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(DlTopTabs(tabs: tabs, currentIndex: 3, onChanged: (_) {})),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('DlBottomNav', () {
    testWidgets('lays out five destinations', (tester) async {
      final items = [
        for (final label in ['Home', 'Discover', 'Photos', 'Garage', 'Account'])
          DlNavItem(
            label: label,
            icon: (selected) => const Icon(Icons.circle, size: 22),
          ),
      ];

      await tester.pumpWidget(
        wrap(
          Scaffold(
            bottomNavigationBar: DlBottomNav(
              items: items,
              currentIndex: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Garage'), findsOneWidget);
    });

    testWidgets('the ends are semicircles, not rounded corners', (
      tester,
    ) async {
      // A pill, not a rounded rectangle: the radius has to be half the
      // height, or there is a straight section between the ends and that is
      // what the eye reads as "square".
      final items = [
        for (final label in ['Home', 'Discover', 'Photos', 'Garage', 'Account'])
          DlNavItem(
            label: label,
            icon: (selected) => const Icon(Icons.circle, size: 22),
          ),
      ];

      await tester.pumpWidget(
        wrap(
          Scaffold(
            bottomNavigationBar: DlBottomNav(
              items: items,
              currentIndex: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final bar = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(DlBottomNav),
              matching: find.byType(Container),
            )
            .first,
      );

      final shape = (bar.decoration! as BoxDecoration).borderRadius!
          .resolve(TextDirection.ltr);

      expect(shape.topLeft.x, DlBottomNav.height / 2);
      expect(shape.bottomRight.x, DlBottomNav.height / 2);
    });

    testWidgets('the highlight travels rather than fading', (tester) async {
      final items = [
        for (final label in ['Home', 'Discover', 'Photos', 'Garage', 'Account'])
          DlNavItem(
            label: label,
            icon: (selected) => const Icon(Icons.circle, size: 22),
          ),
      ];

      Future<double> leftAt(int index) async {
        await tester.pumpWidget(
          wrap(
            Scaffold(
              bottomNavigationBar: DlBottomNav(
                items: items,
                currentIndex: index,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        final positioned = tester.widget<AnimatedPositioned>(
          find.byType(AnimatedPositioned),
        );
        return positioned.left!;
      }

      final first = await leftAt(0);
      final fourth = await leftAt(3);

      // One highlight that moves: there is exactly one AnimatedPositioned,
      // and its offset follows the selection. Per-item backgrounds would
      // give no AnimatedPositioned at all, and a cross-fade instead.
      expect(first, 0);
      expect(fourth, greaterThan(first));
    });
  });
}
