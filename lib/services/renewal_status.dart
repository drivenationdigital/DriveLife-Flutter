import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Whether a subscription is set to renew, which is not the same
/// question as whether it is active.
///
/// ── WHY THIS NEEDED WRITING AT ALL ──────────────────────────────────
///
/// `in_app_purchase` reports what is owned and when it expires, and
/// says nothing about auto-renewal. It lives on RenewalInfo, which the
/// plugin wraps on neither platform's Dart side.
///
/// So without this, somebody who cancelled an hour ago and somebody
/// perfectly happy on a monthly plan look identical to the app, and
/// both get offered "Manage or cancel". The first has already
/// cancelled. The screen is stale, and the one thing they might want -
/// to come back - is not on it.
///
/// ── THE THREE ANSWERS, AND WHY THERE ARE THREE ──────────────────────
///
/// true, false, and null. Null is not a failure: it means nobody could
/// say, which is a real state on iOS below 15, on a platform with no
/// store, and whenever the lookup fails.
///
/// It gets its own answer because the alternative is picking one of
/// the other two and being wrong half the time. "Unknown" draws
/// cautious wording - what they have and when it runs out - without
/// claiming a renewal nobody checked.
/// What the store says about one subscription's next renewal.
class Renewal {
  /// Whether it will renew at all. False means cancelled.
  final bool willRenew;

  /// The product it will renew INTO, when that is not the one they
  /// hold. Null when nothing is pending, or when the platform cannot
  /// say.
  ///
  /// Only iOS reports this. Apple applies an upgrade immediately and
  /// DEFERS a downgrade to the end of the paid period, so a downgrade
  /// is invisible without it: the person still holds the old plan and
  /// everything looks normal until the day it changes under them.
  final String? renewingTo;

  const Renewal({required this.willRenew, this.renewingTo});
}

class RenewalStatus {
  static const MethodChannel _ios = MethodChannel('drivelife/subscription');

  /// What happens next to [productId]. Null means nobody could say.
  ///
  /// Cheap enough to call on every screen build? No. Call it when the
  /// status changes and when coming back from the manage sheet.
  static Future<Renewal?> forProduct(String productId) async {
    final all = await all_();

    return all[productId];
  }

  /// Every subscription this device can see.
  ///
  /// Named with a trailing underscore to keep `all` free as a getter
  /// if this ever grows one.
  static Future<Map<String, Renewal>> all_() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) return _fromStoreKit();

    if (defaultTargetPlatform == TargetPlatform.android) return _fromPlay();

    return const {};
  }

  /// iOS: the native channel in AppDelegate.swift, which reads
  /// StoreKit 2's RenewalInfo directly.
  ///
  /// Works against a local .storekit configuration exactly as against
  /// the App Store, so cancelling in Xcode's Transaction Manager shows
  /// up here straight away.
  static Future<Map<String, Renewal>> _fromStoreKit() async {
    try {
      final raw = await _ios.invokeMethod<List<dynamic>>('renewalStatus');

      if (raw == null) return const {};

      final out = <String, Renewal>{};

      for (final entry in raw) {
        if (entry is! Map) continue;

        final id = entry['productId'];
        final renews = entry['willRenew'];

        if (id is! String || renews is! bool) continue;

        final next = entry['renewingTo'];

        // Equal to the current product means nothing is pending, and
        // empty means StoreKit did not say. Neither is a plan change,
        // and treating either as one would announce a downgrade to
        // somebody who has not asked for anything.
        final pending = next is String && next.isNotEmpty && next != id
            ? next
            : null;

        out[id] = Renewal(willRenew: renews, renewingTo: pending);
      }

      return out;
    } on MissingPluginException {
      // The channel is not there: an older build of the native side,
      // or a platform that never had it. Not an error, and not a
      // reason to claim anything about renewal.
      return const {};
    } catch (e) {
      debugPrint('[subscriptions] renewal status failed: $e');

      return const {};
    }
  }

  /// Android: Play puts it on the purchase, so no channel is needed.
  ///
  /// Read through `restorePurchases`, which emits what is owned onto
  /// the purchase feed. That feed is already being listened to for
  /// other reasons, so this only has to catch what goes past.
  static Future<Map<String, Renewal>> _fromPlay() async {
    try {
      final iap = InAppPurchase.instance;

      if (!await iap.isAvailable()) return const {};

      final out = <String, Renewal>{};
      final done = Completer<void>();

      late final StreamSubscription<List<PurchaseDetails>> watch;

      watch = iap.purchaseStream.listen((purchases) {
        for (final purchase in purchases) {
          if (purchase is GooglePlayPurchaseDetails) {
            // Play tells us whether it renews, not what into. A
            // pending plan change is invisible here, so renewingTo
            // stays null and the screen simply does not mention one.
            out[purchase.productID] = Renewal(
              willRenew: purchase.billingClientPurchase.isAutoRenewing,
            );
          }
        }

        if (!done.isCompleted) done.complete();
      });

      await iap.restorePurchases();

      // Bounded: a device that owns nothing never emits, and this
      // must not hang the screen waiting for a stream that has
      // nothing to say.
      await done.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );

      await watch.cancel();

      return out;
    } catch (e) {
      debugPrint('[subscriptions] play renewal status failed: $e');

      return const {};
    }
  }
}
