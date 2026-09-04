import 'package:drivelife/widgets/events/event_community_gallery_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The viewer is opened as a fullscreen dialog, which on iOS has no edge-swipe
/// back of its own — a drag on the photo is the only way out besides the close
/// button, so these guard that it still is.
void main() {
  CommunityPhoto photo(int id) => CommunityPhoto(
    id: id,
    url: 'https://example.com/$id.jpg',
    thumb: 'https://example.com/$id-thumb.jpg',
    uploaderName: 'Ada',
    uploaderAvatar: '',
  );

  // The photos' loading spinners never stop, so pumpAndSettle would time out:
  // pump a fixed stretch instead, which is long enough for a route transition
  // or a spring-back to finish.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> openViewer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => CommunityPhotoViewer(
                    photos: [photo(1), photo(2)],
                    initialIndex: 0,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.byType(CommunityPhotoViewer), findsOneWidget);
  }

  testWidgets('dragging the photo down closes the viewer', (tester) async {
    await openViewer(tester);

    // Past the distance threshold, so it closes on release rather than
    // springing back — and it must beat the InteractiveViewer to the gesture.
    await tester.drag(find.byType(PageView), const Offset(0, 300));
    await settle(tester);

    expect(find.byType(CommunityPhotoViewer), findsNothing);
  });

  testWidgets('dragging up closes it too', (tester) async {
    await openViewer(tester);

    await tester.drag(find.byType(PageView), const Offset(0, -300));
    await settle(tester);

    expect(find.byType(CommunityPhotoViewer), findsNothing);
  });

  testWidgets('a short drag springs back instead of closing', (tester) async {
    await openViewer(tester);

    await tester.drag(find.byType(PageView), const Offset(0, 40));
    await settle(tester);

    expect(find.byType(CommunityPhotoViewer), findsOneWidget);
    final slide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
    expect(slide.offset, Offset.zero);
  });

  testWidgets('paging sideways still works', (tester) async {
    await openViewer(tester);

    expect(find.text('1 / 2'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await settle(tester);

    expect(find.byType(CommunityPhotoViewer), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
  });
}
