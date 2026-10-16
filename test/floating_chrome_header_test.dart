import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the feed's floating header.
///
/// Two bugs live here, and they pull in opposite directions.
///
/// The first was a crash: a floating sliver header that declares a
/// snapConfiguration must also supply a vsync, or it asserts "vsync must not
/// be null if the floating header changes size animatedly" — and that only
/// runs when a drag ENDS and the snap begins. It compiled, it laid out, it
/// scrolled, and it died the first time a finger left the screen.
///
/// The second was the snap itself. Flutter starts it when the scroll goes
/// quiet and picks the target from the direction at that moment:
///
/// ```dart
/// direction == ScrollDirection.forward ? 0.0 : maxExtent
/// ```
///
/// By the time a settled feed is touched again the direction has gone back
/// to idle, which is not forward — so the header animated away under the
/// reader's thumb. There is no way to narrow that from a delegate, so the
/// snap is gone and the header simply follows the scroll.
void main() {
  Widget harness({required TickerProvider vsync}) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              floating: true,
              delegate: FloatingChromeHeader(
                height: 120,
                vsync: vsync,
                child: const Text('chrome'),
              ),
            ),
            SliverList.builder(
              itemCount: 60,
              itemBuilder: (_, i) =>
                  SizedBox(height: 90, child: Text('item $i')),
            ),
          ],
        ),
      ),
    ),
  );

  test('does not snap', () {
    // The whole fix, stated once. A delegate cannot override which direction
    // Flutter snaps towards, only whether it snaps at all — so if this ever
    // comes back, the header starts vanishing on touch again.
    final delegate = FloatingChromeHeader(
      height: 120,
      vsync: const TestVSync(),
      child: const SizedBox(),
    );

    expect(delegate.snapConfiguration, isNull);
  });

  testWidgets('survives a drag being released', (tester) async {
    await tester.pumpWidget(
      _TickerHost(builder: (vsync) => harness(vsync: vsync)),
    );

    expect(find.text('chrome'), findsOneWidget);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -300),
      800,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 300),
      800,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('chrome'), findsOneWidget);
  });

  testWidgets('leaves view as the feed is read', (tester) async {
    await tester.pumpWidget(
      _TickerHost(builder: (vsync) => harness(vsync: vsync)),
    );

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -900),
      900,
    );
    await tester.pumpAndSettle();

    // Floating, not pinned: once scrolled past, it is gone until asked back.
    expect(find.text('chrome'), findsNothing);
  });

  testWidgets('stays put when the feed is touched but not scrolled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TickerHost(builder: (vsync) => harness(vsync: vsync)),
    );

    // Down the feed, then part of the way back — the header is showing
    // again, which is the state the bug was reported from.
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -900),
      900,
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      600,
    );
    await tester.pumpAndSettle();

    expect(find.text('chrome'), findsOneWidget);
    final before = tester.getTopLeft(find.text('chrome'));

    // A finger put down and lifted again, no movement. Someone holding the
    // phone, or steadying it to read.
    final touch = await tester.startGesture(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 120));
    await touch.up();
    await tester.pumpAndSettle();

    expect(find.text('chrome'), findsOneWidget);
    expect(tester.getTopLeft(find.text('chrome')), before);
  });
}

/// Supplies a real TickerProvider, as the feed's own State does.
class _TickerHost extends StatefulWidget {
  final Widget Function(TickerProvider vsync) builder;

  const _TickerHost({required this.builder});

  @override
  State<_TickerHost> createState() => _TickerHostState();
}

class _TickerHostState extends State<_TickerHost>
    with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => widget.builder(this);
}
