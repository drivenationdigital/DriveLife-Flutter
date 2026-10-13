import 'package:drivelife/screens/discover/discover_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for the Discover page tour.
///
/// Two things matter about a tour: it appears once, and it can always be
/// left. A tour that reappears on every launch is worse than none at all, and
/// one with no way out until the final step is a dialog pretending to be a
/// tip.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('showing once', () {
    test('offered on a fresh install', () async {
      expect(await DiscoverTips.shouldShow(), isTrue);
    });

    test('not offered again once seen', () async {
      await DiscoverTips.markSeen();
      expect(await DiscoverTips.shouldShow(), isFalse);
    });

    test('marking seen twice is harmless', () async {
      await DiscoverTips.markSeen();
      await DiscoverTips.markSeen();
      expect(await DiscoverTips.shouldShow(), isFalse);
    });
  });

  group('the steps', () {
    test('each one says something', () {
      expect(DiscoverTips.steps, isNotEmpty);
      for (final tip in DiscoverTips.steps) {
        expect(tip.title.trim(), isNotEmpty);
        expect(tip.body.trim(), isNotEmpty);
      }
    });

    test('explains the cluster badges', () {
      // The one thing on the page that is genuinely not self-explanatory,
      // and the thing that prompted the tour.
      final bodies = DiscoverTips.steps.map((t) => t.body.toLowerCase());
      expect(bodies.any((b) => b.contains('number')), isTrue);
    });

    test('explains the long press, which nothing else reveals', () {
      final text = DiscoverTips.steps
          .map((t) => '${t.title} ${t.body}'.toLowerCase())
          .join(' ');
      expect(text.contains('hold'), isTrue);
    });
  });

  group('the card', () {
    testWidgets('can be left before the end', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDiscoverTips(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(DiscoverTips.steps.first.title), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text(DiscoverTips.steps.first.title), findsNothing);
      // Leaving early still counts as seen; being shown it again because you
      // skipped is exactly the nagging this avoids.
      expect(await DiscoverTips.shouldShow(), isFalse);
    });

    testWidgets('advances to the end and finishes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDiscoverTips(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      for (var i = 0; i < DiscoverTips.steps.length - 1; i++) {
        expect(find.text(DiscoverTips.steps[i].title), findsOneWidget);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      // The last step offers no Skip, because there is nothing left to skip.
      expect(find.text('Got it'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      expect(find.text('Got it'), findsNothing);
      expect(await DiscoverTips.shouldShow(), isFalse);
    });
  });
}
