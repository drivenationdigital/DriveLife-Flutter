import 'dart:ui' show FontFeature;
import 'dart:async';
import 'package:drivelife/api/checkout_api.dart';
import 'package:drivelife/config/stripe_config.dart';
import 'package:drivelife/models/checkout_models.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/tickets/ticket_payment_screen.dart';
import 'package:drivelife/screens/tickets/ticket_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

/// Step two: who the tickets are for.
///
/// The buyer's own details, then whatever each individual ticket asks about
/// the person it admits — names, vehicles, a photo. Those questions come from
/// the ticket's flags, so an event that asks nothing shows nothing beyond the
/// billing block.
///
/// Everything is written to the cart on Continue rather than as it is typed.
/// A field saved on every keystroke is a request per character over mobile
/// data, and a half-saved form if the buyer walks away mid-word.
class TicketDetailsScreen extends StatefulWidget {
  final CheckoutInfo info;
  final CheckoutCart cart;
  final List<CheckoutTicket> tickets;

  const TicketDetailsScreen({
    super.key,
    required this.info,
    required this.cart,
    required this.tickets,
  });

  @override
  State<TicketDetailsScreen> createState() => _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends State<TicketDetailsScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  final _attendeeName = TextEditingController();
  final _attendeeVehicle = TextEditingController();
  bool _attendeeDisplay = false;

  /// Per-unit answers, keyed '<pid>:<index>:<field>'.
  final Map<String, String> _unitValues = {};

  /// Controllers for the text-ish per-unit fields, keyed the same way.
  final Map<String, TextEditingController> _unitControllers = {};

  /// The organiser's own mailing list.
  bool _marketingOrganiser = true;

  /// The CarEvents.com newsletter. A separate consent, because it is a
  /// different sender — bundling them is what makes an opt-in worthless.
  bool _marketingCarevents = true;

  bool _terms = false;

  final _heardAbout = TextEditingController();
  final _discount = TextEditingController();

  /// The cart as it now stands. Starts as the one handed over and changes
  /// when a ticket is removed, so the summary and the units follow.
  late Map<String, dynamic> _lines = Map<String, dynamic>.from(
    widget.cart.lines,
  );

  late CartTotals _totals = widget.cart.totals;

  CheckoutCoupon? _coupon;
  bool _discountBusy = false;
  bool _removing = false;

  Map<String, String> _errors = {};
  String? _formError;
  bool _submitting = false;

  List<CheckoutUnit> get _units => cartUnits(_lines, widget.tickets);

  /// Whether any ticket in the cart wants display-board details.
  bool get _showAttendee => _units.any((u) => u.ticket.flags.attendance);

  @override
  void initState() {
    super.initState();
    _prefillFromProfile();
  }

  /// Starts the form with what we already know about the buyer.
  ///
  /// Everything stays editable — somebody buying for a friend needs to change
  /// the name, and the ticket email is often not the account email. This only
  /// saves the common case the typing.
  ///
  /// Read once in initState rather than watched: these are starting values,
  /// and a profile refresh mid-form must not overwrite what is being typed.
  void _prefillFromProfile() {
    final user = context.read<UserProvider>().user;
    if (user == null) return;

    _firstName.text = user.firstName.trim();
    _lastName.text = user.lastName.trim();
    _email.text = user.email.trim();
    _phone.text = (user.billingInfo?.phone ?? '').trim();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _attendeeName.dispose();
    _attendeeVehicle.dispose();
    _heardAbout.dispose();
    _discount.dispose();
    for (final controller in _unitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key) =>
      _unitControllers.putIfAbsent(key, TextEditingController.new);

  static final RegExp _emailPattern = RegExp(r'^\S+@\S+\.\S+$');

  /// Everything that has to be filled in, checked in one pass.
  ///
  /// The same rules as the web checkout, including its one exception:
  /// checkboxes are never required, because "no" is an answer.
  Map<String, String> _validate() {
    final errors = <String, String>{};

    if (_firstName.text.trim().isEmpty) errors['first'] = 'Required';
    if (_lastName.text.trim().isEmpty) errors['last'] = 'Required';
    if (_phone.text.trim().isEmpty) errors['phone'] = 'Required';
    if (!_emailPattern.hasMatch(_email.text.trim())) {
      errors['email'] = 'Enter a valid email address';
    }

    for (final unit in _units) {
      for (final spec in unitFieldSpecs(unit.ticket)) {
        if (spec.kind == UnitFieldKind.checkbox) continue;

        final key = '${unit.key}:${spec.field}';

        if ((_unitValues[key] ?? '').trim().isEmpty) {
          errors[key] = spec.kind == UnitFieldKind.photo
              ? 'Please add a photo of your vehicle'
              : 'Required';
        }
      }
    }

    if (_showAttendee) {
      if (_attendeeName.text.trim().isEmpty) errors['att_name'] = 'Required';
      if (_attendeeVehicle.text.trim().isEmpty) {
        errors['att_vehicle'] = 'Required';
      }
    }

    if (!_terms) {
      errors['terms'] = 'Please accept the terms and conditions to continue.';
    }

    return errors;
  }

  Map<String, String> _orderForm() => {
    'billing_first_name': _firstName.text.trim(),
    'billing_last_name': _lastName.text.trim(),
    'billing_email': _email.text.trim(),
    'billing_phone': _phone.text.trim(),
    'cc_source': '',
    'heard_about': _heardAbout.text.trim(),
    'terms_conditions': '1',
    'attendee_details_required': _showAttendee ? '1' : '0',
    'payment_method': 'stripe',
    // Kept as "Credit Card" so historic orders and new ones read the same in
    // the organiser's dashboard and exports.
    'payment_method_title': 'Credit Card',
    'marketing_organiser': _marketingOrganiser ? '1' : '0',
    'marketing_carevents': _marketingCarevents ? '1' : '0',
    // What a backend from before the two consents reads. It maps to the same
    // order column as marketing_organiser.
    if (_marketingOrganiser) 'future_updates': '1',
    if (_showAttendee) ...{
      'attendee_display': _attendeeDisplay ? 'checked' : '',
      'attendee_name': _attendeeName.text.trim(),
      'attendee_vehicle': _attendeeVehicle.text.trim(),
    },
  };

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();

    final errors = _validate();

    setState(() {
      _errors = errors;
      _formError = errors.isEmpty
          ? null
          : 'Please complete the highlighted fields.';
    });

    if (errors.isNotEmpty) return;

    setState(() => _submitting = true);

    final token = widget.cart.token;
    final eid = widget.info.event.eid;

    try {
      await CheckoutApi.saveBilling(token, {
        'billing_first_name': _firstName.text.trim(),
        'billing_last_name': _lastName.text.trim(),
        'billing_email': _email.text.trim(),
        'billing_phone': _phone.text.trim(),
      });

      if (_showAttendee) {
        await CheckoutApi.saveAttendee(token, {
          'attendee_display': _attendeeDisplay ? 'checked' : '',
          'attendee_name': _attendeeName.text.trim(),
          'attendee_vehicle': _attendeeVehicle.text.trim(),
        });
      }

      for (final unit in _units) {
        for (final spec in unitFieldSpecs(unit.ticket)) {
          final key = '${unit.key}:${spec.field}';
          final value = _unitValues[key] ?? '';

          // A photo is already in the cart: it was written when it uploaded,
          // because losing it to a failed Continue would mean picking and
          // uploading it again.
          if (spec.kind == UnitFieldKind.photo) continue;

          await CheckoutApi.updateMeta(
            token,
            unit.pid,
            spec.field,
            value,
            unit.index,
          );
        }
      }

      final form = _orderForm();

      // A pending order row before any money moves, so the PaymentIntent and
      // the order can reference each other. The classic checkout does the
      // same; skipping it leaves a paid intent with no order behind it.
      await CheckoutApi.saveOrder(
        token,
        eid,
        paymentStatus: 'pending',
        form: form,
      );

      final totals = await CheckoutApi.totals(token);

      // Free after discounts: there is nothing for Stripe to do.
      if (totals.total <= 0) {
        final done = await CheckoutApi.saveOrder(
          token,
          eid,
          paymentIntentId: 'free',
          paymentStatus: 'succeeded',
          form: form,
        );

        if (!mounted) return;
        Navigator.of(context).pop(done.orderId);
        return;
      }

      // Only where a card can actually be taken. Minting an intent for a
      // PayPal-only event would leave an unconfirmed PaymentIntent behind on
      // every attempt, and the organiser has no Stripe to see it on.
      final stripe = widget.info.stripe;

      final canUseStripe =
          widget.info.hasStripe &&
          StripeConfig.mayChargeNatively(
            key: stripe.key,
            account: stripe.account,
          );

      final intent = canUseStripe
          ? await CheckoutApi.createIntent(token, eid, widget.info.event.site)
          : null;

      if (!mounted) return;

      final orderId = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => TicketPaymentScreen(
            info: widget.info,
            cartToken: token,
            clientSecret: intent?.clientSecret ?? '',
            // The server's totals as refreshed a moment ago, not the ones the
            // ticket step produced: saving the buyer's email is when a
            // per-person discount limit is finally checked, so this is the
            // first point the figures are settled.
            totals: totals,
            // What Stripe will actually take. It comes from the intent rather
            // than the totals so the amount on screen is the amount being
            // charged, even if the two ever disagree.
            amount: (intent?.total ?? 0) > 0 ? intent!.total : totals.total,
            orderForm: form,
            buyerName:
                '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim(),
            buyerEmail: _email.text.trim(),
            buyerPhone: _phone.text.trim(),
          ),
        ),
      );

      if (!mounted || orderId == null) return;

      // Paid. Carry the order back out through the ticket list.
      Navigator.of(context).pop(orderId);
    } on CheckoutException catch (e) {
      if (!mounted) return;

      // A per-buyer coupon limit is only checked once the email is known, so a
      // code accepted on step one can first fail here. The server names the
      // code and the reason; repeating that is more use than "invalid coupon".
      final invalid = e.extra['invalid_coupons'];

      setState(() {
        _formError = invalid is Map && invalid.isNotEmpty
            ? invalid.entries
                      .map((entry) => '${entry.key}: ${entry.value}')
                      .join(' · ') +
                  ' — remove the code to continue.'
            : e.message;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickPhoto(String key) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Plenty for a judging photo, and it keeps the upload quick on mobile
        // data — the field is a record of the car, not a gallery submission.
        maxWidth: 2000,
        imageQuality: 85,
      );

      if (picked == null) return;

      setState(() {
        _unitValues[key] = '';
        _errors = {..._errors}..remove(key);
        _uploading.add(key);
      });

      final parts = key.split(':');
      final url = await CheckoutApi.uploadVehiclePhoto(
        widget.info.event.eid,
        picked.path,
      );

      // Written to the cart as soon as it lands. A photo that only existed in
      // this screen's state would have to be picked and uploaded again after
      // any failure further down.
      await CheckoutApi.updateMeta(
        widget.cart.token,
        parts[0],
        'vehicle_photo',
        url,
        int.tryParse(parts[1]) ?? 0,
      );

      if (!mounted) return;
      setState(() {
        _unitValues[key] = url;
        _uploading.remove(key);
      });
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading.remove(key);
        _errors = {..._errors, key: e.message};
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading.remove(key);
        _errors = {..._errors, key: "That photo couldn't be uploaded."};
      });
    }
  }

  final Set<String> _uploading = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TicketTheme.canvas,
      appBar: TicketTheme.appBar(context, 'Your details', step: 2),
      body: Stack(
        children: [
          ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          // How long the stock is held. The server reserved it when the cart
          // was built, and a buyer filling in four tickets' worth of details
          // deserves to know there is a clock rather than meet it as a
          // failure at the end.
          _ReservationTimer(expiresAt: widget.cart.reservedUntil),
          const SizedBox(height: 14),

          TicketTheme.card(
            step: 1,
            title: 'Your details',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TicketTheme.field(
                        label: 'First name',
                        controller: _firstName,
                        error: _errors['first'],
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TicketTheme.field(
                        label: 'Last name',
                        controller: _lastName,
                        error: _errors['last'],
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TicketTheme.field(
                  label: 'Email',
                  controller: _email,
                  error: _errors['email'],
                  keyboardType: TextInputType.emailAddress,
                  hint: 'Tickets are sent here',
                ),
                const SizedBox(height: 14),
                TicketTheme.field(
                  label: 'Phone',
                  controller: _phone,
                  error: _errors['phone'],
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),

          for (final unit in _units) ..._unitCard(unit),

          const SizedBox(height: 14),
          _buildTicketList(),

          const SizedBox(height: 14),
          _buildSummary(),

          if (_showAttendee) ...[
            const SizedBox(height: 14),
            TicketTheme.card(
              title: 'Display details',
              subtitle: 'Shown on the event listing and display boards.',
              child: Column(
                children: [
                  TicketTheme.field(
                    label: 'Your name',
                    controller: _attendeeName,
                    error: _errors['att_name'],
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 14),
                  TicketTheme.field(
                    label: 'Vehicle',
                    controller: _attendeeVehicle,
                    error: _errors['att_vehicle'],
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 4),
                  TicketTheme.checkbox(
                    label: 'Show me on the public attendee list',
                    value: _attendeeDisplay,
                    onChanged: (v) => setState(() => _attendeeDisplay = v),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          TicketTheme.card(
            step: _showAttendee ? 5 : 4,
            title: 'Before you go',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TicketTheme.field(
                  label: 'How did you hear about this event? (Optional)',
                  controller: _heardAbout,
                ),
                const SizedBox(height: 10),
                TicketTheme.checkbox(
                  label:
                      'Keep me updated about future events from this event '
                      'organiser',
                  value: _marketingOrganiser,
                  onChanged: (v) => setState(() => _marketingOrganiser = v),
                ),
                TicketTheme.checkbox(
                  label:
                      "I'd like to hear about other future events from "
                      'CarEvents.com',
                  value: _marketingCarevents,
                  onChanged: (v) => setState(() => _marketingCarevents = v),
                ),
                TicketTheme.checkbox(
                  label: 'I accept the terms & conditions',
                  value: _terms,
                  error: _errors['terms'],
                  onChanged: (v) => setState(() => _terms = v),
                  // Readable, not just acceptable. Asking somebody to agree
                  // to something they have no way of opening is the part of
                  // a checkout that quietly costs it trust.
                  richLabel: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: TicketTheme.ink,
                        fontSize: 14,
                        height: 1.35,
                      ),
                      children: [
                        const TextSpan(text: 'I accept the '),
                        TextSpan(
                          text: 'terms & conditions',
                          style: const TextStyle(
                            color: TicketTheme.gold,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = _showTerms,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_formError != null) ...[
            const SizedBox(height: 14),
            TicketTheme.notice(_formError!),
          ],

          TicketTheme.poweredBy(widget.info.event.companyName),
        ],
      ),

          // Over everything, because both of these reserve stock or open a
          // payment and a second tap during one is how a buyer ends up with
          // two carts.
          if (_submitting) TicketTheme.overlay('Preparing your order...'),
          if (_removing) TicketTheme.overlay('Updating your order...'),
        ],
      ),
      bottomNavigationBar: TicketTheme.bar(
        label: 'Total',
        value: TicketTheme.money(
          widget.cart.totals.total,
          widget.info.event.currency,
        ),
        action: 'Continue to Payment',
        busy: _submitting,
        // Terms gate the button rather than failing validation afterwards.
        // Tapping Continue and being told to go back and tick a box is a
        // worse way to learn it than the button simply waiting.
        enabled: _terms,
        onPressed: _continue,
      ),
    );
  }

  /// Opens the terms the buyer is being asked to accept.
  ///
  /// The event's own first, then the site's. Both arrive as HTML from the
  /// organiser's editor, so they are rendered rather than flattened — a wall
  /// of unformatted text is not meaningfully readable either.
  Future<void> _showTerms() async {
    final event = widget.info.event.termsHtml.trim();
    final site = widget.info.event.siteTermsHtml.trim();

    if (event.isEmpty && site.isEmpty) {
      setState(
        () => _formError = 'No terms have been published for this event.',
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: TicketTheme.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Terms & conditions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    color: TicketTheme.muted,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: TicketTheme.line),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  if (event.isNotEmpty) Html(data: event),
                  if (event.isNotEmpty && site.isNotEmpty)
                    const Divider(height: 28, color: TicketTheme.line),
                  if (site.isNotEmpty) Html(data: site),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The tickets in the cart, each removable on its own.
  ///
  /// Per admission, not per line: "two of these three" is the edit a buyer
  /// actually wants to make, and the server takes units for the same reason.
  Widget _buildTicketList() {
    final units = _units;
    final currency = widget.info.event.currency;
    final multiplier = widget.info.vatMultiplier;

    return TicketTheme.card(
      step: 2,
      title: 'Your tickets',
      ruledHeader: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          for (var i = 0; i < units.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: BoxDecoration(
                border: Border.all(color: TicketTheme.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          units[i].ticket.name,
                          style: const TextStyle(
                            color: TicketTheme.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          TicketTheme.money(
                            units[i].ticket.price * multiplier,
                            currency,
                          ),
                          style: const TextStyle(
                            color: TicketTheme.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _removing ? null : () => _removeUnit(units[i]),
                    icon: const Icon(Icons.close, size: 18),
                    color: TicketTheme.muted,
                    tooltip: 'Remove this ticket',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Takes one admission out of the cart.
  ///
  /// An empty cart has nothing left to pay for, so that case goes back to the
  /// ticket list rather than leaving an order of nothing on screen.
  Future<void> _removeUnit(CheckoutUnit unit) async {
    setState(() {
      _removing = true;
      _formError = null;
    });

    try {
      final result = await CheckoutApi.removeUnit(
        widget.cart.token,
        unit.pid,
        unit.index,
      );

      if (!mounted) return;

      if (result.isEmpty) {
        Navigator.of(context).pop();
        return;
      }

      final totals = await CheckoutApi.totals(widget.cart.token);
      if (!mounted) return;

      setState(() {
        _lines = result.lines;
        _totals = totals;
        _removing = false;
      });
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() {
        _removing = false;
        _formError = e.message;
      });
    }
  }

  /// What the buyer is about to be charged, itemised.
  ///
  /// Every line the server put in the cart, named as the server named it. A
  /// booking fee that only appears on the card statement is the complaint
  /// this exists to prevent, and the organiser's own wording for it is what
  /// they will recognise.
  Widget _buildSummary() {
    final totals = _totals;
    final currency = widget.info.event.currency;
    final multiplier = widget.info.vatMultiplier;

    String money(double amount) => TicketTheme.money(amount, currency);

    // One row per cart line, at the price the ticket list showed.
    final lines = <Widget>[];

    _lines.forEach((pid, line) {
      final ticket = widget.tickets.where((t) => t.pid == pid).firstOrNull;
      if (ticket == null || line is! Map) return;

      final qty = int.tryParse('${line['qty'] ?? 0}') ?? 0;
      if (qty <= 0) return;

      lines.add(
        TicketTheme.summaryRow(
          '${ticket.name}  ×$qty',
          money(ticket.price * multiplier * qty),
        ),
      );
    });

    return TicketTheme.card(
      step: 3,
      title: 'Order summary',
      child: Column(
        children: [
          ...lines,
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Divider(height: 1, color: TicketTheme.line),
            const SizedBox(height: 6),
          ],
          TicketTheme.summaryRow('Subtotal', money(totals.subtotal)),
          if (totals.discount > 0)
            TicketTheme.summaryRow(
              'Discount',
              '-${money(totals.discount)}',
              accent: true,
            ),
          if (totals.feeAmount > 0)
            TicketTheme.summaryRow(
              totals.feeName.isEmpty ? 'Booking fee' : totals.feeName,
              money(totals.feeAmount),
            ),
          if (totals.vat > 0) TicketTheme.summaryRow('VAT', money(totals.vat)),
          const SizedBox(height: 4),
          TicketTheme.summaryRow('Total', money(totals.total), bold: true),

          const SizedBox(height: 12),
          _buildDiscountField(),
        ],
      ),
    );
  }

  /// A discount code, applied against the cart that already exists.
  ///
  /// Here rather than only on the ticket list because this is where the
  /// total is being read — somebody who remembers their code at the last
  /// moment should not have to go back two screens for it.
  Widget _buildDiscountField() {
    final applied = _coupon;

    if (applied != null) {
      return Row(
        children: [
          const Icon(
            Icons.local_offer_outlined,
            size: 16,
            color: TicketTheme.gold,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${applied.code} applied',
              style: const TextStyle(
                color: TicketTheme.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _discount,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _applyDiscount(),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Discount code',
              hintStyle: const TextStyle(
                color: TicketTheme.muted,
                fontSize: 14,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 13,
              ),
              filled: true,
              fillColor: const Color(0xFFFCFCFB),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: TicketTheme.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: TicketTheme.gold,
                  width: 1.6,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 46,
          child: ElevatedButton(
            onPressed: _discountBusy ? null : _applyDiscount,
            style: ElevatedButton.styleFrom(
              backgroundColor: TicketTheme.gold,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE8E4DA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _discountBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Apply',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _applyDiscount() async {
    final code = _discount.text.trim();
    if (code.isEmpty || _discountBusy) return;

    setState(() {
      _discountBusy = true;
      _formError = null;
    });

    try {
      final coupon = await CheckoutApi.checkCoupon(
        widget.info.event.eid,
        widget.cart.token,
        code,
      );

      // Validating is not applying: the code only reaches the cart during
      // add-to-basket, so the totals are read back rather than assumed.
      final totals = await CheckoutApi.totals(widget.cart.token);

      if (!mounted) return;

      setState(() {
        _discountBusy = false;
        _coupon = coupon;
        _totals = totals;
        if (coupon == null) {
          _formError = "That code isn't valid for this event.";
        }
      });
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() {
        _discountBusy = false;
        _formError = e.message;
      });
    }
  }

  List<Widget> _unitCard(CheckoutUnit unit) {
    final specs = unitFieldSpecs(unit.ticket);
    if (specs.isEmpty) return const [];

    return [
      const SizedBox(height: 14),
      TicketTheme.card(
        title: unit.ticket.name,
        // Only worth numbering when there is more than one of this ticket.
        subtitle: _units.where((u) => u.pid == unit.pid).length > 1
            ? 'Ticket ${unit.index + 1}'
            : null,
        child: Column(
          children: [
            for (var i = 0; i < specs.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _unitField(unit, specs[i]),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _unitField(CheckoutUnit unit, UnitFieldSpec spec) {
    final key = '${unit.key}:${spec.field}';

    return switch (spec.kind) {
      UnitFieldKind.checkbox => TicketTheme.checkbox(
        label: spec.label,
        value: _unitValues[key] == 'checked',
        onChanged: (v) =>
            setState(() => _unitValues[key] = v ? 'checked' : ''),
      ),
      UnitFieldKind.photo => TicketTheme.photoField(
        label: spec.label,
        url: _unitValues[key] ?? '',
        busy: _uploading.contains(key),
        error: _errors[key],
        onPick: () => _pickPhoto(key),
      ),
      _ => TicketTheme.field(
        label: spec.label,
        controller: _controllerFor(key),
        error: _errors[key],
        keyboardType: spec.kind == UnitFieldKind.phone
            ? TextInputType.phone
            : TextInputType.text,
        textCapitalization: spec.field == 'reg'
            ? TextCapitalization.characters
            : TextCapitalization.words,
        inputFormatters: spec.field == 'reg'
            ? [UpperCaseTextFormatter()]
            : null,
        onChanged: (value) => _unitValues[key] = value,
      ),
    };
  }
}

/// Registrations are written in capitals everywhere else in the app.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => TextEditingValue(
    text: newValue.text.toUpperCase(),
    selection: newValue.selection,
  );
}

/// How long the stock is held, counting down.
///
/// The server reserves tickets for an hour when the cart is built. Somebody
/// filling in details for four admissions has no way of knowing that unless
/// it is on screen, and meeting the limit as a failure at the end is the
/// worst possible way to learn it.
///
/// Stops at zero rather than going negative. Expiry is the server's to
/// enforce — it will refuse the order — and a screen counting backwards past
/// nothing says less than one that simply says the time is up.
class _ReservationTimer extends StatefulWidget {
  final DateTime? expiresAt;

  const _ReservationTimer({required this.expiresAt});

  @override
  State<_ReservationTimer> createState() => _ReservationTimerState();
}

class _ReservationTimerState extends State<_ReservationTimer> {
  Timer? _ticker;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _recalculate();

    // Once a second: the display is in minutes and seconds, and anything
    // finer would be a rebuild nobody can see.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _recalculate());
  }

  void _recalculate() {
    final expires = widget.expiresAt;
    if (expires == null) return;

    final left = expires.difference(DateTime.now());
    final clamped = left.isNegative ? Duration.zero : left;

    if (clamped.inSeconds == _left.inSeconds) return;
    if (mounted) setState(() => _left = clamped);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.expiresAt == null) return const SizedBox.shrink();

    final expired = _left == Duration.zero;
    final minutes = _left.inMinutes.toString().padLeft(2, '0');
    final seconds = (_left.inSeconds % 60).toString().padLeft(2, '0');

    // Red only in the last five minutes. A clock that is urgent from the
    // first second is just decoration by the time it matters.
    final urgent = expired || _left.inMinutes < 5;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TicketTheme.line),
      ),
      child: Row(
        children: [
          Icon(
            Icons.timer_outlined,
            size: 16,
            color: urgent ? TicketTheme.danger : TicketTheme.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              expired
                  ? 'Your reserved tickets have expired'
                  : 'Tickets reserved for',
              style: TextStyle(
                color: urgent ? TicketTheme.danger : TicketTheme.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!expired)
            Text(
              '$minutes:$seconds',
              style: TextStyle(
                color: urgent ? TicketTheme.danger : TicketTheme.ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}
