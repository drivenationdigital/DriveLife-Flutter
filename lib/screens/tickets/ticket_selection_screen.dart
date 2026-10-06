import 'dart:async';

import 'package:drivelife/api/checkout_api.dart';
import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/config/feature_flags.dart';
import 'package:drivelife/config/stripe_config.dart';
import 'package:drivelife/models/checkout_models.dart';
import 'package:drivelife/screens/events/order_ticket_view.dart';
import 'package:drivelife/screens/tickets/ticket_details_screen.dart';
import 'package:drivelife/screens/tickets/ticket_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Picking tickets for an event.
///
/// Step one of the checkout. Nothing is held while this screen is open — a
/// cart is only opened when it is needed, and stock is only reserved on
/// Continue. Browsing the list costs two reads and commits to nothing, which
/// is what lets someone open it out of curiosity without quietly taking a
/// ticket off sale.
class TicketSelectionScreen extends StatefulWidget {
  /// The event's encrypted id — `make_crypt($event_id, 'e')`, the same value
  /// the web checkout takes in its path.
  final String eventEid;

  /// Shown in the header until the real event arrives, so the screen opens
  /// with the name of the thing that was tapped rather than a spinner.
  final String? eventTitle;

  /// A discount code to try on arrival, from a shared link.
  final String? coupon;

  /// The event's cover photo, from the screen that opened this one.
  ///
  /// A fallback, not the first choice: an organiser who has set a checkout
  /// logo gets that instead. It exists so the header still shows the event
  /// when they have not, and so it shows it immediately — the cover is
  /// already loaded on the page the buyer tapped through from, where the
  /// logo only arrives with the checkout info.
  final String? eventImage;

  /// Which blog the event lives on: 'uk' or 'us'.
  ///
  /// Required rather than defaulted. A post id is only unique within a blog
  /// and the encrypted id carries no blog, so the wrong value here does not
  /// fail — it sells a different event. Making the caller state it means a
  /// new entry point cannot forget it by accident.
  final String site;

  const TicketSelectionScreen({
    super.key,
    required this.eventEid,
    required this.site,
    this.eventTitle,
    this.coupon,
    this.eventImage,
  });

  @override
  State<TicketSelectionScreen> createState() => _TicketSelectionScreenState();
}

class _TicketSelectionScreenState extends State<TicketSelectionScreen> {
  static const Color _ink = Color(0xFF14140F);
  static const Color _muted = Color(0xFF7A7A72);
  static const Color _gold = Color(0xFFC4A062);
  static const Color _line = Color(0xFFE8E6E1);

  CheckoutInfo? _info;
  List<CheckoutTicket> _tickets = const [];

  /// Chosen quantity per ticket, keyed by the encrypted ticket id.
  final Map<String, int> _quantities = {};

  CheckoutCoupon? _coupon;
  String _secretCode = '';

  /// Opened lazily — see [_ensureCart].
  String? _cartToken;

  bool _loading = true;
  bool _committing = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    // Before the first request, not after: the very first call is `info`,
    // and asking the wrong blog for an event returns a different event
    // rather than an error.
    CheckoutApi.useSite(widget.site);
    _load();
  }

  @override
  void dispose() {
    // Nothing has been reserved unless Continue ran, but a cart opened for a
    // secret code should not be left lying around either.
    final token = _cartToken;
    if (token != null && !_committing) CheckoutApi.clearCart(token);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Together: the ticket list does not depend on the event, and asking
      // one after the other doubles the wait on a cold open.
      final results = await Future.wait([
        CheckoutApi.info(widget.eventEid),
        CheckoutApi.tickets(widget.eventEid, coupon: widget.coupon ?? ''),
      ]);

      if (!mounted) return;

      setState(() {
        _info = results[0] as CheckoutInfo;
        _tickets = results[1] as List<CheckoutTicket>;
        _loading = false;
      });
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Refetches the list, which changes with a coupon or a secret code.
  Future<void> _reloadTickets() async {
    try {
      final tickets = await CheckoutApi.tickets(
        widget.eventEid,
        cartToken: _cartToken ?? '',
        code: _secretCode,
        coupon: _coupon?.code ?? '',
      );

      if (!mounted) return;

      setState(() {
        _tickets = tickets;

        // A ticket that has gone away takes its quantity with it, or Continue
        // would send a pid the server no longer sells.
        final live = {for (final t in tickets) t.pid};
        _quantities.removeWhere((pid, _) => !live.contains(pid));
      });
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() => _notice = e.message);
    }
  }

  /// A cart token, opening one if this is the first thing that needs it.
  ///
  /// Deliberately not done on load. An empty cart holds no stock, but one per
  /// curious visitor is still a row per visit, and the token is only actually
  /// needed by a secret code or by Continue.
  Future<String> _ensureCart() async {
    final existing = _cartToken;
    if (existing != null && existing.isNotEmpty) return existing;

    final token = await CheckoutApi.createCart(widget.eventEid);

    if (token.isEmpty) {
      throw const CheckoutException(
        "We couldn't start a checkout session. Please try again.",
      );
    }

    _cartToken = token;
    return token;
  }

  int get _totalSelected => _quantities.values.fold(0, (sum, qty) => sum + qty);

  /// The event's cap on items per order, or null where there is none.
  int? get _cartLimit {
    final limit = _info?.event.maxItemsPerOrder ?? 0;
    return limit > 0 ? limit : null;
  }

  /// What the buyer will pay, as far as this screen can tell.
  ///
  /// A preview. The server prices the cart itself on Continue and that figure
  /// replaces this one — nothing is ever charged from a total computed here.
  /// It exists so the steppers feel immediate.
  double get _subtotal {
    final multiplier = _info?.vatMultiplier ?? 1;
    final coupon = _coupon;

    var sum = 0.0;
    var eligible = 0.0;

    for (final ticket in _tickets) {
      if (ticket.isSection) continue;

      final qty = _quantities[ticket.pid] ?? 0;
      if (qty == 0) continue;

      var price = ticket.price * multiplier;
      final applies = coupon != null && coupon.appliesTo(ticket.id);

      if (applies && !coupon.isFixed) price = coupon.priceAfter(price);

      sum += price * qty;
      if (applies) eligible += price * qty;
    }

    // A fixed code comes off the order once, capped at what it is allowed to
    // discount — not off each ticket, which would multiply it by the quantity.
    if (coupon != null && coupon.isFixed && eligible > 0) {
      final off = coupon.discountAmount < eligible
          ? coupon.discountAmount
          : eligible;
      sum = sum - off;
    }

    return sum < 0 ? 0 : sum;
  }

  String _money(double amount) {
    final currency = _info?.event.currency ?? 'GBP';
    final symbol = switch (currency.toUpperCase()) {
      'USD' => r'$',
      'EUR' => '€',
      _ => '£',
    };

    return NumberFormat.currency(
      symbol: symbol,
      decimalDigits: 2,
    ).format(amount);
  }

  /// The most of this ticket the buyer may still add.
  ///
  /// Two ceilings: the ticket's own limit and what is left of the event's cap
  /// on the whole order. The classic checkout clamps by both, and a stepper
  /// that lets someone pass the order cap only fails at add-to-basket.
  int _maxFor(CheckoutTicket ticket) {
    final own = ticket.maxQuantity;
    final limit = _cartLimit;

    if (limit == null) return own;

    final remaining = limit - (_totalSelected - (_quantities[ticket.pid] ?? 0));
    return own < remaining ? own : remaining;
  }

  void _setQuantity(CheckoutTicket ticket, int next) {
    setState(() {
      _notice = null;
      if (next <= 0) {
        _quantities.remove(ticket.pid);
      } else {
        _quantities[ticket.pid] = next;
      }
    });
  }

  Future<void> _applyCoupon(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;

    try {
      final cart = await _ensureCart();
      final coupon = await CheckoutApi.checkCoupon(
        widget.eventEid,
        cart,
        trimmed,
      );

      if (!mounted) return;

      if (coupon == null) {
        setState(() => _notice = "That code isn't valid for this event.");
        return;
      }

      setState(() {
        _coupon = coupon;
        _notice = null;
      });

      await _reloadTickets();
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() => _notice = e.message);
    }
  }

  Future<void> _applySecret(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;

    try {
      final cart = await _ensureCart();
      await CheckoutApi.checkSecretCode(widget.eventEid, cart, trimmed);

      if (!mounted) return;

      setState(() {
        _secretCode = trimmed;
        _notice = null;
      });

      await _reloadTickets();
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() => _notice = e.message);
    }
  }

  /// Builds the cart, holds the stock and prices it.
  ///
  /// The order matters and mirrors the web checkout exactly: add, reserve,
  /// then total. A failure at reserve rolls the cart back rather than leaving
  /// a half-built one behind — otherwise the next attempt stacks on top of it
  /// and the server's total, and the Stripe amount with it, includes units
  /// the screen never showed.
  Future<CheckoutCart?> _commit() async {
    final items = <({String pid, int qty})>[
      for (final ticket in _tickets)
        if (!ticket.isSection && (_quantities[ticket.pid] ?? 0) > 0)
          (pid: ticket.pid, qty: _quantities[ticket.pid]!),
    ];

    if (items.isEmpty) return null;

    String? cart;

    try {
      cart = await _ensureCart();

      final added = await CheckoutApi.addToBasket(
        widget.eventEid,
        cart,
        items,
        coupon: _coupon?.code ?? '',
      );

      if (added['status'] == 'maxqty') {
        setState(
          () => _notice =
              'This event allows a maximum of '
              '${added['max_qty']} items per order.',
        );
        return null;
      }

      // The coupon is put on the CART here, and that can fail even though the
      // code validated on its own — most often because none of the chosen
      // tickets are in its allowed list. Ignoring it would send the buyer on
      // to pay full price having been shown a discount.
      final couponMessage = '${added['auto_apply_coupon_message'] ?? ''}'
          .trim();

      if (couponMessage.isNotEmpty &&
          couponMessage != 'Coupon already applied') {
        await CheckoutApi.clearCart(cart);
        _cartToken = null;

        setState(
          () => _notice =
              'The code ${_coupon?.code ?? ''} could not be '
              'applied: $couponMessage. Remove it or change your tickets, '
              'then try again.',
        );
        return null;
      }

      try {
        await CheckoutApi.reserve(cart);
      } on CheckoutException catch (e) {
        // Sold out since the list was loaded. Roll back and show what is
        // actually left rather than holding a cart that cannot be paid for.
        await CheckoutApi.clearCart(cart);
        _cartToken = null;

        if (mounted) setState(() => _notice = e.message);
        await _reloadTickets();
        return null;
      }

      final totals = await CheckoutApi.totals(cart);

      return CheckoutCart(
        token: cart,
        totals: totals,
        // Cast defensively: an empty PHP array arrives as [] rather than
        // {}, which a straight Map cast throws on.
        lines: added['added_tickets'] is Map
            ? (added['added_tickets'] as Map).cast<String, dynamic>()
            : const {},
        // Counted from the reserve that just succeeded. The server holds the
        // stock for an hour from that moment.
        reservedUntil: DateTime.now().add(const Duration(minutes: 60)),
      );
    } on CheckoutException catch (e) {
      if (mounted) setState(() => _notice = e.message);
      return null;
    }
  }

  /// Whether this event can be sold without leaving the app.
  ///
  /// Two conditions, both about where the money goes.
  ///
  /// Stripe and nothing else: PayPal, Square and Mollie are the organiser's
  /// own merchant accounts with browser SDKs and no native equivalent, and an
  /// event offering one of them alongside Stripe would lose a method the
  /// organiser deliberately switched on.
  ///
  /// And that Stripe has to be the organiser's own connected account. Without
  /// one the charge lands on DriveLife's, collecting on their behalf — see
  /// StripeConfig.allowPlatformCharges. Those go to the web checkout whole,
  /// which is the path that was set up for them.
  /// Why this event has to be paid for on the web, or null if it does not.
  ///
  /// A reason rather than a bare false. Handing somebody to a browser with no
  /// explanation is indistinguishable from the native checkout being broken,
  /// which is exactly how it looked the first time it happened.
  ///
  /// The rule it is applying, which the server decides and this only follows:
  ///
  /// * One card provider per organiser — Stripe, Square or Mollie, never two.
  /// * None connected falls back to the platform's Stripe, so every event can
  ///   still sell a ticket.
  /// * PayPal is never the card slot. It sits alongside whichever card
  ///   provider applies, including the fallback.
  ///
  /// So the only question here is whether the app can present what the server
  /// offers — and the single answer that is still no is Mollie.
  String? get _webCheckoutReason {
    final info = _info;
    if (info == null) return 'The event has not finished loading';

    // All four providers are handled in the app. A fifth added server-side
    // would arrive here as an id this version has never heard of, and if it
    // holds the card slot there is no card payment to be taken.
    //
    // That only sinks the native checkout when there is nothing else: an
    // event with an unknown processor AND PayPal is still buyable here, with
    // the card option withheld and said so on the payment screen.
    const handled = {'stripe', 'square', 'paypal', 'mollie'};

    final unsupported = info.providerIds
        .where((id) => !handled.contains(id))
        .toList();

    if (unsupported.isNotEmpty && !info.hasPaypal) {
      return 'This organiser takes ${unsupported.join(', ')}, which the app '
          'cannot handle';
    }

    // Square needs nothing checked here. It is the organiser's own merchant
    // account with no platform split, so the money goes straight to them —
    // the question the Stripe branch below exists to ask does not arise.
    if (info.hasSquare) {
      final square = info.square;

      if (square == null ||
          square.applicationId.isEmpty ||
          square.locationId.isEmpty) {
        if (info.hasPaypal) return null;
        return "This organiser's Square settings are incomplete";
      }

      return null;
    }

    if (info.hasMollie) {
      // Nothing to check, for the same reason as Square: the organiser's own
      // merchant account, no platform split, and nothing in the app that
      // could be missing — the hosted page is Mollie's.
      if (FeatureFlags.nativeMollieCheckout) return null;

      // Untested against a live organiser, so production still sends these to
      // the web checkout. Unless PayPal is also on offer, in which case the
      // native flow stands and the card option is withheld instead.
      if (info.hasPaypal) return null;

      return 'Mollie card payments are not switched on in the app yet';
    }

    // PayPal alone needs nothing from Stripe — the organiser's own PayPal
    // takes the whole amount.
    if (!info.hasStripe) return null;

    final stripe = info.stripe;

    // Site-level and always present in practice. Without it there is no card
    // payment to offer at all, fallback or otherwise.
    if (stripe.key.trim().isEmpty) {
      return 'This site has no Stripe publishable key';
    }

    if (!StripeConfig.mayChargeNatively(
      key: stripe.key,
      account: stripe.account,
    )) {
      // Only reachable with the platform fallback switched off. The card
      // option is then withheld rather than fatal when PayPal is also on
      // offer, since that still pays the organiser directly.
      if (info.hasPaypal) return null;

      return 'This organiser has not connected their own Stripe account, so '
          'the payment would go through DriveLife';
    }

    return null;
  }

  /// Sends the buyer to the web checkout with their selection already made.
  ///
  /// Nothing is reserved first: a cart built here could not be the one that
  /// gets paid for there, and two carts for one buyer means stock held
  /// against an order that will never arrive.
  ///
  /// An in-app browser rather than the system one — it keeps the app on
  /// screen underneath, and being a real browser it handles the redirects
  /// PayPal and Mollie rely on.
  Future<void> _handOffToWeb() async {
    final selected = <String>[
      for (final ticket in _tickets)
        if (!ticket.isSection && (_quantities[ticket.pid] ?? 0) > 0)
          '${Uri.encodeComponent(ticket.pid)}:${_quantities[ticket.pid]}',
    ];

    if (selected.isEmpty) return;

    setState(() => _committing = true);

    // The empty cart opened for a code check has served its purpose.
    final opened = _cartToken;
    if (opened != null) {
      _cartToken = null;
      unawaited(CheckoutApi.clearCart(opened));
    }

    // The region rides in front of the id, bare meaning UK — the same shape
    // the dashboard's links use. Without it a US event handed to the web
    // would open whichever UK event shares its post id.
    final linkEid = widget.site == 'us'
        ? 'us${widget.eventEid}'
        : widget.eventEid;

    final url = Uri.parse('${CheckoutApi.checkoutBaseUrl}/$linkEid').replace(
      queryParameters: {
        'qty': selected.join(','),
        if (_coupon != null) 'coupon': _coupon!.code,
        if (_secretCode.isNotEmpty) 'code': _secretCode,
        // Where the checkout sends the buyer once the order is placed. It
        // appends order_id, which deeplinks_helper turns into their tickets.
        'complete': 'drivelife://app/?dl-order=1',
      },
    );

    var launched = false;

    for (final mode in [
      LaunchMode.inAppBrowserView,
      // Some devices have no browser that will take an in-app view.
      LaunchMode.externalApplication,
    ]) {
      try {
        launched = await launchUrl(url, mode: mode);
      } catch (_) {
        launched = false;
      }

      if (launched) break;
    }

    if (!mounted) return;

    setState(() {
      _committing = false;
      if (!launched) {
        _notice = "We couldn't open the checkout. Please try again.";
      }
    });
  }

  /// Reserves the tickets, then walks the buyer through the rest.
  Future<void> _continue() async {
    final info = _info;
    if (info == null) return;

    // Decided before anything is reserved, because the two paths build their
    // carts in different places.
    final reason = _webCheckoutReason;

    if (reason != null) {
      // Always logged, so a hand-off during testing says why rather than
      // leaving a browser to be explained. Shown on screen only on staging —
      // a buyer does not need to read about Stripe Connect.
      debugPrint('🎟️ [Checkout] Opening the web checkout: $reason');

      if (AppEnvironment.isStaging) {
        setState(() => _notice = 'Web checkout: $reason');
      }

      return _handOffToWeb();
    }

    setState(() {
      _committing = true;
      _notice = null;
    });

    final cart = await _commit();

    if (!mounted) {
      // Left while the cart was being built. It is holding stock now, so it
      // has to be released rather than left to time out.
      if (cart != null) unawaited(CheckoutApi.clearCart(cart.token));
      return;
    }

    setState(() => _committing = false);

    if (cart == null) return;

    final orderId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            TicketDetailsScreen(info: info, cart: cart, tickets: _tickets),
      ),
    );

    if (!mounted) return;

    if (orderId == null || orderId.isEmpty) {
      // Backed out without paying. The cart still holds the stock, so it is
      // released and the next attempt starts a fresh one — exactly what
      // returning to the ticket list does on the web.
      final token = _cartToken;
      _cartToken = null;
      if (token != null) unawaited(CheckoutApi.clearCart(token));

      await _reloadTickets();
      return;
    }

    // Paid. The cart is spent, so it must not be cleared on dispose.
    _cartToken = null;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => OrderTicketsPage(orderId: orderId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Tickets',
          style: TextStyle(
            color: _ink,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: _line),
        ),
      ),
      // The discount and secret-code fields live in here too, so this screen
      // needs the same way out of the keyboard as the details step.
      body: Stack(
        children: [_buildBody(), TicketTheme.keyboardDismissBar(context)],
      ),
      bottomNavigationBar: _buildBar(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 34, color: _muted),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final buyable = _tickets.where((t) => !t.isSection).toList();

    final event = _info?.event;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        TicketTheme.pageHeader(
          // The organiser's checkout logo where they set one, which is what
          // the web checkout shows; the event's own cover otherwise, so the
          // header is never bare.
          imageUrl: event?.ticketsLogo?.isNotEmpty == true
              ? event!.ticketsLogo
              : widget.eventImage,
          eyebrow: 'Get tickets',
          title: event?.title.isNotEmpty == true
              ? event!.title
              : (widget.eventTitle ?? 'Tickets'),
          subtitle: _whenLabel(),
        ),

        if (_notice != null) ...[
          _buildNotice(_notice!),
          const SizedBox(height: 14),
        ],

        // One card holding the whole list, so the section bars run to its
        // edges rather than stopping short of them.
        // No "Tickets" heading on the card: the eyebrow directly above it
        // already says GET TICKETS, and the two together read as a mistake.
        TicketTheme.card(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (buyable.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
                  child: Text(
                    'There are no tickets available for this event at the '
                    'moment.',
                    style: TextStyle(color: _muted, height: 1.4),
                  ),
                )
              else
                for (var i = 0; i < _tickets.length; i++)
                  _tickets[i].isSection
                      ? _buildSection(_tickets[i])
                      : _TicketRow(
                          ticket: _tickets[i],
                          quantity: _quantities[_tickets[i].pid] ?? 0,
                          max: _maxFor(_tickets[i]),
                          coupon: _coupon,
                          vatMultiplier: _info?.vatMultiplier ?? 1,
                          money: _money,
                          // No rule above the first row or straight after a
                          // section bar, which is already a divider.
                          topRule: i > 0 && !_tickets[i - 1].isSection,
                          onChanged: (next) => _setQuantity(_tickets[i], next),
                        ),

              const Divider(height: 1, thickness: 1, color: _line),
              _CodeEntry(
                couponCode: _coupon?.code,
                onCoupon: _applyCoupon,
                onSecret: _applySecret,
                onRemoveCoupon: () {
                  setState(() => _coupon = null);
                  _reloadTickets();
                },
              ),
            ],
          ),
        ),

        TicketTheme.poweredBy(event?.companyName ?? ''),
      ],
    );
  }

  /// "Tue, 1 February 2028", or a range across two days.
  ///
  /// The API sends ISO dates, which are for storing, not for reading. A
  /// one-day event says one date; a longer one says both ends, dropping the
  /// repeated month and year so the common case stays short.
  String _whenLabel() {
    final event = _info!.event;

    final start = DateTime.tryParse(event.startDate);
    if (start == null) return '';

    final end = DateTime.tryParse(event.endDate);
    final full = DateFormat('EEE, d MMMM yyyy');

    if (end == null || end.difference(start).inDays == 0) {
      return full.format(start);
    }

    final sameMonth = start.year == end.year && start.month == end.month;

    return '${DateFormat(sameMonth ? 'd' : 'd MMMM').format(start)} - '
        '${full.format(end)}';
  }

  Widget _buildSection(CheckoutTicket ticket) {
    return Container(
      width: double.infinity,
      // Solid black, matching the web. A section is a divider between kinds
      // of ticket, and at this weight it reads as one at a glance rather than
      // as another row to be scanned.
      color: _ink,
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Text(
        ticket.name.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
        ),
      ),
    );
  }

  Widget _buildNotice(String message) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF0DCC0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 17, color: Color(0xFF9A6B1E)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF7A5416),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The bar that follows the buyer down the list.
  ///
  /// Always present rather than appearing on first selection: a bar that
  /// arrives unannounced shifts the row under the thumb at the moment it is
  /// being tapped.
  Widget? _buildBar() {
    if (_loading || _error != null) return null;

    final count = _totalSelected;
    final ready = count > 0 && !_committing;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    count == 0
                        ? 'No tickets selected'
                        : '$count ticket${count == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _money(_subtotal),
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: ready ? _continue : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE8E4DA),
                  disabledForegroundColor: const Color(0xFFA9A69D),
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _committing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Checkout',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One ticket in the list.
class _TicketRow extends StatelessWidget {
  final CheckoutTicket ticket;
  final int quantity;
  final int max;
  final CheckoutCoupon? coupon;
  final double vatMultiplier;
  final String Function(double) money;
  final bool topRule;
  final ValueChanged<int> onChanged;

  const _TicketRow({
    required this.ticket,
    required this.quantity,
    required this.max,
    required this.coupon,
    required this.vatMultiplier,
    required this.money,
    required this.onChanged,
    this.topRule = false,
  });

  @override
  Widget build(BuildContext context) {
    final listed = ticket.price * vatMultiplier;

    // Struck-through pricing for percentage codes only. A fixed code is taken
    // off the order once, so showing it against each ticket would promise a
    // discount several times over.
    final discounted =
        coupon != null && !coupon!.isFixed && coupon!.appliesTo(ticket.id);
    final price = discounted ? coupon!.priceAfter(listed) : listed;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          top: topRule
              ? const BorderSide(color: _TicketSelectionScreenState._line)
              : BorderSide.none,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        ticket.name,
                        style: const TextStyle(
                          color: _TicketSelectionScreenState._ink,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (ticket.secretMatched) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.lock_open,
                        size: 14,
                        color: _TicketSelectionScreenState._gold,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price <= 0 ? 'Free' : money(price),
                      style: TextStyle(
                        color: discounted
                            ? _TicketSelectionScreenState._gold
                            : _TicketSelectionScreenState._ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (discounted) ...[
                      const SizedBox(width: 8),
                      Text(
                        money(listed),
                        style: const TextStyle(
                          color: _TicketSelectionScreenState._muted,
                          fontSize: 12.5,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ],
                ),
                if (ticket.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    ticket.description.trim(),
                    style: const TextStyle(
                      color: _TicketSelectionScreenState._muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          _buildControl(),
        ],
      ),
    );
  }

  Widget _buildControl() {
    final live = ticket.earlyLiveDate;

    if (live != null) {
      return SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'Goes live',
              style: TextStyle(
                color: _TicketSelectionScreenState._muted,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('d MMM, HH:mm').format(live.toLocal()),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _TicketSelectionScreenState._ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
        ),
      );
    }

    if (ticket.soldOut) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F1EE),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'SOLD OUT',
          style: TextStyle(
            color: _TicketSelectionScreenState._muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );
    }

    return _QuantityStepper(value: quantity, max: max, onChanged: onChanged);
  }
}

/// Minus, count, plus.
class _QuantityStepper extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _QuantityStepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing left to give: either none were ever on sale, or the order cap
    // has been reached by other tickets.
    if (max <= 0 && value == 0) {
      return const Text(
        'Unavailable',
        style: TextStyle(
          color: _TicketSelectionScreenState._muted,
          fontSize: 12.5,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _TicketSelectionScreenState._line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: Icons.remove,
            onTap: value > 0 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _TicketSelectionScreenState._ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add,
            onTap: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null
                ? const Color(0xFFCFCDC7)
                : _TicketSelectionScreenState._ink,
          ),
        ),
      ),
    );
  }
}

/// Discount and secret codes, tucked under the list.
///
/// Collapsed by default. Most buyers have neither, and two empty fields above
/// the Continue button read as something that has to be filled in.
class _CodeEntry extends StatefulWidget {
  final String? couponCode;
  final Future<void> Function(String) onCoupon;
  final Future<void> Function(String) onSecret;
  final VoidCallback onRemoveCoupon;

  const _CodeEntry({
    required this.couponCode,
    required this.onCoupon,
    required this.onSecret,
    required this.onRemoveCoupon,
  });

  @override
  State<_CodeEntry> createState() => _CodeEntryState();
}

class _CodeEntryState extends State<_CodeEntry> {
  final _controller = TextEditingController();

  bool _open = false;
  bool _busy = false;

  /// Secret codes reveal tickets; discount codes reprice them. One field
  /// cannot tell which was typed, so the buyer says.
  bool _isSecret = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty || _busy) return;

    setState(() => _busy = true);

    if (_isSecret) {
      await widget.onSecret(code);
    } else {
      await widget.onCoupon(code);
    }

    if (!mounted) return;

    _controller.clear();
    setState(() => _busy = false);
  }

  Widget _codeLink(String label, {required bool secret}) {
    return GestureDetector(
      onTap: () => setState(() {
        _isSecret = secret;
        _open = true;
      }),
      child: Text(
        label,
        style: const TextStyle(
          color: _TicketSelectionScreenState._gold,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final applied = widget.couponCode;

    if (applied != null && applied.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: [
            const Icon(
              Icons.local_offer_outlined,
              size: 16,
              color: _TicketSelectionScreenState._gold,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$applied applied',
                style: const TextStyle(
                  color: _TicketSelectionScreenState._ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: widget.onRemoveCoupon,
              style: TextButton.styleFrom(
                foregroundColor: _TicketSelectionScreenState._muted,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Remove', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
    }

    if (!_open) {
      // Named separately rather than as one "discount or secret code" link.
      // They do different things — one reprices, the other reveals tickets
      // that are not on the list — and a buyer holding one knows which.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Wrap(
          spacing: 20,
          runSpacing: 4,
          children: [
            _codeLink('Have a discount code?', secret: false),
            _codeLink('Have a secret code?', secret: true),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _isSecret ? 'Secret code' : 'Discount code',
                  style: const TextStyle(
                    color: _TicketSelectionScreenState._ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              // A way back out. Opening this used to be one-way: the only
              // exits were applying a code or leaving the screen, which is a
              // trap for anyone who tapped it to see what it was.
              GestureDetector(
                onTap: _close,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: _TicketSelectionScreenState._muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _isSecret
                ? 'Unlocks tickets that are not shown publicly.'
                : 'Reduces the price of the tickets it applies to.',
            style: const TextStyle(
              color: _TicketSelectionScreenState._muted,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _isSecret ? 'Enter code' : 'Enter code',
                    hintStyle: const TextStyle(
                      color: _TicketSelectionScreenState._muted,
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
                      borderSide: const BorderSide(
                        color: _TicketSelectionScreenState._line,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: _TicketSelectionScreenState._gold,
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
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _TicketSelectionScreenState._gold,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE8E4DA),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 15,
                          height: 15,
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
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _isSecret = !_isSecret),
            child: Text(
              _isSecret
                  ? 'I have a discount code instead'
                  : 'I have a secret code instead',
              style: const TextStyle(
                color: _TicketSelectionScreenState._gold,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Puts the field away without applying anything.
  void _close() {
    FocusScope.of(context).unfocus();
    _controller.clear();
    setState(() => _open = false);
  }
}
