import 'dart:async';

import 'package:flutter/foundation.dart';

/// How a payment taken on somebody else's pages gets back to the app.
///
/// PayPal and Mollie both send the buyer away — to PayPal's approval page, or
/// to Mollie's hosted checkout and from there possibly into a banking app for
/// 3-D Secure. Neither can be avoided, and no app anywhere avoids them. The
/// buyer returns through a `drivelife://` link, which arrives at the
/// deep-link handler rather than at the screen that is waiting for it.
///
/// This is the one wire between them: the payment screen parks on
/// [awaitResult] and the deep-link handler calls [deliver].
abstract final class HostedPaymentReturn {
  const HostedPaymentReturn._();

  static Completer<HostedPaymentOutcome>? _pending;

  /// Which provider the waiting screen sent the buyer to.
  ///
  /// A redirect for one must not satisfy a wait for the other — most likely
  /// when a stale link arrives from an abandoned attempt.
  static String? _provider;

  static bool get isWaiting => _pending != null && !_pending!.isCompleted;

  /// Waits for [provider] to send the buyer back.
  ///
  /// Times out rather than waiting forever: a buyer can abandon a hosted page
  /// by killing the browser, in which case nothing will ever arrive and the
  /// screen would sit on a spinner until the app was restarted.
  static Future<HostedPaymentOutcome> awaitResult(
    String provider, {
    Duration timeout = const Duration(minutes: 15),
  }) {
    // A previous wait nobody answered. Abandon it rather than leave two
    // completers fighting over the next redirect.
    _pending?.complete(const HostedPaymentOutcome.abandoned());

    final completer = Completer<HostedPaymentOutcome>();
    _pending = completer;
    _provider = provider;

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending = null;
        _provider = null;
        return const HostedPaymentOutcome.abandoned();
      },
    );
  }

  /// Called by the deep-link handler when a provider redirects back.
  ///
  /// [status] is whatever was put in the return URL — "done" or "cancel" —
  /// and [reference] is the provider's own id for the attempt, which PayPal
  /// appends as `token` and Mollie does not send at all.
  static void deliver({
    required String provider,
    required String status,
    String? reference,
  }) {
    final completer = _pending;

    if (completer == null || completer.isCompleted) {
      // Nothing is waiting: the app was killed while the buyer was away and
      // relaunched by the redirect. The order is still pending server side
      // and the organiser can see it, so this is dropped rather than guessed
      // at — and both providers confirm server to server anyway.
      debugPrint('💰 [$provider] Returned with nothing waiting for it');
      return;
    }

    if (_provider != provider) {
      debugPrint('💰 [$provider] Return ignored; waiting on $_provider');
      return;
    }

    _pending = null;
    _provider = null;

    completer.complete(
      status == 'cancel'
          ? const HostedPaymentOutcome.cancelled()
          : HostedPaymentOutcome.returned(reference),
    );
  }

  /// Gives up on any wait in progress, so a screen going away does not leave
  /// a completer the next payment would inherit.
  static void stopWaiting() {
    final completer = _pending;
    _pending = null;
    _provider = null;

    if (completer != null && !completer.isCompleted) {
      completer.complete(const HostedPaymentOutcome.abandoned());
    }
  }
}

/// What came back from a hosted payment page.
@immutable
class HostedPaymentOutcome {
  /// The provider's id for the attempt, where it sends one back.
  ///
  /// PayPal appends its order id; Mollie sends nothing, and the payment is
  /// identified by the id the app already holds from creating it. So a null
  /// reference is not a failure — the caller knows whether it needed one.
  final String? reference;

  /// The buyer pressed cancel on the provider's page.
  final bool cancelled;

  /// Nothing came back — closed the browser, or waited too long.
  final bool abandoned;

  const HostedPaymentOutcome.returned(this.reference)
    : cancelled = false,
      abandoned = false;

  const HostedPaymentOutcome.cancelled()
    : reference = null,
      cancelled = true,
      abandoned = false;

  const HostedPaymentOutcome.abandoned()
    : reference = null,
      cancelled = false,
      abandoned = true;

  /// The buyer came back under their own steam, whatever the verdict turns
  /// out to be. The provider decides that, not this.
  bool get didReturn => !cancelled && !abandoned;
}
