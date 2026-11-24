import 'dart:async';

import 'package:drivelife/models/subscription_plan.dart';
import 'package:flutter/foundation.dart';

/// Buying a subscription, whoever is actually taking the money.
///
/// ── WHY THERE IS AN INTERFACE AT ALL ────────────────────────────────
///
/// Because the real one cannot be run yet. StoreKit and Play Billing
/// both need products registered in a console, agreements signed, and
/// a real device signed into a test account — none of which exists on
/// the day the screen is built.
///
/// So the screen is written against this, and [FakeSubscriptions]
/// stands in. Every outcome the screen has to handle — cancelled,
/// pending, already owned, failed — can be produced on a simulator in
/// one tap, which is the only way to find out whether the screen
/// handles them before real money is involved.
///
/// The real implementation swaps in underneath without the screen
/// changing. See the note on [FakeSubscriptions.plans] for the one
/// thing that must NOT be carried over from the fake.
/// Thrown when the stand-in store is reached in a release build.
///
/// [FakeSubscriptions] grants whatever it is asked for, so reaching it
/// with real users behind it is a free subscription for everybody. An
/// `assert` cannot say so — asserts are stripped from release builds,
/// which is precisely where the mistake matters — so every entry point
/// on the fake throws this instead.
class FakeStoreInReleaseError extends Error {
  final String member;

  FakeStoreInReleaseError(this.member);

  @override
  String toString() =>
      'FakeSubscriptions.$member was reached in a release build. '
      'The paywall must be given a real SubscriptionService.';
}

abstract class SubscriptionService {
  /// What the store will sell, at the store's prices.
  ///
  /// Falls back to [StorePlan.fallback] rather than returning nothing:
  /// a paywall with no prices on it is a dead end, and the fallback is
  /// right often enough to be better than blank. Anything the store
  /// returns replaces it.
  Future<List<StorePlan>> plans();

  /// Starts a purchase and waits for it to end.
  Future<PurchaseOutcome> buy(SubscriptionPlan plan);

  /// Asks the store what this person already owns.
  ///
  /// Both stores require a visible way to do this — a subscription
  /// bought on one device has to be reachable on another, and on iOS
  /// an app without a restore control is rejected.
  Future<SubscriptionStatus> restore();

  /// What they have now, as it changes.
  ///
  /// A stream rather than a one-off read because a purchase can
  /// complete while the app is not asking: a deferred Play payment
  /// clears hours later, and a subscription bought in Settings on iOS
  /// arrives unprompted.
  Stream<SubscriptionStatus> get changes;

  /// The last thing [changes] said, for a screen that is drawing now.
  SubscriptionStatus get current;

  void dispose();
}

/// A subscription service with no store behind it.
///
/// ── WHAT THIS IS FOR ────────────────────────────────────────────────
///
/// Driving the screen before there is anything to drive it with, and
/// then driving the paths a real store makes almost impossible to
/// reach on demand. Forcing Play into a pending payment, or StoreKit
/// into "already owned", takes a test account and several minutes
/// each; here it is one field.
///
/// ── AND WHAT IT MUST NEVER BE ───────────────────────────────────────
///
/// Shipped. There is a guard for that in [plans], but the real
/// protection is that nothing constructs this except the screen's own
/// demo switch and the tests.
class FakeSubscriptions implements SubscriptionService {
  /// What the next purchase will do.
  PurchaseOutcome nextOutcome;

  /// How long to pretend the store takes.
  ///
  /// Not zero by default, deliberately. A purchase that returns
  /// instantly hides every "is the button disabled while it is in
  /// flight" bug, which is exactly the class of thing this is here to
  /// find.
  Duration delay;

  /// Whether the store should fail to list anything.
  bool breakPlans;

  FakeSubscriptions({
    this.nextOutcome = PurchaseOutcome.success,
    this.delay = const Duration(milliseconds: 900),
    this.breakPlans = false,
  });

  final StreamController<SubscriptionStatus> _changes =
      StreamController<SubscriptionStatus>.broadcast();

  SubscriptionStatus _current = SubscriptionStatus.none;

  @override
  SubscriptionStatus get current => _current;

  @override
  Stream<SubscriptionStatus> get changes => _changes.stream;

  @override
  Future<List<StorePlan>> plans() async {
    _refuseInRelease('plans');

    await Future<void>.delayed(delay);

    if (breakPlans) return const [];

    // Prices in the shape a store returns them: with the pence, which
    // is what makes "£5" look wrong next to it if anything is hard
    // coding "£5" somewhere it should not.
    return const [
      StorePlan(plan: SubscriptionPlan.monthly, price: '£4.99'),
      StorePlan(plan: SubscriptionPlan.yearly, price: '£44.99'),
    ];
  }

  @override
  Future<PurchaseOutcome> buy(SubscriptionPlan plan) async {
    _refuseInRelease('buy');

    await Future<void>.delayed(delay);

    final outcome = nextOutcome;

    if (outcome.granted) {
      _set(
        SubscriptionStatus(
          active: true,
          plan: plan,
          renewsAt: DateTime.now().add(Duration(days: 30 * plan.months)),
        ),
      );
    }

    return outcome;
  }

  @override
  Future<SubscriptionStatus> restore() async {
    _refuseInRelease('restore');

    await Future<void>.delayed(delay);

    return _current;
  }

  /// Only the fake has this: pretends a purchase arrived from
  /// somewhere else, which is what a deferred payment clearing or a
  /// subscription bought in Settings looks like to the app.
  void arriveFromOutside(SubscriptionPlan plan) {
    _set(SubscriptionStatus(active: true, plan: plan));
  }

  /// And pretends it lapsed.
  void lapse() => _set(SubscriptionStatus.none);

  /// Refuses to work in a release build, loudly.
  ///
  /// A plain `assert` was here and did nothing: the compiler drops
  /// asserts from release builds, so the one build where this class
  /// must not run was the one build where the guard was absent. This
  /// throws instead, so the failure is a crash on the paywall rather
  /// than a membership given away.
  void _refuseInRelease(String member) {
    if (kReleaseMode) throw FakeStoreInReleaseError(member);
  }

  void _set(SubscriptionStatus status) {
    _current = status;

    if (!_changes.isClosed) _changes.add(status);
  }

  @override
  void dispose() => _changes.close();
}
