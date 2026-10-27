import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tapping the vehicle page's cover photo.
///
/// The hero is a Stack: the photo, a gradient over it that fades into the
/// black panel below, and the back and share buttons on top. Making the
/// photo tappable looks like one line and is not, because two things in
/// that arrangement quietly eat the tap.
///
/// The first is the gradient. A DecoratedBox filling a Stack ABSORBS
/// pointer events — it has a size and it is above the photo, so every tap
/// lands on it and stops. The cover looked tappable and did nothing. It
/// needs an IgnorePointer, which is what the first test here pins.
///
/// The second is the GestureDetector's own behaviour. The default defers to
/// its child, and the real child is a CachedNetworkImage that swaps between
/// a placeholder, the image and an error widget — so the tap would work or
/// not depending on which was showing. Explicit opaque removes that.
///
/// Neither failure reports anything. The button simply does not respond,
/// which is why this is a test and not a comment.
///
/// Reproduced rather than imported: the real hero needs a loaded vehicle and
/// three providers. The arrangement is what is under test, and it is copied
/// here exactly.
void main() {
  late List<String> taps;

  const gradient = BoxDecoration(
    gradient: LinearGradient(colors: [Colors.black12, Colors.black]),
  );

  Widget hero({
    required bool ignorePointer,
    HitTestBehavior? behavior = HitTestBehavior.opaque,
  }) {
    taps = [];

    const tint = DecoratedBox(decoration: gradient);

    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: behavior,
                onTap: () => taps.add('photo'),
                child: const ColoredBox(color: Colors.blue),
              ),

              if (ignorePointer) const IgnorePointer(child: tint) else tint,

              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => taps.add('back'),
                      child: Container(
                        width: 42,
                        height: 42,
                        color: Colors.white,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => taps.add('share'),
                      child: Container(
                        width: 42,
                        height: 42,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('an un-ignored gradient eats the tap', (tester) async {
    // The bug, pinned. If a Flutter release ever stops doing this, this
    // test fails and the IgnorePointer becomes unnecessary — which is worth
    // being told about rather than carrying for ever.
    await tester.pumpWidget(hero(ignorePointer: false));
    await tester.tapAt(const Offset(200, 200));
    await tester.pump();

    expect(taps, isEmpty, reason: 'the gradient is over the photo');
  });

  testWidgets('with IgnorePointer the photo takes the tap', (tester) async {
    await tester.pumpWidget(hero(ignorePointer: true));
    await tester.tapAt(const Offset(200, 200));
    await tester.pump();

    expect(taps, ['photo']);
  });

  testWidgets('the buttons still win their own taps', (tester) async {
    await tester.pumpWidget(hero(ignorePointer: true));

    // Back: left 16, top 8, 42 square.
    await tester.tapAt(const Offset(37, 29));
    await tester.pump();
    expect(taps, ['back'], reason: 'the photo must not steal this');

    // Share: the same, flush to the right of an 800-wide test view.
    await tester.tapAt(const Offset(763, 29));
    await tester.pump();
    expect(taps, ['back', 'share']);
  });

  testWidgets('the gap between the buttons falls through to the photo', (
    tester,
  ) async {
    await tester.pumpWidget(hero(ignorePointer: true));

    // Between the two, on their row. The Row holding them is not opaque,
    // so this belongs to the photo.
    await tester.tapAt(const Offset(400, 29));
    await tester.pump();

    expect(taps, ['photo']);
  });

  testWidgets('deferToChild would depend on what the image is showing', (
    tester,
  ) async {
    // Here the child is a ColoredBox, which does hit-test, so the default
    // happens to work. In the real hero the child is a CachedNetworkImage
    // mid-swap between three different widgets — this is exactly the kind
    // of "works on my machine" the explicit opaque removes.
    await tester.pumpWidget(hero(ignorePointer: true, behavior: null));
    await tester.tapAt(const Offset(200, 200));
    await tester.pump();

    expect(taps, ['photo'], reason: 'a ColoredBox hit-tests; not everything does');
  });
}
