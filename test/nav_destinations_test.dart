import 'package:drivelife/main.dart' show BottomNavProvider;
import 'package:flutter_test/flutter_test.dart';

/// Tests for where the app's navigation shortcuts actually go.
///
/// These exist because of a bug that was invisible from the code: the "Hot
/// right now" shortcuts on the feed navigated with bare integers — 1, 2, 3
/// for Events, Venues and Clubs. Events and Venues later became sections of
/// Home and the bottom bar was reordered twice, so those numbers stayed
/// perfectly valid and quietly started meaning something else. "Find Events"
/// opened the map. "Popular Venues" opened Groups.
///
/// Nothing crashed and nothing looked broken, which is what made it survive
/// two rounds of changes. The destinations are named now, and these pin the
/// names to their positions.
void main() {
  group('bottom bar', () {
    test('the destinations are in the order the bar shows them', () {
      // Home, Garage, Map, Groups, Media — and the reason these
      // assertions are written against names rather than numbers. The
      // bar labels Map and Media; the constants keep the names the
      // screens and routes already use.
      //
      // There is no Search destination. This test asserted one, and a
      // count of six, against a bar that has only ever shipped five —
      // so it has been the one failing check in the project. Search is
      // reachable from the feed's own search control, not the bar; if
      // it ever becomes a destination, add the constant first and this
      // will be waiting for it.
      expect(BottomNavProvider.home, 0);
      // Garage, where Account used to be. The account avatar moved to the
      // header: it is a thing you ARE, not a place you go, and it was
      // spending a fifth of the bar to say so.
      expect(BottomNavProvider.garage, 1);
      expect(BottomNavProvider.discover, 2);
      expect(BottomNavProvider.groups, 3);
      expect(BottomNavProvider.photos, 4);
    });

    test('the count matches the names', () {
      // The shell asserts its destination list against this, because the two
      // are matched by position and a mismatch sends taps to the wrong
      // screen rather than failing.
      expect(BottomNavProvider.destinationCount, 5);
    });
  });

  group('home sections', () {
    test('are in the order of the top tab row', () {
      expect(BottomNavProvider.forYou, 0);
      expect(BottomNavProvider.events, 1);
      expect(BottomNavProvider.places, 2);
      // Tracks before Businesses: one has somewhere to go, the other is a
      // "coming soon" page.
      expect(BottomNavProvider.tracks, 3);
      expect(BottomNavProvider.businesses, 4);
      // Last. Messages used to sit after this one and no longer does —
      // the inbox moved out of the row into MessagesScreen, which it
      // shares with notifications behind the header's message icon.
      expect(BottomNavProvider.shop, 5);
    });

    test('the count matches the names', () {
      expect(BottomNavProvider.sectionCount, 6);
    });

    test('a section index is not a destination index', () {
      // The whole bug in one line: Events as a Home section is 1, and 1 as
      // a destination is the Garage. Anything navigating with a bare number
      // is one reorder away from being wrong — and this line has already
      // had to be rewritten once, because the reorder that moved Garage to
      // 1 moved Discover off it. The collision survived; only its victim
      // changed.
      expect(BottomNavProvider.events, BottomNavProvider.garage);
    });
  });

  group('openHomeSection', () {
    test('switches to Home and selects the section together', () {
      final nav = BottomNavProvider()..setIndex(BottomNavProvider.groups);

      nav.openHomeSection(BottomNavProvider.events);

      // Both, in one call. Setting the section while on Groups would change
      // nothing visible; switching to Home first would show the old section
      // for a frame.
      expect(nav.currentIndex, BottomNavProvider.home);
      expect(nav.homeSection, BottomNavProvider.events);
    });

    test('notifies once so the shell rebuilds', () {
      final nav = BottomNavProvider();
      var notifications = 0;
      nav.addListener(() => notifications++);

      nav.openHomeSection(BottomNavProvider.places);

      expect(notifications, 1);
    });

    test('does nothing when already there', () {
      final nav = BottomNavProvider()
        ..openHomeSection(BottomNavProvider.places);

      var notifications = 0;
      nav.addListener(() => notifications++);
      nav.openHomeSection(BottomNavProvider.places);

      expect(notifications, 0);
    });

    test(
      'still notifies when the section matches but the destination does not',
      () {
        // Tapping "Popular Venues" from the Groups tab: the remembered section
        // is already Places, but the user is not on Home and expects to go
        // there. Comparing the section alone would make the tap do nothing.
        final nav = BottomNavProvider()
          ..openHomeSection(BottomNavProvider.places)
          ..setIndex(BottomNavProvider.groups);

        var notifications = 0;
        nav.addListener(() => notifications++);
        nav.openHomeSection(BottomNavProvider.places);

        expect(notifications, 1);
        expect(nav.currentIndex, BottomNavProvider.home);
      },
    );

    test('remembers the section while you are elsewhere', () {
      // Leaving Home and coming back should land where it was left.
      final nav = BottomNavProvider()
        ..openHomeSection(BottomNavProvider.tracks)
        ..setIndex(BottomNavProvider.photos);

      expect(nav.homeSection, BottomNavProvider.tracks);

      nav.setIndex(BottomNavProvider.home);
      expect(nav.homeSection, BottomNavProvider.tracks);
    });
  });
}
