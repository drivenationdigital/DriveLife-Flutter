import 'dart:async';

import 'package:drivelife/models/subscription_plan.dart';
import 'package:drivelife/providers/membership_provider.dart';
import 'package:drivelife/services/store_subscriptions.dart';
import 'package:drivelife/services/subscription_service.dart';
import 'package:flutter/foundation.dart';

/// Keeps [MembershipProvider] in step with what the store reports.
///
/// ── THE GAP THIS FILLS ──────────────────────────────────────────────
///
/// Everything needed to buy a subscription existed, and everything
/// needed to draw one existed, and nothing joined them. You could buy
/// DriveLife Plus, see the purchase succeed in StoreKit, and the app
/// would still say Free on every screen - because the only thing that
/// ever set the tier was the demo switch.
///
/// This is the join. One service, owned for the life of the app, that
/// listens to the store and pushes what it hears into the provider.
///
/// ── WHY IT ASKS AT LAUNCH AND NOT ONLY ON PURCHASE ──────────────────
///
/// A purchase is one moment; membership outlives it. Somebody who
/// subscribed last month, or on another handset, or who reinstalled,
/// has bought nothing this session and must still be a member. So the
/// first thing this does is ask the store what is already owned.
///
/// That ask is cheap and silent on both platforms, which is the only
/// reason it can be done unprompted at launch:
///
///   * iOS, StoreKit 2: `restorePurchases` reads
///     `Transaction.currentEntitlements` on the device. It does NOT
///     call `AppStore.sync()`, so there is no App Store password
///     prompt. (Under StoreKit 1 there would be - the plugin defaults
///     to StoreKit 2, and this is one of the reasons to leave it that
///     way.)
///   * Android: `queryPurchases` against the local Play cache.
///
/// ── AND WHY THE STORE IS ALSO SHARED FROM HERE ──────────────────────
///
/// Because two of them is a bug. Both instances see the same purchase
/// feed, and both would call `completePurchase` on the same
/// transaction. The paywall therefore borrows this one rather than
/// building its own - see [SubscribeScreen].
class MembershipSync {
  MembershipSync(this._membership, {SubscriptionService? store})
    : store = store ?? StoreSubscriptions();

  final MembershipProvider _membership;

  /// The app's one subscription service. Borrowed by the paywall.
  final SubscriptionService store;

  StreamSubscription<SubscriptionStatus>? _watch;

  bool _started = false;

  /// Begins listening, then asks the store what is already owned.
  ///
  /// Never throws and never blocks anything: a store that is
  /// unreachable, a device with no Play Services, a simulator with no
  /// StoreKit configuration selected - each leaves the person on the
  /// free experience, which is the right failure. Launch must not
  /// depend on the App Store being up.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _membership.applyStoreStatus(store.current);

    _watch = store.changes.listen(
      _membership.applyStoreStatus,
      // A dead feed is not a cancelled membership. Leave the tier
      // where it is rather than taking a badge off somebody because
      // the store stopped talking.
      onError: (Object e) => debugPrint('[subscriptions] feed: $e'),
    );

    try {
      await store.restore();
    } catch (e) {
      debugPrint('[subscriptions] launch restore failed: $e');
    }
  }

  /// Asks the store again, on demand.
  ///
  /// For coming back from the manage-subscriptions sheet, where
  /// somebody may have just cancelled or resubscribed and the purchase
  /// feed does not always say so.
  Future<void> refresh() async {
    try {
      await store.restore();
    } catch (e) {
      debugPrint('[subscriptions] refresh failed: $e');
    }
  }

  void dispose() {
    _watch?.cancel();
    store.dispose();
  }
}
