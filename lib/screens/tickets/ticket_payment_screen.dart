import 'dart:io' show Platform;

import 'package:drivelife/api/checkout_api.dart';
import 'package:drivelife/config/stripe_config.dart';
import 'package:drivelife/models/checkout_models.dart';
import 'package:drivelife/screens/tickets/ticket_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

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

  /// What Stripe will take, for display only.
  final double amount;

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

  /// The Stripe settings this event's intent was created against.
  ///
  /// Not ours. Ticket money goes to the organiser, on their own connected
  /// account, with their own publishable key — which is why this cannot reuse
  /// the key the app is initialised with for the store.
  ///
  /// `providers` is preferred but optional: a backend predating the
  /// multi-provider work omits it and sends only the top-level `stripe`
  /// object, so falling back to that is what keeps those events working.
  ({String key, String? account}) get _stripe {
    for (final provider in widget.info.providers) {
      if (provider.id != 'stripe') continue;

      final account = '${provider.raw['account'] ?? ''}'.trim();

      return (
        key: '${provider.raw['publishable_key'] ?? ''}',
        account: account.isEmpty ? null : account,
      );
    }

    return (key: widget.info.stripeKey, account: widget.info.stripeAccount);
  }

  @override
  void dispose() {
    // The app's own key is restored whatever happened here, so the store
    // checkout is never left pointing at an organiser's account.
    StripeConfig.restoreAppAccount();
    super.dispose();
  }

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final provider = _stripe;

      // The intent was created on the organiser's connected account, so the
      // SDK has to be pointed at the same account before it can confirm it.
      // Confirming with the platform's own key fails with "No such
      // payment_intent", which reads as a dead card rather than a
      // misconfiguration.
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
                  currencyCode: widget.info.event.currency,
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

      // The sheet returning without throwing is Stripe's confirmation. The
      // backend re-checks the intent against the charge it recorded, so this
      // is a report rather than a claim.
      await _complete();
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

  /// Tells the backend the payment succeeded, and gets the order back.
  ///
  /// If this fails the money has already moved, so the buyer must not be told
  /// the purchase failed — the order exists as a pending row from the details
  /// step and the organiser can see it. They are told to check their email
  /// instead of being invited to pay twice.
  Future<void> _complete() async {
    try {
      final done = await CheckoutApi.saveOrder(
        widget.cartToken,
        widget.info.event.eid,
        paymentIntentId: widget.clientSecret.split('_secret_').first,
        paymentStatus: 'succeeded',
        form: widget.orderForm,
      );

      if (!mounted) return;
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
                  _row('Total', TicketTheme.money(widget.amount, currency),
                      bold: true),
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
                          'Paid securely to '
                          '${widget.info.event.companyName.isNotEmpty ? widget.info.event.companyName : 'the organiser'}'
                          ' through Stripe. Card details never reach DriveLife.',
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

            if (_error != null) ...[
              const SizedBox(height: 14),
              TicketTheme.notice(_error!),
            ],
          ],
        ),
        bottomNavigationBar: TicketTheme.bar(
          label: 'Total',
          value: TicketTheme.money(widget.amount, currency),
          action: 'Pay',
          busy: _busy,
          onPressed: _pay,
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: TicketTheme.muted, fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            color: TicketTheme.ink,
            fontSize: bold ? 18 : 14,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
