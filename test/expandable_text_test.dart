import 'package:drivelife/widgets/expandable_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The thing worth testing here is the DECISION, not the drawing:
/// whether the toggle appears at all. Getting that backwards gives
/// either a "Read more" under a single line, or a YouTube description
/// that silently runs to three lines and stops with no way to see the
/// rest - and both look like a finished feature.
void main() {
  const style = TextStyle(fontSize: 14, height: 1.45);

  // Long enough to pass three lines at 300px wide, short enough that
  // the EXPANDED version still fits the 600px test viewport - a tap
  // target below the fold is one tester.tap() cannot reach.
  final long = List.filled(40, 'words').join(' ');
  final alsoLong = List.filled(40, 'other').join(' ');
  const toggleStyle = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800);
  const linkStyle = TextStyle(fontSize: 14, color: Color(0xFFAE9159));

  Future<void> pump(WidgetTester tester, String text) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Scrollable, because expanded text is taller than the
          // 600px test viewport and Flutter raises an overflow as a
          // test failure. The real screen is a ListView, so this
          // matches it rather than working around it.
          body: SingleChildScrollView(
            child: SizedBox(
              // A realistic column width, so the measurement is a
              // realistic one.
              width: 300,
              child: ExpandableText(
                text,
                style: style,
                toggleStyle: toggleStyle,
              linkStyle: linkStyle,
                maxLines: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('short text gets no toggle', (tester) async {
    await pump(tester, 'A quick lap of Goodwood.');

    expect(find.text('Read more'), findsNothing);
    expect(find.text('Show less'), findsNothing);
  });

  testWidgets('long text gets one', (tester) async {
    await pump(tester, long);

    expect(find.text('Read more'), findsOneWidget);
  });

  testWidgets('tapping opens and closes it', (tester) async {
    await pump(tester, long);

    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();

    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('Read more'), findsNothing);

    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();

    expect(find.text('Read more'), findsOneWidget);
  });

  testWidgets('empty text draws nothing at all', (tester) async {
    await pump(tester, '   ');

    // Not an empty Text with padding round it - nothing.
    expect(find.byType(Text), findsNothing);
  });

  _linkTests();

  testWidgets('a new description starts closed again', (tester) async {
    // Opening one video's notes and moving to the next should not
    // show the next one already expanded.
    await pump(tester, long);

    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();

    expect(find.text('Show less'), findsOneWidget);

    await pump(tester, alsoLong);
    await tester.pumpAndSettle();

    expect(find.text('Read more'), findsOneWidget);
    expect(find.text('Show less'), findsNothing);
  });
}

/// Links are the half of this that fails silently: a description full
/// of URLs that renders as plain grey text looks exactly like one that
/// works, until somebody tries to tap a sponsor link.
void _linkTests() {
  testWidgets('a URL becomes its own styled span', (tester) async {
    const linkColour = Color(0xFFAE9159);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 300,
              child: ExpandableText(
                'Gear I use: example.com/kit and mail me at hi@example.com',
                style: TextStyle(fontSize: 14),
                toggleStyle: TextStyle(fontSize: 13.5),
                linkStyle: TextStyle(fontSize: 14, color: linkColour),
              ),
            ),
          ),
        ),
      ),
    );

    final rich = tester.widget<Text>(find.byType(Text).first);
    final span = rich.textSpan! as TextSpan;

    final linked = <String>[];

    span.visitChildren((child) {
      if (child is TextSpan &&
          child.recognizer != null &&
          child.text != null) {
        linked.add(child.text!);
      }

      return true;
    });

    // Both the bare domain and the address, and nothing else.
    expect(linked, ['example.com/kit', 'hi@example.com']);
  });

  testWidgets('plain prose produces no tappable spans', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ExpandableText(
              'A quick lap of Goodwood in the rain.',
              style: TextStyle(fontSize: 14),
              toggleStyle: TextStyle(fontSize: 13.5),
              linkStyle: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );

    final rich = tester.widget<Text>(find.byType(Text).first);
    final span = rich.textSpan! as TextSpan;

    var tappable = 0;

    span.visitChildren((child) {
      if (child is TextSpan && child.recognizer != null) tappable++;

      return true;
    });

    expect(tappable, 0);
  });
}
