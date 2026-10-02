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

  /// Whether an event with no card provider of its own may be charged through
  /// DriveLife's own Stripe account.
  ///
  /// On, because that is the rule: exactly one of Stripe, Square or Mollie is
  /// the organiser's primary card provider, and where none is connected the
  /// platform's Stripe is the fallback so every event can still sell a ticket.
  /// PayPal never occupies that slot — it sits alongside whichever card
  /// provider applies, including the fallback.
  ///
  /// An organiser with no `stripe_account_id` has no Connect relationship, so
  /// the PaymentIntent is created on the platform account and DriveLife
  /// collects on their behalf. That is the deliberate choice here, and it
  /// matches what the web checkout has always done — see
  /// cc_pay_card_processor(), which returns 'stripe' for exactly this case.
  ///
  /// Kept as a switch rather than hard-coded because the 2027 direction is to
  /// need it less: as organisers connect their own Stripe, fewer events reach
  /// the fallback at all. Setting DL_ALLOW_PLATFORM_STRIPE=false makes the app
  /// refuse those payments and send them to the web checkout instead, which
  /// is the behaviour to reach for if collecting on an organiser's behalf ever
  /// has to stop.
  static const bool allowPlatformCharges = bool.fromEnvironment(
    'DL_ALLOW_PLATFORM_STRIPE',
    defaultValue: true,
  );

  /// Whether this event's Stripe settings are ones the app will charge.
  ///
  /// A key is required either way — without one there is nothing to confirm
  /// against. A connected account means the money goes straight to the
  /// organiser; no account means the platform fallback, which is allowed only
  /// while [allowPlatformCharges] says so.
  static bool mayChargeNatively({required String key, String? account}) {
    if (key.trim().isEmpty) return false;

    final connected = (account ?? '').trim().isNotEmpty;

    return connected || allowPlatformCharges;
  }

  /// True while the SDK is pointed somewhere other than the app's account.
  static bool _borrowed = false;

  /// Whether the key in use is a test key.
  ///
  /// Read rather than hardcoded: an organiser's connected account can be in
  /// test mode while ours is live, and Google Pay has to be told which.
  static bool get isTestMode => Stripe.publishableKey.startsWith('pk_test');

  /// Points the SDK at an organiser's account for a ticket purchase.
  ///
  /// No fallback to the app's own key. An empty key used to quietly become
  /// DriveLife's, which is the store's account and the one thing a ticket
  /// must never be charged to by accident — call [mayChargeNatively] first
  /// and do not get here without a key.
  static Future<void> useTicketAccount({
    required String publishableKey,
    String? connectedAccountId,
  }) async {
    final key = publishableKey.trim();
    assert(key.isNotEmpty, 'useTicketAccount needs the event\'s own key');
    if (key.isEmpty) return;

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
