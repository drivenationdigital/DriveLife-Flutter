import 'package:drivelife/models/membership_tier.dart';
import 'package:drivelife/models/subscription_plan.dart';
import 'package:drivelife/providers/membership_provider.dart';
import 'package:drivelife/services/membership_sync.dart';
import 'package:drivelife/services/subscription_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Getting from "the store says they paid" to "the app treats them as a
/// member", and the order of precedence that decides it.
///
/// This is the file that was missing, and its absence was the bug: a
/// purchase could succeed and every screen still said Free, because
/// nothing joined the store to the provider.
void main() {
  group('what the store says', () {
    test('an active subscription makes them a member', () {
      final m = MembershipProvider();

      m.applyStoreStatus(
        const SubscriptionStatus(
          active: true,
          plan: SubscriptionPlan.monthly,
        ),
      );

      expect(m.tier, MembershipTier.plus);
      expect(m.isMember, isTrue);
    });

    test('the tier follows the product, not the fact of paying', () {
      final m = MembershipProvider();

      m.applyStoreStatus(
        const SubscriptionStatus(
          active: true,
          plan: SubscriptionPlan.superchargedYearly,
        ),
      );

      expect(m.tier, MembershipTier.supercharged);
      expect(m.has(MembershipTier.plus), isTrue);
    });

    test('active with no recognisable plan grants NOTHING', () {
      // A product this build cannot name. The accident is always
      // upward, so the answer has to be no.
      final m = MembershipProvider();

      m.applyStoreStatus(const SubscriptionStatus(active: true));

      expect(m.tier, MembershipTier.none);
    });

    test('a lapsed subscription takes the tier away again', () {
      final m = MembershipProvider();

      m.applyStoreStatus(
        const SubscriptionStatus(
          active: true,
          plan: SubscriptionPlan.yearly,
        ),
      );
      m.applyStoreStatus(SubscriptionStatus.none);

      expect(m.tier, MembershipTier.none);
    });
  });

  group('who wins', () {
    test('the server outranks the store', () {
      // The store is this device talking about itself, and a rooted
      // phone will lie. Once the server has an answer, it is the
      // answer.
      final m = MembershipProvider();

      m.applyStoreStatus(
        const SubscriptionStatus(
          active: true,
          plan: SubscriptionPlan.superchargedYearly,
        ),
      );
      m.set(MembershipTier.plus);

      expect(m.tier, MembershipTier.plus);
    });

    test('the server saying "no" beats the store saying "yes"', () {
      final m = MembershipProvider();

      m.applyStoreStatus(
        const SubscriptionStatus(
          active: true,
          plan: SubscriptionPlan.monthly,
        ),
      );
      m.set(MembershipTier.none);

      expect(m.tier, MembershipTier.none);
    });

    test('the demo override outranks both', () {
      final m = MembershipProvider();

      m.set(MembershipTier.none);
      m.debugSetTier(MembershipTier.supercharged);

      expect(m.tier, MembershipTier.supercharged);
    });

    test('dropping the override falls back to the real answer', () {
      final m = MembershipProvider();

      m.applyStoreStatus(
        const SubscriptionStatus(
          active: true,
          plan: SubscriptionPlan.monthly,
        ),
      );
      m.debugSetTier(MembershipTier.none);
      expect(m.tier, MembershipTier.none);

      m.debugUseLive();
      expect(m.tier, MembershipTier.plus);
    });

    test('signing out clears all three', () {
      // The subscription belongs to the Apple or Google account, not
      // the DriveLife one. The next person on this handset must not
      // inherit it.
      final m = MembershipProvider();

      m.applyStoreStatus(
        const SubscriptionStatus(
          active: true,
          plan: SubscriptionPlan.monthly,
        ),
      );
      m.set(MembershipTier.plus);
      m.debugSetTier(MembershipTier.supercharged);

      m.clear();

      expect(m.tier, MembershipTier.none);
    });
  });

  group('notifying', () {
    test('only fires when the ANSWER moves', () {
      // The server confirming what the store already said is not a
      // change worth rebuilding the app for.
      var calls = 0;
      final m = MembershipProvider()..addListener(() => calls++);

      m.applyStoreStatus(
        const SubscriptionStatus(
          active: true,
          plan: SubscriptionPlan.monthly,
        ),
      );
      expect(calls, 1);

      m.set(MembershipTier.plus);
      expect(calls, 1, reason: 'same answer, different source');

      m.set(MembershipTier.supercharged);
      expect(calls, 2);
    });
  });

  group('the sync', () {
    test('asks the store at startup and reports what it owns', () async {
      // Somebody who subscribed last month has bought nothing this
      // session and is still a member. Launch has to ask.
      final m = MembershipProvider();
      final fake = FakeSubscriptions(delay: Duration.zero)
        ..arriveFromOutside(SubscriptionPlan.yearly);

      await MembershipSync(m, store: fake).start();

      expect(m.tier, MembershipTier.plus);
    });

    test('a purchase after startup lands too', () async {
      final m = MembershipProvider();
      final fake = FakeSubscriptions(delay: Duration.zero);
      final sync = MembershipSync(m, store: fake);

      await sync.start();
      expect(m.tier, MembershipTier.none);

      await fake.buy(SubscriptionPlan.superchargedYearly);
      await _settle();

      expect(m.tier, MembershipTier.supercharged);
    });

    test('a cancellation lands too', () async {
      final m = MembershipProvider();
      final fake = FakeSubscriptions(delay: Duration.zero);

      await MembershipSync(m, store: fake).start();
      await fake.buy(SubscriptionPlan.monthly);
      await _settle();
      expect(m.isMember, isTrue);

      fake.lapse();
      await _settle();

      expect(m.tier, MembershipTier.none);
    });

    test('a store that throws leaves them free, not broken', () async {
      // A simulator with no StoreKit configuration, a device with no
      // Play Services, an App Store outage. Launch must survive all
      // three.
      final m = MembershipProvider();

      await MembershipSync(m, store: _BrokenStore()).start();

      expect(m.tier, MembershipTier.none);
    });

    test('starting twice does not double-subscribe', () async {
      final m = MembershipProvider();
      final fake = FakeSubscriptions(delay: Duration.zero);
      final sync = MembershipSync(m, store: fake);

      await sync.start();
      await sync.start();

      var calls = 0;
      m.addListener(() => calls++);

      await fake.buy(SubscriptionPlan.monthly);
      await _settle();

      expect(calls, 1);
    });
  });
}

/// Lets the purchase stream deliver.
///
/// The service hands status out on a broadcast stream, so a listener
/// runs a microtask after the add rather than during it. Real code
/// never notices; a test that asserts on the next line does.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// A store that fails at everything, for the launch path.
class _BrokenStore implements SubscriptionService {
  @override
  Stream<SubscriptionStatus> get changes => const Stream.empty();

  @override
  SubscriptionStatus get current => SubscriptionStatus.none;

  @override
  Future<List<StorePlan>> plans() async => throw StateError('no store');

  @override
  Future<PurchaseOutcome> buy(SubscriptionPlan plan) async =>
      throw StateError('no store');

  @override
  Future<SubscriptionStatus> restore() async => throw StateError('no store');

  @override
  void dispose() {}
}
