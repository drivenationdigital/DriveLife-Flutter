import 'package:drivelife/models/membership_config.dart';
import 'package:drivelife/models/membership_tier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading the membership copy and the advert switch off the wire.
///
/// Worth testing hard because this payload is the one thing in the app
/// that can change the paywall without a review. Every way it can go
/// wrong has to leave the app on the copy it shipped with, and the
/// advert switch has to fail to OFF - a config that cannot be read
/// must never start showing adverts.
void main() {
  group('the advert switch', () {
    test('is OFF with no config at all', () {
      // A build shipped before the membership launches, and a build
      // that cannot reach the server, are the same state.
      expect(const MembershipConfig().ads.enabled, isFalse);
      expect(MembershipConfig.bundled.ads.enabled, isFalse);
    });

    test('is OFF for anything that is not plainly true', () {
      for (final value in [null, 0, '', 'no', 'FALSE', [], {}]) {
        expect(
          AdConfig.fromMap({'enabled': value}).enabled,
          isFalse,
          reason: 'for $value',
        );
      }
    });

    test('is on for the shapes a server actually sends', () {
      for (final value in [true, 1, '1', 'true']) {
        expect(
          AdConfig.fromMap({'enabled': value}).enabled,
          isTrue,
          reason: 'for $value',
        );
      }
    });

    test('density comes through', () {
      final ads = AdConfig.fromMap({
        'enabled': true,
        'first_after': 2,
        'every': 3,
      });

      expect(ads.firstAfter, 2);
      expect(ads.every, 3);
    });

    test('a zero or a negative is refused, not obeyed', () {
      // Zero would put an advert in every slot, and a negative breaks
      // the arithmetic in FeedAdSlots. This number is typed by a human
      // into a text box.
      const fallback = AdConfig();

      for (final bad in [0, -1, -99, 'nonsense', null]) {
        final ads = AdConfig.fromMap({'first_after': bad, 'every': bad});

        expect(ads.firstAfter, fallback.firstAfter, reason: 'for $bad');
        expect(ads.every, fallback.every, reason: 'for $bad');
      }
    });

    test('an absurd density is capped', () {
      final ads = AdConfig.fromMap({'every': 100000});

      expect(ads.every, 50);
    });
  });

  group('the benefit copy', () {
    test('the server replaces the bundled list', () {
      final config = MembershipConfig.fromMap({
        'version': 7,
        'tiers': {
          'plus': {
            'tagline': 'A new tagline',
            'benefits': [
              {'icon': 'bolt', 'title': 'Something new', 'detail': 'Detail.'},
            ],
          },
        },
      });

      expect(config.version, 7);
      expect(config.taglineFor(MembershipTier.plus), 'A new tagline');
      expect(config.benefitsFor(MembershipTier.plus).length, 1);
      expect(
        config.benefitsFor(MembershipTier.plus).single.title,
        'Something new',
      );
    });

    test('a tier the server does not mention keeps what it had', () {
      final config = MembershipConfig.fromMap({
        'tiers': {
          'plus': {
            'benefits': [
              {'icon': 'bolt', 'title': 'Only Plus changed'},
            ],
          },
        },
      });

      expect(
        config.benefitsFor(MembershipTier.supercharged),
        MembershipConfig.bundled.benefitsFor(MembershipTier.supercharged),
      );
    });

    test('an EMPTY benefit list is ignored, not obeyed', () {
      // Almost always a mistake at the editing end, and a tier with no
      // benefits is a paywall that sells nothing.
      final config = MembershipConfig.fromMap({
        'tiers': {
          'plus': {'tagline': 'Kept', 'benefits': <dynamic>[]},
        },
      });

      expect(config.benefitsFor(MembershipTier.plus), isNotEmpty);
      // The tagline still lands - the two are separately useful.
      expect(config.taglineFor(MembershipTier.plus), 'Kept');
    });

    test('a benefit with no title is dropped, not drawn blank', () {
      final config = MembershipConfig.fromMap({
        'tiers': {
          'plus': {
            'benefits': [
              {'icon': 'bolt', 'title': 'Real'},
              {'icon': 'bolt', 'title': '   '},
              {'icon': 'bolt'},
            ],
          },
        },
      });

      expect(config.benefitsFor(MembershipTier.plus).length, 1);
    });

    test('rubbish falls all the way back to the build', () {
      for (final bad in [
        <String, dynamic>{},
        {'tiers': 'not a map'},
        {'tiers': <String, dynamic>{}},
        {'tiers': {'plus': 'not a map'}},
      ]) {
        final config = MembershipConfig.fromMap(bad);

        expect(
          config.benefitsFor(MembershipTier.plus),
          MembershipConfig.bundled.benefitsFor(MembershipTier.plus),
          reason: '$bad',
        );
      }
    });

    test('a free tier is never sold anything', () {
      expect(MembershipConfig.bundled.benefitsFor(MembershipTier.none), isEmpty);
    });
  });

  group('icons', () {
    test('a known name resolves to its icon', () {
      expect(benefitIcon('bolt'), Icons.bolt_rounded);
      expect(benefitIcon('  VERIFIED  '), Icons.verified_rounded);
    });

    test('an unknown name is a tick, not a crash and not nothing', () {
      // The server is free to send a typo. It must not be free to put
      // an arbitrary glyph on the paywall either.
      expect(benefitIcon('rocket'), Icons.check_circle_rounded);
      expect(benefitIcon(''), Icons.check_circle_rounded);
    });

    test('names round-trip, so a config can be written back out', () {
      for (final name in benefitIconNames) {
        expect(benefitIconName(benefitIcon(name)), name, reason: name);
      }
    });
  });

  group('round trip', () {
    test('what is written out reads back the same', () {
      // The cache stores a payload and reads it again on the next
      // launch. A lossy round trip is copy that quietly degrades every
      // time the app is opened offline.
      final original = MembershipConfig.fromMap({
        'version': 4,
        'ads': {'enabled': true, 'first_after': 3, 'every': 5},
        'tiers': {
          'plus': {
            'tagline': 'Tag',
            'benefits': [
              {'icon': 'map', 'title': 'One', 'detail': 'Detail one.'},
              {'icon': 'ticket', 'title': 'Two', 'detail': ''},
            ],
          },
        },
      });

      final again = MembershipConfig.fromMap(original.toMap());

      expect(again.version, original.version);
      expect(again.ads.enabled, isTrue);
      expect(again.ads.firstAfter, 3);
      expect(again.ads.every, 5);
      expect(again.taglineFor(MembershipTier.plus), 'Tag');
      expect(
        again.benefitsFor(MembershipTier.plus).map((b) => b.title).toList(),
        ['One', 'Two'],
      );
      expect(
        again.benefitsFor(MembershipTier.plus).first.icon,
        Icons.map_rounded,
      );
    });
  });
}
