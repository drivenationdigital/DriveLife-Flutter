import 'package:drivelife/models/membership_benefits.dart';
import 'package:drivelife/models/membership_tier.dart';
import 'package:drivelife/models/subscription_plan.dart';
import 'package:drivelife/providers/membership_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which tier somebody is on, and what that satisfies.
///
/// Worth testing because every one of these decides whether something
/// is given away. A gate that compares the wrong way round hands the
/// higher tier's features to the lower one, and an unrecognised
/// product that resolves to anything at all hands them to a purchase
/// this build has never heard of.
void main() {
  group('what outranks what', () {
    test('SuperCharged satisfies a Plus gate', () {
      expect(
        MembershipTier.supercharged.atLeast(MembershipTier.plus),
        isTrue,
      );
    });

    test('Plus does NOT satisfy a SuperCharged gate', () {
      // The direction that matters. Backwards, the top tier is worth
      // nothing and everybody who paid for it paid for Plus.
      expect(
        MembershipTier.plus.atLeast(MembershipTier.supercharged),
        isFalse,
      );
    });

    test('a tier satisfies itself', () {
      for (final tier in MembershipTier.values) {
        expect(tier.atLeast(tier), isTrue, reason: '$tier');
      }
    });

    test('nobody satisfies a gate from none', () {
      expect(MembershipTier.none.atLeast(MembershipTier.plus), isFalse);
      expect(MembershipTier.none.isMember, isFalse);
    });

    test('both paid tiers are members', () {
      expect(MembershipTier.plus.isMember, isTrue);
      expect(MembershipTier.supercharged.isMember, isTrue);
    });
  });

  group('what a badge says', () {
    test('a free account has no badge at all', () {
      // Not a grey "FREE" pill. A badge saying you have not paid is
      // not a badge, it is a nag.
      expect(MembershipTier.none.badge, isEmpty);
    });

    test('the paid tiers do, and they differ', () {
      expect(MembershipTier.plus.badge, 'PLUS');
      expect(MembershipTier.supercharged.badge, 'SUPERCHARGED');
      expect(
        MembershipTier.plus.colour,
        isNot(MembershipTier.supercharged.colour),
      );
    });
  });

  group('naming a purchase', () {
    test('each product resolves to its tier', () {
      expect(
        MembershipTier.forProduct('drivelife_plus_monthly'),
        MembershipTier.plus,
      );
      expect(
        MembershipTier.forProduct('drivelife_plus_yearly'),
        MembershipTier.plus,
      );
      expect(
        MembershipTier.forProduct('drivelife_supercharged_yearly'),
        MembershipTier.supercharged,
      );
    });

    test('an unknown product is null, never a tier', () {
      // Granting a tier for a purchase this build cannot name is
      // granting one by accident, and the accident is always upward.
      expect(MembershipTier.forProduct('drivelife_lifetime'), isNull);
      expect(MembershipTier.forProduct(''), isNull);
    });
  });

  group('the plans behind each tier', () {
    test('Plus has a monthly and a yearly', () {
      final plans = SubscriptionPlan.forTier(MembershipTier.plus);

      expect(plans.length, 2);
      expect(plans.map((p) => p.period), containsAll(['month', 'year']));
    });

    test('SuperCharged is yearly only, as created', () {
      // Somebody on Plus Monthly has no monthly step up to this.
      final plans = SubscriptionPlan.forTier(MembershipTier.supercharged);

      expect(plans.length, 1);
      expect(plans.single.period, 'year');
    });

    test('every plan knows which tier it buys', () {
      for (final plan in SubscriptionPlan.values) {
        expect(plan.tier.isMember, isTrue, reason: plan.productId);
        expect(
          MembershipTier.forProduct(plan.productId),
          plan.tier,
          reason: '${plan.productId} disagrees with its own id',
        );
      }
    });
  });

  // The saving badge is a claim about money, on a button next to a
  // real charge. Against the wrong tier it is a number somebody could
  // act on and be wrong about.
  group('what the saving is measured against', () {
    test('Plus yearly saves against PLUS monthly', () {
      final monthly = SubscriptionPlan.monthlyOf(MembershipTier.plus);

      expect(monthly, SubscriptionPlan.monthly);
      expect(SubscriptionPlan.yearly.savingLabel(monthly!), 'Save 25%');
    });

    test('SuperCharged has no monthly, so no saving is claimed', () {
      // Comparing it to the PLUS monthly rate would produce a
      // percentage about two different things.
      expect(SubscriptionPlan.monthlyOf(MembershipTier.supercharged), isNull);
    });

    test('and a free tier has no plans at all', () {
      expect(SubscriptionPlan.monthlyOf(MembershipTier.none), isNull);
      expect(SubscriptionPlan.forTier(MembershipTier.none), isEmpty);
    });
  });

  group('the benefits', () {
    test('each paid tier has its own list and a tagline', () {
      for (final tier in [MembershipTier.plus, MembershipTier.supercharged]) {
        expect(MembershipBenefits.forTier(tier), isNotEmpty, reason: tier.name);
        expect(MembershipBenefits.taglineFor(tier), isNotEmpty, reason: tier.name);
      }
    });

    test('a free account is sold nothing', () {
      expect(MembershipBenefits.forTier(MembershipTier.none), isEmpty);
      expect(MembershipBenefits.taglineFor(MembershipTier.none), isEmpty);
    });

    test('SuperCharged offers more than Plus', () {
      expect(
        MembershipBenefits.forTier(MembershipTier.supercharged).length,
        greaterThan(MembershipBenefits.forTier(MembershipTier.plus).length),
      );
    });

    test('each badge benefit names the right metal', () {
      // The colours are a promise made in the listing, so the words
      // and the colours have to agree.
      final plus = MembershipBenefits.forTier(MembershipTier.plus)
          .map((b) => b.title)
          .join(' ');
      final sc = MembershipBenefits.forTier(MembershipTier.supercharged)
          .map((b) => b.title)
          .join(' ');

      expect(plus.toLowerCase(), contains('silver'));
      expect(sc.toLowerCase(), contains('gold'));
    });
  });

  group('the provider', () {
    test('starts as nobody', () {
      final m = MembershipProvider();

      expect(m.tier, MembershipTier.none);
      expect(m.isMember, isFalse);
    });

    test('has() answers the gate question once, for everybody', () {
      final m = MembershipProvider()..set(MembershipTier.plus);

      expect(m.has(MembershipTier.plus), isTrue);
      expect(m.has(MembershipTier.supercharged), isFalse);
    });

    test('clearing takes the badge with it', () {
      // Sign-out. Leaving the last account's tier behind shows the
      // next person a badge they have not got.
      final m = MembershipProvider()..set(MembershipTier.supercharged);

      m.clear();

      expect(m.tier, MembershipTier.none);
    });

    test('notifies only on a real change', () {
      var calls = 0;
      final m = MembershipProvider()..addListener(() => calls++);

      m.set(MembershipTier.plus);
      m.set(MembershipTier.plus);

      expect(calls, 1);
    });
  });
}
