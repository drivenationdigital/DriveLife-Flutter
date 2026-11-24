import 'package:drivelife/models/subscription_plan.dart';
import 'package:drivelife/services/subscription_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The arithmetic and the outcomes behind the paywall.
///
/// Worth testing because the numbers end up on a button next to a real
/// charge, and because the outcomes decide whether somebody is given
/// something they have not paid for — or refused something they have.
void main() {
  group('what a year costs', () {
    test('the monthly plan, twelve times', () {
      expect(SubscriptionPlan.monthly.yearlyPence, 6000);
    });

    test('the yearly plan is its own price', () {
      expect(SubscriptionPlan.yearly.yearlyPence, 4500);
    });
  });

  group('the saving', () {
    test('a quarter off, which is two months free', () {
      expect(
        SubscriptionPlan.yearly.savingAgainst(SubscriptionPlan.monthly),
        25,
      );
      expect(
        SubscriptionPlan.yearly.savingLabel(SubscriptionPlan.monthly),
        'Save 25%',
      );
    });

    test('a plan does not save against itself', () {
      // "Save 0%" is worse than no badge at all.
      expect(
        SubscriptionPlan.monthly.savingAgainst(SubscriptionPlan.monthly),
        0,
      );
      expect(
        SubscriptionPlan.monthly.savingLabel(SubscriptionPlan.monthly),
        isNull,
      );
    });
  });

  group('naming a product', () {
    test('each id finds its plan', () {
      expect(
        SubscriptionPlan.forProduct('drivelife_plus_yearly'),
        SubscriptionPlan.yearly,
      );
      expect(
        SubscriptionPlan.forProduct('drivelife_plus_monthly'),
        SubscriptionPlan.monthly,
      );
    });

    test('an id from an older build is null, not a guess', () {
      // A purchase the app cannot name is one it must not act on.
      expect(SubscriptionPlan.forProduct('drivelife_plus_lifetime'), isNull);
      expect(SubscriptionPlan.forProduct(''), isNull);
    });

    test('every plan is in the list the store is asked about', () {
      expect(
        SubscriptionPlan.allProductIds.length,
        SubscriptionPlan.values.length,
      );
    });
  });

  group('the price on the screen', () {
    test('comes from the store, exactly as given', () {
      // Localised and tax-inclusive. Reformatting it is how an app
      // shows a price nobody is actually charged.
      const store = StorePlan(plan: SubscriptionPlan.yearly, price: '€54,99');

      expect(store.priceLine, '€54,99 / year');
    });

    test('and falls back only until the store answers', () {
      expect(StorePlan.fallback(SubscriptionPlan.monthly).price, '£5');
    });
  });

  group('how a purchase ended', () {
    test('cancelled is not a failure and says nothing', () {
      // Somebody changing their mind is the most common outcome of a
      // paywall. "Purchase failed" for it is wrong and faintly rude.
      expect(PurchaseOutcome.cancelled.granted, isFalse);
      expect(PurchaseOutcome.cancelled.message, isNull);
    });

    test('success grants, and lets the screen do the talking', () {
      expect(PurchaseOutcome.success.granted, isTrue);
      expect(PurchaseOutcome.success.message, isNull);
    });

    test('already owned grants too', () {
      // Restoring on a second device lands here, and refusing it
      // would lock somebody out of what they have paid for.
      expect(PurchaseOutcome.alreadyOwned.granted, isTrue);
      expect(PurchaseOutcome.alreadyOwned.message, isNotNull);
    });

    test('pending grants NOTHING and says so', () {
      // Play's deferred payments clear hours later, at a shop.
      // Granting here is giving it away.
      expect(PurchaseOutcome.pending.granted, isFalse);
      expect(PurchaseOutcome.pending.message, contains('pending'));
    });

    test('failed grants nothing and promises no charge', () {
      expect(PurchaseOutcome.failed.granted, isFalse);
      expect(PurchaseOutcome.failed.message, contains('Nothing was charged'));
    });
  });

  group('the stand-in store', () {
    test('lists both plans at store-shaped prices', () async {
      final store = FakeSubscriptions(delay: Duration.zero);

      final plans = await store.plans();

      expect(plans.length, 2);
      expect(plans.first.price, '£4.99');

      store.dispose();
    });

    test('a success turns the subscription on', () async {
      final store = FakeSubscriptions(delay: Duration.zero);

      expect(store.current.active, isFalse);

      final outcome = await store.buy(SubscriptionPlan.yearly);

      expect(outcome, PurchaseOutcome.success);
      expect(store.current.active, isTrue);
      expect(store.current.plan, SubscriptionPlan.yearly);

      store.dispose();
    });

    test('a cancel changes nothing', () async {
      final store = FakeSubscriptions(
        delay: Duration.zero,
        nextOutcome: PurchaseOutcome.cancelled,
      );

      await store.buy(SubscriptionPlan.yearly);

      expect(store.current.active, isFalse);

      store.dispose();
    });

    test('a pending payment grants nothing yet', () async {
      final store = FakeSubscriptions(
        delay: Duration.zero,
        nextOutcome: PurchaseOutcome.pending,
      );

      await store.buy(SubscriptionPlan.monthly);

      expect(store.current.active, isFalse);

      store.dispose();
    });

    test('a purchase from outside reaches the stream', () async {
      final store = FakeSubscriptions(delay: Duration.zero);

      final seen = <bool>[];
      final watch = store.changes.listen((s) => seen.add(s.active));

      store.arriveFromOutside(SubscriptionPlan.monthly);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [true]);

      await watch.cancel();
      store.dispose();
    });

    test('a store that lists nothing is survivable', () async {
      final store = FakeSubscriptions(delay: Duration.zero, breakPlans: true);

      expect(await store.plans(), isEmpty);

      store.dispose();
    });
  });
}
