import 'package:drivelife/models/membership_tier.dart';
import 'package:drivelife/models/subscription_plan.dart';
import 'package:drivelife/providers/membership_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cancelled, lapsed, and renewing - and the differences between them.
///
/// ── WHY THIS IS ITS OWN FILE ────────────────────────────────────────
///
/// Because "cancelled" is the state everybody gets wrong, in both
/// directions:
///
///   * Treat it as lapsed and you revoke a membership somebody has
///     paid eleven more months for.
///   * Treat it as ordinary and you offer to cancel something already
///     cancelled, which reads as the cancellation not having worked.
///
/// The second is the bug this was written for. Both are checked here.
void main() {
  group('still entitled', () {
    test('a cancelled subscription is still active', () {
      // The whole point. Cancelling stops the NEXT charge; it does not
      // refund the period already paid for.
      const status = SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.yearly,
        willRenew: false,
      );

      expect(status.active, isTrue);
      expect(status.endingSoon, isTrue);
    });

    test('and it still grants the tier', () {
      final m = MembershipProvider();

      m.applyStoreStatus(
        const SubscriptionStatus(
          active: true,
          plan: SubscriptionPlan.monthly,
          willRenew: false,
        ),
      );

      expect(m.tier, MembershipTier.plus);
    });

    test('a lapsed one is not active and not ending - it has ended', () {
      expect(SubscriptionStatus.none.active, isFalse);
      expect(SubscriptionStatus.none.endingSoon, isFalse);
    });
  });

  group('endingSoon', () {
    test('is false while it is renewing', () {
      const status = SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.monthly,
        willRenew: true,
      );

      expect(status.endingSoon, isFalse);
    });

    test('is false when nobody could say', () {
      // iOS below 15, no store, a failed lookup. Unknown must not read
      // as cancelled: it would tell a perfectly happy member that
      // their membership is ending.
      const status = SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.monthly,
      );

      expect(status.willRenew, isNull);
      expect(status.endingSoon, isFalse);
    });

    test('is false for somebody who is not a member at all', () {
      // Not active, so there is nothing to end, whatever the flag says.
      const status = SubscriptionStatus(willRenew: false);

      expect(status.endingSoon, isFalse);
    });
  });

  group('copyWith', () {
    test('sets the renewal flag and keeps everything else', () {
      final renews = DateTime.utc(2026, 12, 24);

      final status = const SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.superchargedYearly,
      ).copyWith(willRenew: false);

      expect(status.active, isTrue);
      expect(status.plan, SubscriptionPlan.superchargedYearly);
      expect(status.willRenew, isFalse);

      final dated = SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.monthly,
        renewsAt: renews,
      ).copyWith(willRenew: true);

      expect(dated.renewsAt, renews);
      expect(dated.willRenew, isTrue);
    });

    test('a null argument leaves the flag alone', () {
      // Dart's `??` means passing null cannot clear it. Worth pinning:
      // the alternative reading is that copyWith(willRenew: null)
      // resets to unknown, and a refresh that returns null would then
      // wipe a known answer.
      final status = const SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.monthly,
        willRenew: false,
      ).copyWith();

      expect(status.willRenew, isFalse);
    });
  });

  group('the three states a member can be in', () {
    // What the paywall branches on. One of these must be true and the
    // other two false, for every member, always.
    ({bool renewing, bool ending, bool unknown}) classify(
      SubscriptionStatus s,
    ) => (
      renewing: s.active && s.willRenew == true,
      ending: s.endingSoon,
      unknown: s.active && s.willRenew == null,
    );

    test('exactly one is true in each case', () {
      const cases = [
        SubscriptionStatus(
          active: true,
          plan: SubscriptionPlan.monthly,
          willRenew: true,
        ),
        SubscriptionStatus(
          active: true,
          plan: SubscriptionPlan.monthly,
          willRenew: false,
        ),
        SubscriptionStatus(active: true, plan: SubscriptionPlan.monthly),
      ];

      for (final status in cases) {
        final c = classify(status);
        final count = [
          c.renewing,
          c.ending,
          c.unknown,
        ].where((v) => v).length;

        expect(count, 1, reason: 'for willRenew=${status.willRenew}');
      }
    });

    test('a non-member matches none of them', () {
      final c = classify(SubscriptionStatus.none);

      expect(c.renewing || c.ending || c.unknown, isFalse);
    });
  });

  group('a plan change waiting to happen', () {
    test('a pending downgrade is a change, not an ending', () {
      // Apple defers a downgrade to the end of the period. This person
      // is not leaving, they are moving - and telling them their
      // membership is ending would be wrong.
      const status = SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.superchargedYearly,
        willRenew: true,
        renewingTo: SubscriptionPlan.yearly,
      );

      expect(status.changingPlan, isTrue);
      expect(status.endingSoon, isFalse);
      expect(status.active, isTrue);
    });

    test('renewing into the SAME plan is not a change', () {
      // StoreKit reports autoRenewPreference as the current product
      // when nothing is pending. Treated naively that announces a plan
      // change to everybody.
      const status = SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.monthly,
        willRenew: true,
        renewingTo: SubscriptionPlan.monthly,
      );

      expect(status.changingPlan, isFalse);
    });

    test('no pending plan is not a change', () {
      const status = SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.monthly,
        willRenew: true,
      );

      expect(status.changingPlan, isFalse);
    });

    test('a non-member is never changing plan', () {
      const status = SubscriptionStatus(renewingTo: SubscriptionPlan.yearly);

      expect(status.changingPlan, isFalse);
    });

    test('cancelled and changing are independent', () {
      // Cancelling a subscription that had a downgrade queued leaves
      // both true. The screen has to handle that without contradicting
      // itself.
      const status = SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.superchargedYearly,
        willRenew: false,
        renewingTo: SubscriptionPlan.yearly,
      );

      expect(status.endingSoon, isTrue);
      expect(status.changingPlan, isTrue);
    });

    test('copyWith carries the pending plan', () {
      final status = const SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.superchargedYearly,
      ).copyWith(willRenew: true, renewingTo: SubscriptionPlan.monthly);

      expect(status.renewingTo, SubscriptionPlan.monthly);
      expect(status.changingPlan, isTrue);
    });

    test('a crossgrade within one tier still registers', () {
      // Yearly to monthly is the same tier at a different price. Not a
      // tier change, but still a change worth telling somebody about.
      const status = SubscriptionStatus(
        active: true,
        plan: SubscriptionPlan.yearly,
        willRenew: true,
        renewingTo: SubscriptionPlan.monthly,
      );

      expect(status.changingPlan, isTrue);
      expect(status.renewingTo!.tier, status.plan!.tier);
    });
  });
}
