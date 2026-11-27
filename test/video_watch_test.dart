import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/services/watch_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembering where somebody got to, and the rules about when NOT to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WatchProgress.resetForTest();
  });

  group('reading a duration', () {
    test('under an hour', () {
      expect(LongVideo.formatPosition(0), '0:00');
      expect(LongVideo.formatPosition(9), '0:09');
      expect(LongVideo.formatPosition(70), '1:10');
      expect(LongVideo.formatPosition(599), '9:59');
    });

    test('over an hour, with padded minutes', () {
      // 1:5:04 would be wrong and is the easy mistake here.
      expect(LongVideo.formatPosition(3904), '1:05:04');
      expect(LongVideo.formatPosition(3600), '1:00:00');
    });

    test('a negative position reads as the start, not as nonsense', () {
      expect(LongVideo.formatPosition(-5), '0:00');
    });

    test('an UNKNOWN length is empty, but a zero POSITION is not', () {
      // The card leaves the line out entirely rather than printing
      // "0:00" for a video whose length nobody told us.
      expect(LongVideo.formatDuration(0), '');
      expect(LongVideo.formatDuration(-1), '');

      // The player, meanwhile, has to render the start.
      expect(LongVideo.formatPosition(0), '0:00');
    });
  });

  group('what is worth remembering', () {
    test('a position past the threshold comes back', () async {
      await WatchProgress.save(
        postId: 'a',
        seconds: 120,
        durationSeconds: 600,
      );

      expect(await WatchProgress.positionFor('a'), 120);
    });

    test('the first few seconds are NOT remembered', () async {
      // Resuming at 0:03 is not resuming. It tells somebody they have
      // watched something they have not.
      await WatchProgress.save(postId: 'a', seconds: 4, durationSeconds: 600);

      expect(await WatchProgress.positionFor('a'), isNull);
    });

    test('finishing offers no position to resume from', () async {
      // Being offered to resume at 9:50 of a ten minute video is the
      // app failing to notice you are done.
      await WatchProgress.save(
        postId: 'a',
        seconds: 120,
        durationSeconds: 600,
      );
      expect(await WatchProgress.positionFor('a'), 120);

      await WatchProgress.save(
        postId: 'a',
        seconds: 580,
        durationSeconds: 600,
      );

      expect(await WatchProgress.positionFor('a'), isNull);
    });

    test('finishing is REMEMBERED, not forgotten', () async {
      // The distinction the "Watched" note is drawn from. Deleting
      // the entry - which is what this used to do - made a finished
      // video and one nobody had ever opened the same thing.
      await WatchProgress.save(
        postId: 'a',
        seconds: 580,
        durationSeconds: 600,
      );

      final all = await WatchProgress.positions();

      expect(all['a'], WatchProgress.finished);
    });

    test('the finished mark is negative, so no bar can draw it', () async {
      // Every progress bar in the app is guarded on a position above
      // zero. That guard is the only reason this marker can live in
      // the same map without a single call site changing, so it is
      // worth a test of its own.
      expect(WatchProgress.finished, lessThan(0));
    });

    test('a finished video can be started again and tracked', () async {
      await WatchProgress.save(
        postId: 'a',
        seconds: 580,
        durationSeconds: 600,
      );
      await WatchProgress.save(
        postId: 'a',
        seconds: 45,
        durationSeconds: 600,
      );

      expect(await WatchProgress.positionFor('a'), 45);
    });

    test('starting again clears the finished mark too', () async {
      await WatchProgress.save(
        postId: 'a',
        seconds: 580,
        durationSeconds: 600,
      );

      await WatchProgress.clear('a');

      expect((await WatchProgress.positions())['a'], isNull);
    });

    test('just before the slack window still counts as watching', () async {
      await WatchProgress.save(
        postId: 'a',
        seconds: 569,
        durationSeconds: 600,
      );

      expect(await WatchProgress.positionFor('a'), 569);
    });

    test('an unknown duration cannot be finished, so it is kept', () async {
      // A live or still-processing video reports no duration. Dropping
      // the position because 0 >= 0 - 30 would lose every one of them.
      await WatchProgress.save(postId: 'a', seconds: 300, durationSeconds: 0);

      expect(await WatchProgress.positionFor('a'), 300);
    });

    test('an empty id is ignored rather than stored', () async {
      await WatchProgress.save(postId: '', seconds: 120, durationSeconds: 600);

      expect(await WatchProgress.positionFor(''), isNull);
    });
  });

  group('several videos', () {
    test('are kept apart', () async {
      await WatchProgress.save(postId: 'a', seconds: 30, durationSeconds: 600);
      await WatchProgress.save(postId: 'b', seconds: 90, durationSeconds: 600);

      final all = await WatchProgress.positions();

      expect(all['a'], 30);
      expect(all['b'], 90);
    });

    test('clearing one leaves the others', () async {
      await WatchProgress.save(postId: 'a', seconds: 30, durationSeconds: 600);
      await WatchProgress.save(postId: 'b', seconds: 90, durationSeconds: 600);

      await WatchProgress.clear('a');

      expect(await WatchProgress.positionFor('a'), isNull);
      expect(await WatchProgress.positionFor('b'), 90);
    });

    test('survive being read back from storage', () async {
      await WatchProgress.save(postId: 'a', seconds: 42, durationSeconds: 600);

      // A fresh launch: the in-memory cache is gone, the disk is not.
      WatchProgress.resetForTest();

      expect(await WatchProgress.positionFor('a'), 42);
    });

    test('the store is capped, and sheds finished marks first', () async {
      // Positions used to be deleted on completion, so the store
      // could only hold what was part-watched. Keeping them means it
      // grows forever unless something stops it.
      //
      // 'keep' goes in first, which under a plain oldest-out rule
      // would make it the FIRST casualty. It is the one thing here
      // somebody would notice losing, so it has to be the last to
      // go.
      await WatchProgress.save(
        postId: 'keep',
        seconds: 120,
        durationSeconds: 6000,
      );

      for (var i = 0; i < 600; i++) {
        await WatchProgress.save(
          postId: 'done-$i',
          seconds: 590,
          durationSeconds: 600,
        );
      }

      final all = await WatchProgress.positions();

      expect(all.length, lessThanOrEqualTo(500));
      expect(all['keep'], 120, reason: 'a resume point outranks a badge');
      expect(all['done-0'], isNull, reason: 'the oldest badge went first');
      expect(all['done-599'], WatchProgress.finished);
    });

    test('a corrupt store reads as empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues({
        'video_watch_progress_v1': 'not json at all',
      });
      WatchProgress.resetForTest();

      expect(await WatchProgress.positions(), isEmpty);
      expect(await WatchProgress.positionFor('a'), isNull);
    });
  });

  group('the model', () {
    test('a video with no file is not playable', () {
      const video = LongVideo(postId: '1', title: 'x');

      expect(video.isPlayable, isFalse);
    });

    test('parsing survives the shapes a server actually sends', () {
      final video = LongVideo.fromJson({
        'post_id': 998,
        'title': '  Trimmed  ',
        'duration': '2840',
        'like_count': 12,
        'liked': '1',
        'video_url': 'https://example.test/a.mp4',
        'published_at': '2026-11-01T09:00:00Z',
      });

      expect(video.postId, '998');
      expect(video.title, 'Trimmed');
      expect(video.durationSeconds, 2840);
      expect(video.liked, isTrue);
      expect(video.isPlayable, isTrue);
      expect(video.lengthLabel, '47:20');
      expect(video.publishedAt?.year, 2026);
    });

    test('rubbish parses to a safe, non-playable video', () {
      final video = LongVideo.fromJson({
        'duration': 'ages',
        'liked': 'maybe',
      });

      expect(video.durationSeconds, 0);
      expect(video.liked, isFalse);
      expect(video.isPlayable, isFalse);
      expect(video.lengthLabel, '');
    });

    test('copyWith moves the like without touching anything else', () {
      const video = LongVideo(
        postId: '1',
        title: 'x',
        videoUrl: 'https://example.test/a.mp4',
        likeCount: 3,
      );

      final liked = video.copyWith(liked: true, likeCount: 4);

      expect(liked.liked, isTrue);
      expect(liked.likeCount, 4);
      expect(liked.title, 'x');
      expect(liked.isPlayable, isTrue);
    });
  });
}
