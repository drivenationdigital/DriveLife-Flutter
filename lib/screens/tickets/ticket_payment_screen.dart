import 'dart:async';
import 'dart:io' show Platform;

import 'package:drivelife/api/checkout_api.dart';
import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/config/stripe_config.dart';
import 'package:drivelife/screens/tickets/paypal_return.dart';
import 'package:drivelife/models/checkout_models.dart';
import 'package:drivelife/screens/tickets/ticket_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:square_in_app_payments/google_pay_constants.dart';
import 'package:square_in_app_payments/in_app_payments.dart';
import 'package:square_in_app_payments/models.dart';
import 'package:url_launcher/url_launcher.dart';

/// Step three: paying.
///
/// Stripe only. The organiser's other methods — PayPal, Square, Mollie — are
/// their own merchant accounts with their own browser SDKs, and none of them
/// has a native equivalent; events using those still go to the web checkout.
///
/// The money never passes through this screen. The PaymentIntent was minted
/// server-side against the cart, and all that happens here is confirming it
/// and telling the backend what Stripe said.
class TicketPaymentScreen extends StatefulWidget {
  final CheckoutInfo info;
  final String cartToken;

  /// The intent the server opened for this cart.
  final String clientSecret;

  /// What Stripe will take.
  final double amount;

  /// The server's breakdown behind [amount], for the summary.
  final CartTotals totals;

  /// The order fields gathered on the details step, sent again on completion.
  final Map<String, String> orderForm;

  final String buyerName;
  final String buyerEmail;
  final String buyerPhone;

  const TicketPaymentScreen({
    super.key,
    required this.info,
    required this.cartToken,
    required this.clientSecret,
    required this.amount,
    required this.totals,
    required this.orderForm,
    required this.buyerName,
    required this.buyerEmail,
    required this.buyerPhone,
  });

  @override
  State<TicketPaymentScreen> createState() => _TicketPaymentScreenState();
}

class _TicketPaymentScreenState extends State<TicketPaymentScreen> {
  bool _busy = false;
  String? _error;

  /// Whether a card payment can actually be taken here.
  ///
  /// Not the same as the event offering Stripe. Without the organiser's own
  /// connected account the money would go through DriveLife, so the card
  /// option is withheld and PayPal — which pays them directly — is all that
  /// is shown.
  bool get _stripeUsable =>
      widget.info.hasStripe &&
      widget.clientSecret.isNotEmpty &&
      StripeConfig.mayChargeNatively(
        key: widget.info.stripe.key,
        account: widget.info.stripe.account,
      );

  /// Whether this event's card payments go through Square.
  ///
  /// Stripe, Square and Mollie are mutually exclusive — the organiser has one
  /// card processor — so at most one of these is ever true.
  bool get _squareUsable {
    final square = widget.info.square;
    return square != null &&
        square.applicationId.isNotEmpty &&
        square.locationId.isNotEmpty;
  }

  /// Which processor sits behind the "Card" option, or null for none.
  String? get _cardMethod => _stripeUsable
      ? 'stripe'
      : (_squareUsable ? 'square' : null);

  /// What the buyer is paying with.
  ///
  /// A choice only when a card and PayPal are both available; otherwise there
  /// is nothing to pick and the button says what it does.
  late String _method = _cardMethod ?? 'paypal';

  /// The Stripe settings this event's intent was created against.
  ///
  /// Not ours. Ticket money goes to the organiser, on their own connected
  /// account, with their own publishable key — which is why this cannot reuse
  /// the key the app is initialised with for the store.
  ({String key, String? account}) get _stripe => widget.info.stripe;

  @override
  void initState() {
    super.initState();
    if (_squareUsable) unawaited(_prepareSquareWallet());
  }

  @override
  void dispose() {
    // The app's own key is restored whatever happened here, so the store
    // checkout is never left pointing at an organiser's account.
    StripeConfig.restoreAppAccount();

    // A payment screen going away must not leave a PayPal wait behind for the
    // next one to inherit.
    PayPalReturn.stopWaiting();
    super.dispose();
  }

  /// Takes the payment with whichever method is selected.
  Future<void> _pay() => switch (_method) {
    'paypal' => _payWithPayPal(),
    'square' => _payWithSquare(),
    _ => _payWithStripe(),
  };

  /// Square: card entry and SCA in Square's own sheet, charged server-side.
  ///
  /// The card never reaches our code — the SDK returns a single-use nonce and,
  /// where the buyer's bank demands it, a verification token. Both go to the
  /// PHP, which charges the organiser's own Square account.
  Future<void> _payWithSquare() async {
    final square = widget.info.square;

    if (square == null || square.applicationId.isEmpty) {
      setState(() {
        _error = 'This event cannot be paid for in the app. Open it on the '
            'website to finish your order — your tickets are still held.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await InAppPayments.setSquareApplicationId(square.applicationId);

      // Square draws its own card screen. On iOS it is themed from here; on
      // Android it is XML, because the SDK builds it natively before Dart
      // gets a say — see sqip_Theme_CardEntry in styles.xml.
      if (Platform.isIOS) await _applySquareTheme();

      await InAppPayments.startCardEntryFlowWithBuyerVerification(
        // "Charge", not "Store": this authorises one payment of this amount
        // rather than keeping the card on file.
        buyerAction: 'Charge',
        money: Money(
          (b) => b
            // Minor units. The figure is the one the server priced, not a
            // total computed here.
            ..amount = (widget.amount * 100).round()
            ..currencyCode = widget.info.event.currency.toUpperCase(),
        ),
        squareLocationId: square.locationId,
        // What Square shows the bank during verification. The details the
        // buyer already gave, so they are not asked twice.
        contact: Contact(
          (b) => b
            ..givenName = _firstName
            ..familyName = _lastName
            ..email = widget.buyerEmail
            ..countryCode = _merchantCountry,
        ),
        onBuyerVerificationSuccess: _onSquareVerified,
        onBuyerVerificationFailure: (error) {
          // No showCardNonceProcessingError here — see _onSquareVerified.
          if (!mounted) return;
          setState(() {
            _busy = false;
            _error = error.message;
          });
        },
        onCardEntryCancel: () {
          // Backing out of the card sheet is not an error. Nothing was
          // charged and the cart is untouched.
          if (!mounted) return;
          setState(() => _busy = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong taking the payment. Please try again.';
      });

      if (AppEnvironment.isStaging) debugPrint('💳 [Square] $e');
    }
  }

  /// The Apple Pay merchant identifier this app is registered under.
  ///
  /// The same one Stripe uses — it identifies who is ASKING the wallet, not
  /// who is paid. Square routes the resulting token to the organiser.
  static const String _appleMerchantId = 'merchant.com.app.carcalendar';

  /// Whether this device can pay Square with a wallet.
  ///
  /// Checked once when the screen opens rather than on tap: the button has to
  /// be there or not be there before the buyer reaches for it.
  bool _squareWalletReady = false;

  /// Apple Pay on iOS, Google Pay on Android.
  String get _walletName => Platform.isIOS ? 'Apple Pay' : 'Google Pay';

  /// Sets up Square's wallet support, if the device has any.
  ///
  /// Quiet on failure. A wallet is a shortcut past typing a card, never the
  /// only way to pay — if it cannot be prepared the card form is still there,
  /// and an error about it would be noise.
  Future<void> _prepareSquareWallet() async {
    final square = widget.info.square;
    if (square == null || square.locationId.isEmpty) return;

    try {
      await InAppPayments.setSquareApplicationId(square.applicationId);

      if (Platform.isAndroid) {
        await InAppPayments.initializeGooglePay(
          square.locationId,
          square.environment == 'production'
              ? environmentProduction
              : environmentTest,
        );

        final ready = await InAppPayments.canUseGooglePay;
        if (mounted) setState(() => _squareWalletReady = ready);
        return;
      }

      if (Platform.isIOS) {
        // The same merchant id the app registers for Apple Pay elsewhere.
        // Square routes the token to the organiser; the merchant id only
        // identifies who is asking the wallet.
        await InAppPayments.initializeApplePay(_appleMerchantId);

        final ready = await InAppPayments.canUseApplePay;
        if (mounted) setState(() => _squareWalletReady = ready);
      }
    } catch (e) {
      if (AppEnvironment.isStaging) debugPrint('💳 [Square] wallet: $e');
    }
  }

  /// Pays with the device wallet through Square.
  ///
  /// The wallet tokenises into the same `source_id` a typed card produces, so
  /// the server charges it identically. No buyer verification: the wallet has
  /// already authenticated the cardholder, which is the whole point of it.
  Future<void> _payWithSquareWallet() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    // Square wants the amount as a decimal string, not minor units.
    final price = widget.amount.toStringAsFixed(2);
    final currency = widget.info.event.currency.toUpperCase();

    try {
      if (Platform.isAndroid) {
        await InAppPayments.requestGooglePayNonce(
          price: price,
          currencyCode: currency,
          priceStatus: totalPriceStatusFinal,
          onGooglePayNonceRequestSuccess: (result) =>
              _chargeSquareWallet(result.nonce),
          onGooglePayNonceRequestFailure: (error) => _walletFailed(error.message),
          onGooglePayCanceled: _walletCancelled,
        );
        return;
      }

      await InAppPayments.requestApplePayNonce(
        price: price,
        summaryLabel: widget.info.event.title,
        countryCode: _merchantCountry,
        currencyCode: currency,
        paymentType: ApplePayPaymentType.finalPayment,
        onApplePayNonceRequestSuccess: (result) async {
          // Apple's sheet stays up until it is told the outcome, so the
          // charge happens first and the sheet is closed with the verdict.
          final ok = await _chargeSquareWallet(result.nonce, closeApple: false);

          await InAppPayments.completeApplePayAuthorization(
            isSuccess: ok,
            errorMessage: ok ? '' : (_error ?? 'Payment failed'),
          );
        },
        onApplePayNonceRequestFailure: (error) => _walletFailed(error.message),
        onApplePayComplete: () {},
      );
    } catch (e) {
      _walletFailed('That payment could not be started. Please try again.');
      if (AppEnvironment.isStaging) debugPrint('💳 [Square] wallet pay: $e');
    }
  }

  /// Sends a wallet nonce to be charged. Returns whether it went through.
  Future<bool> _chargeSquareWallet(String nonce, {bool closeApple = true}) async {
    try {
      final result = await CheckoutApi.squarePay(
        widget.cartToken,
        widget.info.event.eid,
        nonce,
        // No verification token: the wallet authenticated the cardholder, and
        // square.php only forwards one when it is given one.
        '',
        widget.info.event.site,
      );

      final status = result.paymentStatus;

      if (status != 'succeeded' && status != 'processing') {
        _walletFailed('That payment was not completed. Please try again.');
        return false;
      }

      await _complete(result.transactionId, status, provider: 'square');
      return true;
    } on CheckoutException catch (e) {
      _walletFailed(e.message);
      return false;
    }
  }

  void _walletFailed(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  void _walletCancelled() {
    // Dismissing the wallet is not an error. Nothing charged, cart untouched.
    if (!mounted) return;
    setState(() => _busy = false);
  }

  /// Dresses Square's iOS card screen in the checkout's own colours.
  ///
  /// Only the fields the theme actually needs. Square falls back to its own
  /// defaults for anything left unset, which is better than guessing at a
  /// value and getting a near-miss.
  Future<void> _applySquareTheme() async {
    RGBAColor rgb(int r, int g, int b) =>
        RGBAColor((c) => c..r = r..g = g..b = b);

    await InAppPayments.setIOSCardEntryTheme(
      IOSTheme(
        (t) => t
          ..backgroundColor = rgb(250, 249, 247).toBuilder()
          ..foregroundColor = rgb(255, 255, 255).toBuilder()
          ..textColor = rgb(20, 20, 15).toBuilder()
          ..placeholderTextColor = rgb(168, 165, 156).toBuilder()
          // Cursor, focus and the active save button.
          ..tintColor = rgb(196, 160, 98).toBuilder()
          ..messageColor = rgb(122, 122, 114).toBuilder()
          ..errorColor = rgb(192, 57, 43).toBuilder()
          ..saveButtonTitle = 'Pay'
          ..saveButtonTextColor = rgb(255, 255, 255).toBuilder()
          // Light: the rest of the checkout is, and a dark keyboard over a
          // cream form is the one place the seam would show.
          ..keyboardAppearance = KeyboardAppearance.light,
      ),
    );
  }

  /// Square has a card and, where required, the bank's blessing.
  ///
  /// Square's sheet has already closed by the time this runs, so neither
  /// completeCardEntry nor showCardNonceProcessingError may be called here.
  /// Those two belong to the plain card-entry flow, where the sheet stays
  /// open while the app charges the nonce and they release the latch holding
  /// it. The verification flow never creates that latch — CardEntryModule
  /// returns Finish() as soon as a contact is set — so calling either one
  /// throws a NullPointerException on countDownLatch.
  ///
  /// Anything to report therefore goes to this screen's own notice.
  Future<void> _onSquareVerified(BuyerVerificationDetails details) async {
    try {
      final result = await CheckoutApi.squarePay(
        widget.cartToken,
        widget.info.event.eid,
        details.nonce,
        details.token,
        widget.info.event.site,
      );

      final status = result.paymentStatus;

      if (status != 'succeeded' && status != 'processing') {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'That payment was not completed. Please try again.';
        });
        return;
      }

      await _complete(result.transactionId, status, provider: 'square');
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  String get _firstName =>
      widget.buyerName.split(' ').first.trim().isEmpty
      ? 'Guest'
      : widget.buyerName.split(' ').first.trim();

  String get _lastName {
    final parts = widget.buyerName.trim().split(' ');
    return parts.length > 1 ? parts.sublist(1).join(' ') : '';
  }

  /// PayPal: open an order, let the buyer approve it on PayPal's pages, then
  /// capture it server-side.
  ///
  /// The app never sees an amount — it carries the order id out and back, and
  /// the PHP prices and captures against the cart.
  Future<void> _payWithPayPal() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final order = await CheckoutApi.paypalCreate(
        widget.cartToken,
        widget.info.event.eid,
        widget.info.event.site,
        returnUrl: 'drivelife://app/?dl-paypal=done',
        cancelUrl: 'drivelife://app/?dl-paypal=cancel',
      );

      // Parked before the browser opens: PayPal can redirect back faster than
      // the launch call returns, and a wait started afterwards would miss it.
      final returned = PayPalReturn.awaitResult();

      final approvalUrl = order.approveUrl;

      if (AppEnvironment.isStaging) {
        debugPrint('💰 [PayPal] Opening $approvalUrl');
      }

      var launched = false;

      for (final mode in [
        LaunchMode.inAppBrowserView,
        LaunchMode.externalApplication,
      ]) {
        try {
          launched = await launchUrl(approvalUrl, mode: mode);
        } catch (_) {
          launched = false;
        }

        if (launched) break;
      }

      if (!launched) {
        PayPalReturn.stopWaiting();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = "We couldn't open PayPal. Please try again.";
        });
        return;
      }

      final outcome = await returned;

      if (!mounted) return;

      if (outcome.cancelled || outcome.abandoned) {
        // Cancelling is not an error. Nothing has been charged and the cart
        // is untouched, so they can try again or switch to a card.
        setState(() => _busy = false);
        return;
      }

      // Captured on the server against the charge PayPal recorded. The status
      // comes back in Stripe's vocabulary, so completion is the same path.
      final capture = await CheckoutApi.paypalCapture(
        widget.cartToken,
        widget.info.event.eid,
        outcome.orderId!,
        widget.info.event.site,
      );

      final status = capture.paymentStatus;

      if (status != 'succeeded' && status != 'processing') {
        setState(() {
          _busy = false;
          _error = 'PayPal did not complete this payment. Please try again.';
        });
        return;
      }

      await _complete(capture.transactionId, status, provider: 'paypal');
    } on CheckoutException catch (e) {
      PayPalReturn.stopWaiting();
      if (!mounted) return;
      setState(() {
        _busy = false;
        // On staging, show whatever the server attached. PayPal's refusals
        // reduce to one generic sentence by the time they reach a buyer, and
        // that sentence is the same for a misconfigured app as for a declined
        // card — useless to anyone testing.
        final debug = e.extra['debug'];

        _error = AppEnvironment.isStaging && debug != null
            ? '${e.message}\n\n$debug'
            : e.message;
      });
    } catch (_) {
      PayPalReturn.stopWaiting();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong with PayPal. Please try again.';
      });
    }
  }

  Future<void> _payWithStripe() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final provider = _stripe;

      // A backstop. The ticket step already refuses to start a native
      // checkout for an event whose money would not go straight to the
      // organiser, so reaching here means something changed underneath —
      // and charging anyway would put a stranger's ticket money through
      // DriveLife's own Stripe account.
      if (!StripeConfig.mayChargeNatively(
        key: provider.key,
        account: provider.account,
      )) {
        setState(() {
          _busy = false;
          _error =
              'This event cannot be paid for in the app. Open it on the '
              'website to finish your order — your tickets are still held.';
        });
        return;
      }

      // The intent was created on the organiser's connected account, so the
      // SDK has to be pointed at the same account before it can confirm it.
      await StripeConfig.useTicketAccount(
        publishableKey: provider.key,
        connectedAccountId: provider.account,
      );

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          // The organiser sells the ticket; our name on the sheet would be
          // the wrong one on the buyer's statement and in Apple Pay.
          merchantDisplayName: widget.info.event.companyName.isNotEmpty
              ? widget.info.event.companyName
              : widget.info.event.title,
          paymentIntentClientSecret: widget.clientSecret,

          // Already collected on the previous step. Asking again is a second
          // form over the top of the one just filled in.
          billingDetailsCollectionConfiguration:
              const BillingDetailsCollectionConfiguration(
                name: CollectionMode.never,
                email: CollectionMode.never,
                phone: CollectionMode.never,
                address: AddressCollectionMode.never,
              ),
          billingDetails: BillingDetails(
            name: widget.buyerName,
            email: widget.buyerEmail,
            phone: widget.buyerPhone,
          ),

          applePay: Platform.isIOS
              ? PaymentSheetApplePay(
                  merchantCountryCode: _merchantCountry,
                )
              : null,
          googlePay: Platform.isAndroid
              ? PaymentSheetGooglePay(
                  merchantCountryCode: _merchantCountry,
                  // Uppercase: the API sends "gbp"/"usd" because that is what
                  // Stripe's charge takes, but Google Pay wants ISO 4217 as
                  // written — "GBP" — and quietly declines to offer itself
                  // otherwise.
                  currencyCode: widget.info.event.currency.toUpperCase(),
                  testEnv: StripeConfig.isTestMode,
                )
              : null,

          style: ThemeMode.light,
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(primary: TicketTheme.gold),
            shapes: PaymentSheetShape(borderRadius: 12, borderWidth: 1),
          ),
        ),
      );

      await Stripe.instance.presentPaymentSheet();

      // The sheet returning without throwing means the buyer got through it,
      // not that the money has settled. Read the intent back for its real id
      // and status rather than assuming: a delayed method leaves it
      // "processing", and reporting that as "succeeded" marks an order paid
      // before the bank has agreed.
      final intent = await Stripe.instance.retrievePaymentIntent(
        widget.clientSecret,
      );

      final status = _statusName(intent.status);

      if (status != 'succeeded' && status != 'processing') {
        setState(() {
          _busy = false;
          _error = 'Your payment was not completed. Please try again.';
        });
        return;
      }

      await _complete(intent.id, status);
    } on StripeException catch (e) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        // Cancelling is not an error. Saying "payment failed" to somebody who
        // tapped the X reads as their card being declined.
        _error = e.error.code == FailureCode.Canceled
            ? null
            : (e.error.localizedMessage ?? e.error.message);
      });
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong taking the payment. Please try again.';
      });
    }
  }

  /// Stripe's own word for a status, which is what the backend expects.
  ///
  /// The SDK hands back an enum in its own casing; the ticketing side speaks
  /// Stripe's vocabulary — "succeeded", "processing" — because that is what
  /// every other gateway's result is translated into before it gets there.
  String _statusName(PaymentIntentsStatus status) => switch (status) {
    PaymentIntentsStatus.Succeeded => 'succeeded',
    PaymentIntentsStatus.Processing => 'processing',
    PaymentIntentsStatus.RequiresPaymentMethod => 'requires_payment_method',
    PaymentIntentsStatus.RequiresConfirmation => 'requires_confirmation',
    PaymentIntentsStatus.RequiresAction => 'requires_action',
    PaymentIntentsStatus.RequiresCapture => 'requires_capture',
    PaymentIntentsStatus.Canceled => 'canceled',
    PaymentIntentsStatus.Unknown => 'unknown',
  };

  /// Tells the backend what Stripe said, and gets the order back.
  ///
  /// If this fails the money has already moved, so the buyer must not be told
  /// the purchase failed — the order exists as a pending row from the details
  /// step and the organiser can see it. They are told to check their email
  /// instead of being invited to pay twice.
  Future<void> _complete(
    String intentId,
    String status, {
    String provider = 'stripe',
  }) async {
    try {
      final done = await CheckoutApi.saveOrder(
        widget.cartToken,
        widget.info.event.eid,
        paymentIntentId: intentId,
        paymentStatus: status,
        // The order row is labelled with what the buyer actually used, so the
        // organiser's dashboard and exports read correctly.
        form: {
          ...widget.orderForm,
          'payment_method': provider,
          'payment_method_title': provider == 'paypal'
              ? 'PayPal'
              : 'Credit Card',
        },
        provider: provider,
      );

      if (!mounted) return;

      // A delayed payment method has been accepted but not settled. Saying
      // nothing would hand over an order screen that shows no tickets yet and
      // look like something had gone wrong.
      if (status == 'processing') {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Payment processing'),
            content: const Text(
              'Your payment has been accepted but is still clearing with your '
              'bank. Your tickets will be emailed as soon as it completes — '
              'there is nothing else to do, and no need to pay again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (!mounted) return;
      }

      Navigator.of(context).pop(done.orderId);
    } on CheckoutException {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _error =
            'Your payment went through, but we could not confirm the order '
            'here. Check your email for your tickets, and contact the '
            'organiser if nothing arrives. Do not pay again.';
      });
    }
  }

  /// The processor handling the selected method, as a buyer would name it.
  String get _processorName => switch (_method) {
    'paypal' => 'PayPal',
    'square' => 'Square',
    _ => 'Stripe',
  };

  /// Who the buyer is actually paying.
  String get _payee => widget.info.event.companyName.isNotEmpty
      ? widget.info.event.companyName
      : 'the organiser';

  /// One selectable payment method.
  Widget _methodTile({
    required String id,
    required String label,
    required String detail,
    required IconData icon,
  }) {
    final selected = _method == id;

    return Material(
      color: selected
          ? TicketTheme.gold.withValues(alpha: 0.10)
          : const Color(0xFFFCFCFB),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // Not while a payment is in flight: switching method underneath a
        // PayPal approval that is already open would capture the wrong one.
        onTap: _busy ? null : () => setState(() => _method = id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? TicketTheme.gold : TicketTheme.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? TicketTheme.gold : TicketTheme.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: TicketTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: TicketTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? TicketTheme.gold : TicketTheme.line,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Where the organiser is, for the wallets.
  ///
  /// Taken from the event's site rather than the device: Apple Pay and Google
  /// Pay want the merchant's country, and a buyer in Canada at a UK event is
  /// still paying a UK merchant.
  String get _merchantCountry =>
      widget.info.event.site.toLowerCase() == 'us' ? 'US' : 'GB';

  @override
  Widget build(BuildContext context) {
    final currency = widget.info.event.currency;

    return PopScope(
      // Leaving mid-payment is fine; leaving mid-confirmation is not, because
      // the money has moved and the screen is the only thing still trying to
      // record it.
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: TicketTheme.canvas,
        appBar: TicketTheme.appBar(context, 'Payment', step: 3),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            TicketTheme.card(
              title: widget.info.event.title,
              subtitle: widget.info.event.location.isEmpty
                  ? null
                  : widget.info.event.location,
              child: Column(
                children: [
                  // The same breakdown as the previous step, repeated where
                  // the money actually moves. A fee first seen on the card
                  // statement is the complaint this prevents.
                  TicketTheme.summaryRow(
                    'Subtotal',
                    TicketTheme.money(widget.totals.subtotal, currency),
                  ),
                  if (widget.totals.discount > 0)
                    TicketTheme.summaryRow(
                      'Discount',
                      '-${TicketTheme.money(widget.totals.discount, currency)}',
                      accent: true,
                    ),
                  if (widget.totals.feeAmount > 0)
                    TicketTheme.summaryRow(
                      widget.totals.feeName.isEmpty
                          ? 'Booking fee'
                          : widget.totals.feeName,
                      TicketTheme.money(widget.totals.feeAmount, currency),
                    ),
                  if (widget.totals.vat > 0)
                    TicketTheme.summaryRow(
                      'VAT',
                      TicketTheme.money(widget.totals.vat, currency),
                    ),
                  const SizedBox(height: 4),
                  TicketTheme.summaryRow(
                    'Total',
                    TicketTheme.money(widget.amount, currency),
                    bold: true,
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: TicketTheme.line),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 15,
                        color: TicketTheme.muted,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Paid securely to $_payee through '
                          '${_processorName}. '
                          'Payment details never reach DriveLife.',
                          style: const TextStyle(
                            color: TicketTheme.muted,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Only where there is a choice to make. With one method the
            // button already says what it does.
            if (_cardMethod != null && widget.info.hasPaypal) ...[
              const SizedBox(height: 14),
              TicketTheme.card(
                title: 'Pay with',
                child: Column(
                  children: [
                    _methodTile(
                      id: _cardMethod ?? 'stripe',
                      label: 'Card',
                      detail: _cardMethod == 'square'
                          ? 'Entered securely with Square'
                          : 'Apple Pay and Google Pay included',
                      icon: Icons.credit_card,
                    ),
                    const SizedBox(height: 8),
                    _methodTile(
                      id: 'paypal',
                      label: 'PayPal',
                      detail: 'Approve in PayPal, then come back',
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ],
                ),
              ),
            ],

            // A card processor the app cannot present. Without this a buyer
            // with no PayPal account is simply stuck, with no idea the event
            // takes cards at all.
            if (_cardMethod == null &&
                widget.info.cardProcessorNotInApp != null) ...[
              const SizedBox(height: 14),
              TicketTheme.notice(
                'Card payments for this event are handled by '
                '${widget.info.cardProcessorNotInApp}, which the app cannot '
                'show. To pay by card, open this event on the website.',
                isError: false,
              ),
            ],

            // Above everything else: it is a shortcut past the form, and
            // below it the buyer has already started reading the breakdown.
            if (_method == 'square' && _squareWalletReady) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _payWithSquareWallet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TicketTheme.ink,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE8E4DA),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    Platform.isIOS
                        ? Icons.apple
                        : Icons.account_balance_wallet_outlined,
                    size: 20,
                  ),
                  label: Text(
                    'Pay with $_walletName',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'or pay by card below',
                  style: TextStyle(
                    color: TicketTheme.muted,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 14),
              TicketTheme.notice(_error!),
            ],
          ],
        ),
        bottomNavigationBar: TicketTheme.bar(
          label: 'Total',
          value: TicketTheme.money(widget.amount, currency),
          action: _method == 'paypal' ? 'Pay with PayPal' : 'Pay',
          busy: _busy,
          onPressed: _pay,
        ),
      ),
    );
  }

}
