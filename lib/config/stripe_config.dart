import 'package:drivelife/main.dart' show stripePublishableKey;
import 'package:flutter_stripe/flutter_stripe.dart';

/// Which Stripe account the SDK is currently pointed at.
///
/// The app sells two different things through Stripe and they do not share an
/// account:
///
/// * the **store**, which is DriveLife's own merchant account and the key the
///   app is initialised with at launch;
/// * **event tickets**, where the money belongs to the organiser. Those are
///   charged on the organiser's own connected account, with their own
///   publishable key, and the server mints the PaymentIntent there.
///
/// flutter_stripe has one global configuration, so paying for a ticket means
/// repointing it and then putting it back. Confirming an organiser's intent
/// with the platform's key fails as "No such payment_intent", which looks
/// like a declined card rather than a misconfiguration — and leaving it
/// repointed afterwards would send the next store purchase to the wrong
/// account entirely.
abstract final class StripeConfig {
  const StripeConfig._();

  /// True while the SDK is pointed somewhere other than the app's account.
  static bool _borrowed = false;

  /// Whether the key in use is a test key.
  ///
  /// Read rather than hardcoded: an organiser's connected account can be in
  /// test mode while ours is live, and Google Pay has to be told which.
  static bool get isTestMode => Stripe.publishableKey.startsWith('pk_test');

  /// Points the SDK at an organiser's account for a ticket purchase.
  ///
  /// [publishableKey] empty falls back to the app's own key, which is what
  /// the backend uses when an organiser has no Stripe of their own — in that
  /// case the intent really is on the platform account and there is nothing
  /// to switch.
  static Future<void> useTicketAccount({
    required String publishableKey,
    String? connectedAccountId,
  }) async {
    final key = publishableKey.trim().isEmpty
        ? stripePublishableKey
        : publishableKey.trim();

    final account = (connectedAccountId ?? '').trim();

    Stripe.publishableKey = key;
    Stripe.stripeAccountId = account.isEmpty ? null : account;

    _borrowed = true;

    // Settings are read when the sheet is built, so they have to be applied
    // before initPaymentSheet rather than at the next launch.
    await Stripe.instance.applySettings();
  }

  /// Puts the SDK back on the app's own account.
  ///
  /// Called whenever a ticket payment screen goes away, however it went —
  /// paid, cancelled or backed out of. Cheap and idempotent, because the cost
  /// of missing it once is a store purchase charged to an organiser.
  static void restoreAppAccount() {
    if (!_borrowed) return;

    _borrowed = false;

    Stripe.publishableKey = stripePublishableKey;
    Stripe.stripeAccountId = null;

    // Not awaited: this runs from dispose, where there is nothing left to
    // wait on it, and the next payment applies its own settings first.
    Stripe.instance.applySettings();
  }
}
