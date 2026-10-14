import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the shape of the feed screen's scroll view.
///
/// The feeds used to be a TabBarView of three CustomScrollViews, each with
/// its own copy of the header, the hot row and the feed selector. Switching
/// from Latest to Following therefore slid the whole page sideways and
/// replaced every part of it, when only the posts below the selector should
/// have changed.
///
/// They now share one scroll view: the header and selector are slivers in it,
/// and each feed contributes a SliverMainAxisGroup that is taken offstage
/// when another feed is showing. These tests pin down the two properties
/// that arrangement depends on, without needing the network the real screen
/// talks to.
void main() {
  /// Stands in for the screen: shared chrome, then one group per feed with
  /// only the selected one onstage.
  Widget harness({required int active, required ScrollController controller}) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: controller,
          slivers: [
            const SliverToBoxAdapter(
              child: SizedBox(height: 120, child: Text('chrome')),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _Pinned(
                child: const SizedBox(height: 54, child: Text('selector')),
              ),
            ),
            for (var feed = 0; feed < 2; feed++)
              SliverOffstage(
                offstage: feed != active,
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverList.builder(
                      itemCount: 20,
                      itemBuilder: (_, i) => SizedBox(
                        height: 100,
                        child: Text('feed $feed post $i'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  testWidgets('switching feed leaves the chrome where it was', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(active: 0, controller: controller));
    await tester.pumpAndSettle();

    final selectorBefore = tester.getRect(find.text('selector'));
    expect(find.text('feed 0 post 0'), findsOneWidget);
    expect(find.text('feed 1 post 0'), findsNothing);

    await tester.pumpWidget(harness(active: 1, controller: controller));
    await tester.pumpAndSettle();

    // The whole point: the selector has not moved, and the posts have
    // changed underneath it.
    expect(tester.getRect(find.text('selector')), selectorBefore);
    expect(find.text('feed 0 post 0'), findsNothing);
    expect(find.text('feed 1 post 0'), findsOneWidget);
  });

  testWidgets('switching feed keeps the scroll position', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(active: 0, controller: controller));
    await tester.pumpAndSettle();

    controller.jumpTo(400);
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness(active: 1, controller: controller));
    await tester.pumpAndSettle();

    // One scroll view means one position. Three separate ones each had their
    // own, which is the other half of why the page appeared to jump.
    expect(controller.offset, 400);
  });

  testWidgets('an offstage feed takes up no room', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(active: 0, controller: controller));
    await tester.pumpAndSettle();

    // 120 chrome + 54 selector + 20 posts of 100 = 2174, less the viewport.
    // If the hidden feed contributed its own 2000 the extent would double,
    // and the scrollbar would describe a feed twice as long as it is.
    final extent = controller.position.maxScrollExtent;
    final viewport = tester.getSize(find.byType(CustomScrollView)).height;

    expect(extent + viewport, closeTo(120 + 54 + 2000, 1));
  });
}

class _Pinned extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _Pinned({required this.child});

  @override
  double get minExtent => 54;

  @override
  double get maxExtent => 54;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(color: Colors.white, child: child);

  @override
  bool shouldRebuild(_Pinned old) => old.child != child;
}
