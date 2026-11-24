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
class RenewalStatus {
  static const MethodChannel _ios = MethodChannel('drivelife/subscription');

  /// Whether [productId] is set to renew. Null means nobody could say.
  ///
  /// Cheap enough to call on every screen build? No. Call it when the
  /// status changes and when coming back from the manage sheet.
  static Future<bool?> willRenew(String productId) async {
    final all = await all_();

    return all[productId];
  }

  /// Every subscription this device can see, and whether each renews.
  ///
  /// Named with a trailing underscore to keep `all` free as a getter
  /// if this ever grows one.
  static Future<Map<String, bool>> all_() async {
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
  static Future<Map<String, bool>> _fromStoreKit() async {
    try {
      final raw = await _ios.invokeMethod<List<dynamic>>('renewalStatus');

      if (raw == null) return const {};

      final out = <String, bool>{};

      for (final entry in raw) {
        if (entry is! Map) continue;

        final id = entry['productId'];
        final renews = entry['willRenew'];

        if (id is String && renews is bool) out[id] = renews;
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
  static Future<Map<String, bool>> _fromPlay() async {
    try {
      final iap = InAppPurchase.instance;

      if (!await iap.isAvailable()) return const {};

      final out = <String, bool>{};
      final done = Completer<void>();

      late final StreamSubscription<List<PurchaseDetails>> watch;

      watch = iap.purchaseStream.listen((purchases) {
        for (final purchase in purchases) {
          if (purchase is GooglePlayPurchaseDetails) {
            out[purchase.productID] =
                purchase.billingClientPurchase.isAutoRenewing;
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
