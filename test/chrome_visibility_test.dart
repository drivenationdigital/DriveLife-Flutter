import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Behaviour tests for the scroll-driven chrome.
///
/// Both of these cover a real failure. The first version read scroll offsets,
/// which fed back on itself — hiding the header shortened the viewport, the
/// new metrics arrived as another notification, and the toggling ate the
/// gesture so the feed could not be scrolled at all. It also set its value
/// straight from the notification, which can arrive during layout, and threw
/// "Build scheduled during frame".
///
/// Driving a real ListView rather than hand-built notifications is the point:
/// a fake notification would not reproduce either bug.
void main() {
  late ChromeVisibility chrome;

  setUp(() => chrome = ChromeVisibility());
  tearDown(() => chrome.dispose());

  Widget harness() => MaterialApp(
    home: Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: chrome.handle,
        child: ListView.builder(
          itemCount: 100,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('item $i')),
        ),
      ),
    ),
  );

  testWidgets('starts visible', (tester) async {
    await tester.pumpWidget(harness());
    expect(chrome.value, isTrue);
  });

  testWidgets('hides when the reader scrolls down the page', (tester) async {
    await tester.pumpWidget(harness());

    // Finger up the screen = content moving down = reading onward.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(chrome.value, isFalse);
  });

  testWidgets('comes back when they scroll up', (tester) async {
    await tester.pumpWidget(harness());

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(chrome.value, isFalse, reason: 'should be hidden first');

    // Back up the page, but not all the way to the top — otherwise this
    // would pass on the at-the-top rule rather than on direction.
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(chrome.value, isTrue);
  });

  testWidgets('a small upward nudge does not bring it back', (tester) async {
    // The complaint this is for: scrolling back "even slightly" popped the
    // whole header and bottom bar in, which reads as the layout twitching
    // rather than as a deliberate reveal.
    await tester.pumpWidget(harness());

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(chrome.value, isFalse, reason: 'should be hidden first');

    // Well under the show threshold, and nowhere near the top.
    await tester.drag(find.byType(ListView), const Offset(0, 40));
    await tester.pumpAndSettle();

    expect(chrome.value, isFalse);
  });

  testWidgets('always shows at the top', (tester) async {
    await tester.pumpWidget(harness());

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(chrome.value, isFalse);

    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();

    expect(chrome.value, isTrue);
  });

  testWidgets('scrolling actually moves the list while chrome reacts', (
    tester,
  ) async {
    // The jam this is guarding against: the chrome toggling on its own
    // layout consumed the gesture, and the list stayed where it was.
    await tester.pumpWidget(harness());

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;

    expect(position.pixels, 0);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(300));
    expect(tester.takeException(), isNull);
  });
}
