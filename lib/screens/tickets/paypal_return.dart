import 'dart:async';

import 'package:flutter/foundation.dart';

/// How PayPal gets the buyer back to the payment screen.
///
/// Approval happens on PayPal's own pages — there is no way around that, and
/// no app anywhere avoids it. The buyer leaves, approves, and PayPal redirects
/// to a `drivelife://` link, which arrives at the deep-link handler rather
/// than at the screen that is waiting for it.
///
/// This is the one wire between them: the payment screen parks on [awaitResult]
/// and the deep-link handler calls [deliver].
abstract final class PayPalReturn {
  const PayPalReturn._();

  static Completer<PayPalOutcome>? _pending;

  /// Whether a payment screen is currently waiting to hear back.
  static bool get isWaiting => _pending != null && !_pending!.isCompleted;

  /// Waits for PayPal to send the buyer back.
  ///
  /// Times out rather than waiting forever: a buyer can abandon PayPal by
  /// killing the browser, in which case nothing will ever arrive and the
  /// screen would sit on a spinner until the app was restarted.
  static Future<PayPalOutcome> awaitResult({
    Duration timeout = const Duration(minutes: 15),
  }) {
    // A previous wait that nobody answered. Abandon it rather than leave two
    // completers fighting over the next redirect.
    _pending?.complete(const PayPalOutcome.abandoned());

    final completer = Completer<PayPalOutcome>();
    _pending = completer;

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending = null;
        return const PayPalOutcome.abandoned();
      },
    );
  }

  /// Called by the deep-link handler when PayPal redirects back.
  ///
  /// [status] is whatever was put in the return URL — "done" or "cancel" —
  /// and [token] is the PayPal order id, which PayPal appends itself.
  static void deliver({required String status, String? token}) {
    final completer = _pending;
    _pending = null;

    if (completer == null || completer.isCompleted) {
      // Nothing is waiting: the app was killed while the buyer was at PayPal
      // and relaunched by the redirect. The order is still pending server
      // side and the organiser can see it, so this is dropped rather than
      // guessed at.
      debugPrint('💰 [PayPal] Returned with nothing waiting for it');
      return;
    }

    completer.complete(
      status == 'cancel'
          ? const PayPalOutcome.cancelled()
          : PayPalOutcome.approved(token ?? ''),
    );
  }

  /// Gives up on any wait in progress, so a screen going away does not leave
  /// a completer that the next payment would inherit.
  static void stopWaiting() {
    final completer = _pending;
    _pending = null;

    if (completer != null && !completer.isCompleted) {
      completer.complete(const PayPalOutcome.abandoned());
    }
  }
}

/// What came back from PayPal.
@immutable
class PayPalOutcome {
  /// The PayPal order id, when the buyer approved.
  final String? orderId;

  /// The buyer pressed cancel at PayPal.
  final bool cancelled;

  /// Nothing came back — closed the browser, or waited too long.
  final bool abandoned;

  const PayPalOutcome.approved(String this.orderId)
    : cancelled = false,
      abandoned = false;

  const PayPalOutcome.cancelled()
    : orderId = null,
      cancelled = true,
      abandoned = false;

  const PayPalOutcome.abandoned()
    : orderId = null,
      cancelled = false,
      abandoned = true;

  bool get isApproved => orderId != null && orderId!.isNotEmpty;
}
