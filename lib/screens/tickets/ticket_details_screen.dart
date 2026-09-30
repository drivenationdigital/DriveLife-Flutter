import 'package:drivelife/api/checkout_api.dart';
import 'package:drivelife/models/checkout_models.dart';
import 'package:drivelife/screens/tickets/ticket_payment_screen.dart';
import 'package:drivelife/screens/tickets/ticket_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

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

  bool _marketing = true;
  bool _terms = false;

  Map<String, String> _errors = {};
  String? _formError;
  bool _submitting = false;

  late final List<CheckoutUnit> _units = cartUnits(
    widget.cart.lines,
    widget.tickets,
  );

  /// Whether any ticket in the cart wants display-board details.
  late final bool _showAttendee =
      _units.any((u) => u.ticket.flags.attendance);

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _attendeeName.dispose();
    _attendeeVehicle.dispose();
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
    'heard_about': '',
    'terms_conditions': '1',
    'attendee_details_required': _showAttendee ? '1' : '0',
    'payment_method': 'stripe',
    // Kept as "Credit Card" so historic orders and new ones read the same in
    // the organiser's dashboard and exports.
    'payment_method_title': 'Credit Card',
    if (_marketing) 'future_updates': '1',
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

      final intent = await CheckoutApi.createIntent(
        token,
        eid,
        widget.info.event.site,
      );

      if (!mounted) return;

      final orderId = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => TicketPaymentScreen(
            info: widget.info,
            cartToken: token,
            clientSecret: intent.clientSecret,
            amount: intent.total > 0 ? intent.total : totals.total,
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          TicketTheme.card(
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
            child: Column(
              children: [
                TicketTheme.checkbox(
                  label: 'Keep me updated about future events',
                  value: _marketing,
                  onChanged: (v) => setState(() => _marketing = v),
                ),
                TicketTheme.checkbox(
                  label: 'I accept the terms and conditions',
                  value: _terms,
                  error: _errors['terms'],
                  onChanged: (v) => setState(() => _terms = v),
                ),
              ],
            ),
          ),

          if (_formError != null) ...[
            const SizedBox(height: 14),
            TicketTheme.notice(_formError!),
          ],
        ],
      ),
      bottomNavigationBar: TicketTheme.bar(
        label: 'Total',
        value: TicketTheme.money(
          widget.cart.totals.total,
          widget.info.event.currency,
        ),
        action: 'Continue',
        busy: _submitting,
        onPressed: _continue,
      ),
    );
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
