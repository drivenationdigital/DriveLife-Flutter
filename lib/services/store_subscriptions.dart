import 'dart:async';

import 'package:drivelife/models/subscription_plan.dart';
import 'package:drivelife/services/renewal_status.dart';
import 'package:drivelife/services/subscription_service.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

/// The real store, behind the same interface the paywall already uses.
///
/// ── WHAT THIS IS AND IS NOT ─────────────────────────────────────────
///
/// It is the purchase FLOW: asking the store what it sells, starting a
/// purchase, handing back what happened, and completing the
/// transaction so the store stops re-delivering it.
///
/// It is NOT the answer to "is this person a member". The store tells
/// THIS DEVICE what it believes, and a rooted phone will happily lie.
/// docs/pro-membership-design.md §2 settles it: the server decides,
/// from a receipt it validated with Apple or Google, kept fresh by
/// server-to-server notifications. None of that exists yet.
///
/// So [changes] and [current] are a report of what the store said on
/// this device, suitable for driving the screen and for testing against
/// a local StoreKit configuration. They must not become the thing that
/// grants a benefit — see [MembershipProvider], which still takes its
/// tier from elsewhere on purpose.
///
/// ── TESTING IT WITHOUT SPENDING MONEY ───────────────────────────────
///
/// ios/DriveLife.storekit is a local StoreKit configuration. With it
/// selected in the scheme's Run action, the whole flow runs on a
/// simulator or device with no App Store Connect products, no sandbox
/// account and no charge. See ios/DriveLife.storekit.README.md.
class StoreSubscriptions implements SubscriptionService {
  StoreSubscriptions({InAppPurchase? iap})
    : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  final StreamController<SubscriptionStatus> _changes =
      StreamController<SubscriptionStatus>.broadcast();

  StreamSubscription<List<PurchaseDetails>>? _feed;

  SubscriptionStatus _current = SubscriptionStatus.none;

  /// Completes when the purchase the screen is waiting on resolves.
  ///
  /// The plugin reports purchases on one broadcast stream rather than
  /// returning them from [InAppPurchase.buyNonConsumable], including
  /// ones nobody asked for — a deferred payment clearing, or a
  /// subscription bought in iOS Settings. So [buy] parks a completer
  /// here and the feed completes it.
  Completer<PurchaseOutcome>? _awaiting;

  bool _started = false;

  /// Subscribes to the purchase feed. Safe to call more than once.
  ///
  /// Separate from the constructor because it has to happen before any
  /// purchase is started AND before [restore], and a constructor that
  /// starts listening makes the class awkward to construct in a test.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _feed = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object _) {
        // A dead feed must not look like a declined purchase: resolve
        // anything waiting as failed and let the screen say so.
        _finish(PurchaseOutcome.failed);
      },
    );
  }

  @override
  SubscriptionStatus get current => _current;

  @override
  Stream<SubscriptionStatus> get changes => _changes.stream;

  @override
  Future<List<StorePlan>> plans() async {
    await start();

    if (!await _iap.isAvailable()) return _fallbackPlans();

    final response = await _iap.queryProductDetails(
      SubscriptionPlan.values.map((p) => p.productId).toSet(),
    );

    // notFoundIDs is the ordinary symptom of a product that is not
    // registered, is not cleared for sale, or whose id has a typo. It
    // is not an error the buyer can act on, so it is logged rather
    // than surfaced, and the plan falls back to its own price.
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint(
        '[subscriptions] store did not return: ${response.notFoundIDs}',
      );
    }

    if (response.productDetails.isEmpty) return _fallbackPlans();

    final byId = {for (final d in response.productDetails) d.id: d};

    return [
      for (final plan in SubscriptionPlan.values)
        if (byId[plan.productId] case final d?)
          StorePlan(
            plan: plan,
            // The store's own localised, tax-inclusive string. Never
            // rebuilt from the raw amount: that is how an app ends up
            // showing "£4.99" to somebody being charged €5.99.
            price: d.price,
            title: d.title,
            description: d.description,
          )
        else
          StorePlan.fallback(plan),
    ];
  }

  List<StorePlan> _fallbackPlans() => [
    for (final plan in SubscriptionPlan.values) StorePlan.fallback(plan),
  ];

  @override
  Future<PurchaseOutcome> buy(SubscriptionPlan plan) async {
    await start();

    if (!await _iap.isAvailable()) return PurchaseOutcome.failed;

    final response = await _iap.queryProductDetails({plan.productId});
    final product = response.productDetails
        .where((d) => d.id == plan.productId)
        .firstOrNull;

    // Nothing to buy. Distinct from a declined payment, but there is
    // nothing the buyer can do about either, so it reads the same.
    if (product == null) {
      debugPrint('[subscriptions] no product for ${plan.productId}');
      return PurchaseOutcome.failed;
    }

    final waiting = _awaiting = Completer<PurchaseOutcome>();

    try {
      // buyNonConsumable, not buyConsumable: a subscription is owned
      // until it lapses, and the store must keep reporting it so a
      // reinstall can restore it.
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (e) {
      debugPrint('[subscriptions] buy threw: $e');
      _awaiting = null;
      return PurchaseOutcome.failed;
    }

    return waiting.future;
  }

  @override
  Future<SubscriptionStatus> restore() async {
    await start();

    if (!await _iap.isAvailable()) return _current;

    // restorePurchases returns nothing: what it restores arrives on
    // the purchase feed like any other purchase. So this asks, waits a
    // moment for the feed to speak, and reports whatever it then says.
    await _iap.restorePurchases();
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // ── AND ASK AGAIN WHETHER IT RENEWS ──────────────────────────
    //
    // This is the call made after the manage sheet closes, which is
    // exactly when somebody has just cancelled. restorePurchases
    // reports what is OWNED, and a cancelled subscription is still
    // owned until it expires - so without this the screen comes back
    // from a cancellation reporting the state from before it.
    //
    // Awaited here, unlike in _grant. The caller is a refresh that is
    // already showing a spinner and whose entire purpose is to come
    // back with the new answer.
    final plan = _current.plan;

    if (_current.active && plan != null) {
      final renewal = await RenewalStatus.forProduct(plan.productId);

      if (renewal != null && _current.active && _current.plan == plan) {
        _set(
          _current.copyWith(
            willRenew: renewal.willRenew,
            renewingTo: renewal.renewingTo == null
                ? null
                : SubscriptionPlan.forProduct(renewal.renewingTo!),
          ),
        );
      }
    }

    return _current;
  }

  /// Handles a batch from the purchase feed.
  ///
  /// ── WHY EVERY PURCHASE IS WRAPPED ───────────────────────────────
  ///
  /// This is an ASYNC listener callback, and the stream's `onError`
  /// does not cover it: `onError` is for errors the stream delivers,
  /// not for something thrown inside the handler. An uncaught throw
  /// here becomes an unhandled asynchronous error, which on a debug
  /// build stops the app dead at launch — [MembershipSync] calls
  /// `restore()` on boot, restored transactions arrive here, and
  /// `completePurchase` on one the store already considers finished
  /// is enough to do it.
  ///
  /// So each purchase is handled in isolation: one bad transaction is
  /// logged and stepped over rather than taking the launch with it,
  /// and the rest of the batch is still processed.
  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      try {
        await _handle(purchase);
      } catch (e) {
        debugPrint('[subscriptions] handling ${purchase.productID}: $e');

        // Something is waiting on this and must not wait forever.
        _finish(PurchaseOutcome.failed);
      }
    }
  }

  Future<void> _handle(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        // Google Play deferred payment. Not granted, not failed.
        _finish(PurchaseOutcome.pending);

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        _grant(purchase);
        _finish(
          purchase.status == PurchaseStatus.restored
              ? PurchaseOutcome.alreadyOwned
              : PurchaseOutcome.success,
        );

      case PurchaseStatus.canceled:
        _finish(PurchaseOutcome.cancelled);

      case PurchaseStatus.error:
        debugPrint('[subscriptions] ${purchase.error}');
        _finish(PurchaseOutcome.failed);
    }

    // Required by both stores, and required even for a failure: an
    // uncompleted transaction is re-delivered on every launch and,
    // on iOS, blocks later purchases behind it.
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  /// Records what the store says this device owns.
  ///
  /// Device-reported only — see the note at the top of the class.
  void _grant(PurchaseDetails purchase) {
    final plan = SubscriptionPlan.values
        .where((p) => p.productId == purchase.productID)
        .firstOrNull;

    // A product this build cannot name is not a reason to grant
    // anything. Same rule as MembershipTier.forProduct: the accident
    // is always upward, so the answer is no.
    if (plan == null) {
      debugPrint('[subscriptions] unknown product ${purchase.productID}');
      return;
    }

    _set(
      SubscriptionStatus(
        active: true,
        plan: plan,
        renewsAt: _expiryOf(purchase),
      ),
    );

    // Asked for separately, and after. Neither store puts it on the
    // purchase in a form the plugin exposes, so it is a second trip -
    // and the screen must not wait on it, because "you are a member"
    // is worth drawing immediately and "it renews on the 24th" can
    // arrive a moment later.
    unawaited(_fillRenewal(plan));
  }

  /// Asks whether the current plan is set to renew, and republishes.
  ///
  /// Quiet on failure: an unknown renewal state is a real state that
  /// the screen already draws sensibly - see SubscriptionStatus.
  Future<void> _fillRenewal(SubscriptionPlan plan) async {
    final renewal = await RenewalStatus.forProduct(plan.productId);

    if (renewal == null) return;

    // Only if it still describes the same subscription. A purchase or
    // a lapse while this was in flight makes the answer stale, and a
    // stale renewal flag is what this whole path exists to prevent.
    if (!_current.active || _current.plan != plan) return;

    _set(
      _current.copyWith(
        willRenew: renewal.willRenew,
        // A product id this build cannot name means nothing is shown,
        // which is better than naming a plan wrongly.
        renewingTo: renewal.renewingTo == null
            ? null
            : SubscriptionPlan.forProduct(renewal.renewingTo!),
      ),
    );
  }

  /// When the store says this subscription next renews.
  ///
  /// Taken from the transaction rather than worked out from the plan's
  /// length. "Bought today, so it renews in a month" is wrong for
  /// anybody who subscribed before this session - which, after launch
  /// day, is nearly everybody - and wrong again for a free trial, an
  /// introductory offer, or a plan switched mid-term.
  ///
  /// Only StoreKit 2 reports it. Android and StoreKit 1 return null,
  /// and the screen simply omits the line rather than guessing.
  static DateTime? _expiryOf(PurchaseDetails purchase) {
    if (purchase is! SK2PurchaseDetails) return null;

    final millis = int.tryParse(purchase.expirationDate ?? '');

    if (millis == null) return null;

    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  void _finish(PurchaseOutcome outcome) {
    final waiting = _awaiting;
    _awaiting = null;

    if (waiting != null && !waiting.isCompleted) waiting.complete(outcome);
  }

  void _set(SubscriptionStatus status) {
    _current = status;

    if (!_changes.isClosed) _changes.add(status);
  }

  @override
  void dispose() {
    _feed?.cancel();
    _changes.close();
  }
}
