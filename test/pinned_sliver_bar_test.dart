import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:drivelife/widgets/nav/pinned_sliver_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two headers a listing screen stacks: chrome that floats away, and
/// tabs that do not.
///
/// Places and Tracks both put the shell's header and their own search field
/// in a floating sliver and their tabs in a pinned one. Getting those the
/// wrong way round loses you the navigation halfway down a grid, which is
/// exactly when you want it — the way out of a list you don't like is to
/// change tab or change the filter.
void main() {
  Widget harness({required TickerProvider vsync}) => MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            floating: true,
            delegate: FloatingChromeHeader(
              height: 120,
              vsync: vsync,
              child: const Text('chrome'),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: const PinnedSliverBar(height: 48, child: Text('tabs')),
          ),
          SliverList.builder(
            itemCount: 40,
            itemBuilder: (_, i) => SizedBox(height: 90, child: Text('row $i')),
          ),
        ],
      ),
    ),
  );

  testWidgets('the tabs stay and the chrome goes', (tester) async {
    await tester.pumpWidget(
      _TickerHost(builder: (vsync) => harness(vsync: vsync)),
    );

    expect(find.text('chrome'), findsOneWidget);
    expect(find.text('tabs'), findsOneWidget);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -900),
      900,
    );
    await tester.pumpAndSettle();

    expect(find.text('chrome'), findsNothing);
    expect(find.text('tabs'), findsOneWidget);
  });

  testWidgets('the tabs hold the top edge once reached', (tester) async {
    await tester.pumpWidget(
      _TickerHost(builder: (vsync) => harness(vsync: vsync)),
    );

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -900),
      900,
    );
    await tester.pumpAndSettle();

    final first = tester.getTopLeft(find.text('tabs'));

    // Further down the list, it must not have moved.
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -900),
      900,
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('tabs')), first);
  });

  testWidgets('the chrome comes back on scrolling up', (tester) async {
    await tester.pumpWidget(
      _TickerHost(builder: (vsync) => harness(vsync: vsync)),
    );

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -900),
      900,
    );
    await tester.pumpAndSettle();
    expect(find.text('chrome'), findsNothing);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 600),
      800,
    );
    await tester.pumpAndSettle();

    expect(find.text('chrome'), findsOneWidget);
  });

  test('rebuilds only when something changed', () {
    const a = PinnedSliverBar(height: 48, child: Text('tabs'));

    expect(a.shouldRebuild(a), isFalse);
    expect(
      a.shouldRebuild(const PinnedSliverBar(height: 56, child: Text('tabs'))),
      isTrue,
    );
  });
}

/// Supplies a real TickerProvider, as each screen's State does.
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
