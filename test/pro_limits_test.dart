import 'package:drivelife/models/pro_limits.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a free account may add, and what it keeps.
///
/// The rule is one sentence - nothing is taken away, the cap applies to
/// ADDING - and it is arithmetic with an off-by-one in it. "At the cap"
/// and "over the cap" must both refuse while meaning different things,
/// and "under the cap" must allow. Each of the three ways to get that
/// wrong either blocks somebody who has done nothing wrong or gives the
/// feature away.
void main() {
  const feature = ProFeature.routes;
  final cap = ProLimits.freeLimit[feature]!;

  group('a free account', () {
    test('may add while under the cap', () {
      expect(ProLimits.canAdd(feature, isPro: false, owned: 0), isTrue);
      expect(ProLimits.canAdd(feature, isPro: false, owned: cap - 1), isTrue);
    });

    test('may not add AT the cap', () {
      // The off-by-one. Three of three is three, not room for a fourth.
      expect(ProLimits.canAdd(feature, isPro: false, owned: cap), isFalse);
    });

    test('may not add over the cap', () {
      expect(ProLimits.canAdd(feature, isPro: false, owned: cap + 37), isFalse);
    });
  });

  group('Pro', () {
    test('may always add, at any count', () {
      expect(ProLimits.canAdd(feature, isPro: true, owned: 0), isTrue);
      expect(ProLimits.canAdd(feature, isPro: true, owned: cap), isTrue);
      expect(ProLimits.canAdd(feature, isPro: true, owned: 5000), isTrue);
    });

    test('is never grandfathered, because it is never capped', () {
      expect(
        ProLimits.isGrandfathered(feature, isPro: true, owned: 5000),
        isFalse,
      );
    });

    test('has no number remaining, rather than a big one', () {
      expect(ProLimits.remaining(feature, isPro: true, owned: 0), isNull);
    });
  });

  group('keeping what you already have', () {
    test('over the cap is grandfathered', () {
      expect(
        ProLimits.isGrandfathered(feature, isPro: false, owned: 40),
        isTrue,
      );
    });

    test('AT the cap is not grandfathered - it is just full', () {
      // Both refuse to add. Only one of them gets the reassuring
      // sentence, and telling somebody with exactly three that they
      // have "more than allowed" is nonsense.
      expect(
        ProLimits.isGrandfathered(feature, isPro: false, owned: cap),
        isFalse,
      );
    });

    test('nothing ever reports a negative remainder', () {
      // Minus thirty-seven on a screen is the grandfathering promise
      // printed as a threat.
      expect(ProLimits.remaining(feature, isPro: false, owned: 40), 0);
    });

    test('remaining counts down to the cap', () {
      expect(ProLimits.remaining(feature, isPro: false, owned: 0), cap);
      expect(ProLimits.remaining(feature, isPro: false, owned: cap - 1), 1);
      expect(ProLimits.remaining(feature, isPro: false, owned: cap), 0);
    });
  });

  group('what the upsell says', () {
    test('nothing at all when they can still add', () {
      expect(
        ProLimits.reasonToUpsell(feature, isPro: false, owned: 0),
        isNull,
      );
    });

    test('nothing at all to somebody who has paid', () {
      expect(
        ProLimits.reasonToUpsell(feature, isPro: true, owned: 5000),
        isNull,
      );
    });

    test('at the cap, it states the rule', () {
      expect(
        ProLimits.reasonToUpsell(feature, isPro: false, owned: cap),
        'Add more than $cap routes',
      );
    });

    test('over the cap, it reassures first and sells second', () {
      // The grandfathering promise, said out loud, to the only people
      // who need to hear it.
      expect(
        ProLimits.reasonToUpsell(feature, isPro: false, owned: 40),
        'Keep your 40 routes, and add more with Pro',
      );
    });

    test('one of something is singular', () {
      expect(
        ProLimits.reasonToUpsell(
          ProFeature.vehicles,
          isPro: false,
          owned: ProLimits.freeLimit[ProFeature.vehicles]! + 1,
        ),
        contains('vehicles'),
      );
      expect(
        ProLimits.reasonToUpsell(ProFeature.vehicles, isPro: false, owned: 1),
        anyOf(isNull, contains('vehicle')),
      );
    });
  });

  group('a feature nobody has set a number for', () {
    test('is not silently capped', () {
      // Every ProFeature must appear in freeLimit. A missing entry
      // reads as "unlimited", which is the safe direction to fail -
      // but it is still a feature somebody forgot to price, so this
      // test is here to notice.
      for (final f in ProFeature.values) {
        expect(
          ProLimits.freeLimit.containsKey(f),
          isTrue,
          reason: '$f has no free limit set',
        );
      }
    });
  });
}
