import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the feed's floating header.
///
/// These exist because of a crash that nothing else could catch. A floating
/// sliver header that declares a snapConfiguration must also supply a vsync,
/// or it asserts "vsync must not be null if the floating header changes size
/// animatedly" — and that only runs when a drag ENDS and the snap begins.
///
/// So it compiled, it laid out, it scrolled, and it died the first time a
/// finger left the screen. Pumping a drag is not enough; the test has to let
/// go and settle.
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

  testWidgets('snaps on release without asserting', (tester) async {
    await tester.pumpWidget(
      _TickerHost(builder: (vsync) => harness(vsync: vsync)),
    );

    expect(find.text('chrome'), findsOneWidget);

    // A drag that is released. The release is the whole point — the snap
    // animation starts there, and that is where the missing vsync threw.
    await tester.fling(find.byType(CustomScrollView), const Offset(0, -300), 800);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // And back up, which snaps it open again.
    await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 800);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('chrome'), findsOneWidget);
  });

  testWidgets('leaves view as the feed is read', (tester) async {
    await tester.pumpWidget(
      _TickerHost(builder: (vsync) => harness(vsync: vsync)),
    );

    await tester.fling(find.byType(CustomScrollView), const Offset(0, -900), 900);
    await tester.pumpAndSettle();

    // Floating, not pinned: once scrolled past, it is gone until asked back.
    expect(find.text('chrome'), findsNothing);
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
