import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/services/watch_progress.dart';
import 'package:drivelife/widgets/media/video_list_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The note under a video in a list: Resume, Watched, or nothing.
void main() {
  const video = LongVideo(
    postId: '1',
    title: 'New Audi RS5 v RS6 GT V8: DRAG RACE',
    durationSeconds: 600,
  );

  Future<void> show(WidgetTester tester, int watched) {
    return tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: VideoListRow(
              video: video,
              subtitle: 'carwow',
              watchedSeconds: watched,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('an unwatched video says nothing', (tester) async {
    // The quiet case, and the common one. A list where every row
    // carries a status is a list where none of them stands out.
    await show(tester, 0);

    expect(find.textContaining('Resume'), findsNothing);
    expect(find.text('Watched'), findsNothing);
  });

  testWidgets('a part-watched video offers to resume, with the time '
      'remaining', (tester) async {
    await show(tester, 240);

    // 600 - 240. The remainder, not the position: somebody coming
    // back to a video wants to know whether they have time for it.
    expect(find.text('Resume  ·  6:00 left'), findsOneWidget);
  });

  testWidgets('a finished video says Watched and offers no resume', (
    tester,
  ) async {
    await show(tester, WatchProgress.finished);

    expect(find.text('Watched'), findsOneWidget);
    expect(find.textContaining('Resume'), findsNothing);
  });

  testWidgets('a finished video draws no progress bar', (tester) async {
    // The whole reason the marker is negative. If this ever fails,
    // every bar in the app is about to try drawing a negative
    // fraction.
    await show(tester, WatchProgress.finished);

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('an unknown duration resumes without quoting a remainder', (
    tester,
  ) async {
    // A still-processing upload reports no length. A difference from
    // an unknown total is not a time, so the word has to stand alone.
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: VideoListRow(
              video: const LongVideo(postId: '2', title: 'Processing'),
              subtitle: 'DriveLife',
              watchedSeconds: 90,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Resume'), findsOneWidget);
  });
}
