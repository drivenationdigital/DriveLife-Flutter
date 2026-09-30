/// Types for the ticket checkout.
///
/// These mirror the interfaces in the Next.js checkout's lib/checkout/api.ts,
/// which is the contract both clients read. Where a name differs from ours the
/// wire name wins — this is somebody else's API and renaming fields in the
/// parser is how two clients quietly stop agreeing about the same cart.
library;

double _num(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? 0;
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

String _str(dynamic value) => value == null ? '' : '$value';

/// What a ticket asks the buyer for.
///
/// Each flag turns on a block of fields in the details step. Carried here so
/// the ticket list can say what a ticket will involve before it is chosen.
class TicketFlags {
  final bool contactDetails;
  final bool carDetails;
  final bool concours;
  final bool attendance;
  final bool carClub;
  final bool vehiclePhoto;
  final bool collectionDelivery;

  const TicketFlags({
    this.contactDetails = false,
    this.carDetails = false,
    this.concours = false,
    this.attendance = false,
    this.carClub = false,
    this.vehiclePhoto = false,
    this.collectionDelivery = false,
  });

  factory TicketFlags.fromJson(Map<String, dynamic> json) => TicketFlags(
    contactDetails: json['contactDetails'] == true,
    carDetails: json['carDetails'] == true,
    concours: json['concours'] == true,
    attendance: json['attendance'] == true,
    carClub: json['carClub'] == true,
    vehiclePhoto: json['vehiclePhoto'] == true,
    collectionDelivery: json['collectionDelivery'] == true,
  );
}

/// One row of the ticket list.
class CheckoutTicket {
  final int id;

  /// Encrypted ticket id — the currency of the PHP cart API.
  ///
  /// Everything that addresses a ticket uses this, never [id]. The plain id is
  /// only good for matching a coupon's allowed list.
  final String pid;

  final String name;
  final String description;
  final double price;
  final int stock;
  final int maxQuantity;

  /// A heading in the list rather than something that can be bought.
  final bool isSection;

  final bool soldOut;

  /// When a not-yet-on-sale ticket opens, else null.
  final DateTime? earlyLiveDate;

  /// Revealed by the secret code the buyer entered.
  final bool secretMatched;

  final TicketFlags flags;
  final String collectionInformation;

  const CheckoutTicket({
    required this.id,
    required this.pid,
    required this.name,
    this.description = '',
    this.price = 0,
    this.stock = 0,
    this.maxQuantity = 0,
    this.isSection = false,
    this.soldOut = false,
    this.earlyLiveDate,
    this.secretMatched = false,
    this.flags = const TicketFlags(),
    this.collectionInformation = '',
  });

  /// Can this row be added to a cart at all?
  bool get isBuyable => !isSection && !soldOut && earlyLiveDate == null;

  factory CheckoutTicket.fromJson(Map<String, dynamic> json) {
    final early = _str(json['earlyLiveDate']);

    return CheckoutTicket(
      id: _int(json['id']),
      pid: _str(json['pid']),
      name: _str(json['name']),
      description: _str(json['description']),
      price: _num(json['price']),
      stock: _int(json['stock']),
      maxQuantity: _int(json['maxQuantity']),
      isSection: json['isSection'] == true,
      soldOut: json['soldOut'] == true,
      earlyLiveDate: early.isEmpty ? null : DateTime.tryParse(early),
      secretMatched: json['secretMatched'] == true,
      flags: TicketFlags.fromJson(
        (json['flags'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      collectionInformation: _str(json['collectionInformation']),
    );
  }
}

/// The event, as the checkout describes it.
class CheckoutEvent {
  final int id;
  final String eid;
  final String title;
  final String permalink;
  final String startDate;
  final String startTime;
  final String endDate;
  final String endTime;
  final String location;
  final String? ticketsLogo;

  /// '1' is a free registration-only event: no tickets and no payment.
  final String ticketType;

  /// How many items one order may contain, across all tickets. 0 is no cap.
  final int maxItemsPerOrder;

  final String newsletterLabel;
  final String termsHtml;
  final String siteTermsHtml;
  final String companyName;

  /// 'uk' or 'us'. Decides currency, and rides along on every payment call.
  final String site;

  final String currency;

  const CheckoutEvent({
    required this.id,
    required this.eid,
    required this.title,
    this.permalink = '',
    this.startDate = '',
    this.startTime = '',
    this.endDate = '',
    this.endTime = '',
    this.location = '',
    this.ticketsLogo,
    this.ticketType = '',
    this.maxItemsPerOrder = 0,
    this.newsletterLabel = '',
    this.termsHtml = '',
    this.siteTermsHtml = '',
    this.companyName = '',
    this.site = 'uk',
    this.currency = 'GBP',
  });

  /// Free registration rather than a sale.
  bool get isRegistrationOnly => ticketType == '1';

  factory CheckoutEvent.fromJson(Map<String, dynamic> json) {
    final logo = _str(json['tickets_logo']);

    return CheckoutEvent(
      id: _int(json['id']),
      eid: _str(json['eid']),
      title: _str(json['title']),
      permalink: _str(json['permalink']),
      startDate: _str(json['start_date']),
      startTime: _str(json['start_time']),
      endDate: _str(json['end_date']),
      endTime: _str(json['end_time']),
      location: _str(json['location']),
      ticketsLogo: logo.isEmpty ? null : logo,
      ticketType: _str(json['ticket_type']),
      maxItemsPerOrder: _int(json['max_items_per_order']),
      newsletterLabel: _str(json['newsletter_label']),
      termsHtml: _str(json['terms_html']),
      siteTermsHtml: _str(json['site_terms_html']),
      companyName: _str(json['company_name']),
      site: _str(json['site']).isEmpty ? 'uk' : _str(json['site']),
      currency: _str(json['currency']).isEmpty ? 'GBP' : _str(json['currency']),
    );
  }
}

/// A payment method the organiser has switched on.
///
/// Only the id matters here. The credentials each one carries are the payment
/// step's business, and that is not built yet — but which methods exist
/// decides, before a cart is ever created, whether this event can be sold
/// natively or has to go to the web checkout.
class CheckoutProvider {
  final String id;
  final String label;
  final Map<String, dynamic> raw;

  const CheckoutProvider({
    required this.id,
    this.label = '',
    this.raw = const {},
  });

  factory CheckoutProvider.fromJson(Map<String, dynamic> json) =>
      CheckoutProvider(
        id: _str(json['id']),
        label: _str(json['label']),
        raw: json,
      );
}

/// Everything the checkout needs before it shows anything.
class CheckoutInfo {
  final CheckoutEvent event;

  /// 1.2 where the organiser displays VAT-inclusive prices, else 1.
  final double vatMultiplier;

  /// The Stripe account this event's money goes to.
  ///
  /// Always sent, unlike [providers], which a backend predating the
  /// multi-provider work omits entirely. `account` is the organiser's
  /// connected account, or null where they have none and the charge lands on
  /// the platform's own.
  final String stripeKey;
  final String? stripeAccount;

  /// Server-ordered list of enabled methods.
  ///
  /// Empty on a backend that predates the multi-provider work, which supports
  /// Stripe and nothing else — so empty means Stripe, not "no way to pay".
  final List<CheckoutProvider> providers;

  const CheckoutInfo({
    required this.event,
    this.vatMultiplier = 1,
    this.providers = const [],
    this.stripeKey = '',
    this.stripeAccount,
  });

  /// Which methods this event accepts, with the legacy default applied.
  List<String> get providerIds =>
      providers.isEmpty ? const ['stripe'] : [for (final p in providers) p.id];

  factory CheckoutInfo.fromJson(Map<String, dynamic> json) {
    final stripe = (json['stripe'] as Map?)?.cast<String, dynamic>();
    final account = _str(stripe?['account']);

    return CheckoutInfo(
      event: CheckoutEvent.fromJson(
        (json['event'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      stripeKey: _str(stripe?['publishable_key']),
      stripeAccount: account.isEmpty ? null : account,
      vatMultiplier: json['display_vat_multiplier'] == null
          ? 1
          : _num(json['display_vat_multiplier']),
      providers: ((json['providers'] as List?) ?? const [])
          .whereType<Map>()
          .map((p) => CheckoutProvider.fromJson(p.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

/// A discount code, once the server has validated it.
class CheckoutCoupon {
  final String code;
  final double discountAmount;

  /// 'percentage' or 'fixed'.
  final String discountType;

  /// Plain ticket ids this applies to. Empty means everything.
  final Set<int> allowedProducts;

  const CheckoutCoupon({
    required this.code,
    this.discountAmount = 0,
    this.discountType = 'percentage',
    this.allowedProducts = const {},
  });

  bool get isFixed => discountType == 'fixed';

  /// Does this code touch that ticket?
  bool appliesTo(int ticketId) =>
      allowedProducts.isEmpty || allowedProducts.contains(ticketId);

  /// [price] after a percentage code. Fixed codes come off the order total
  /// once, so they are not a per-ticket price at all.
  double priceAfter(double price) {
    if (isFixed) return price;

    final after = price - (price * discountAmount / 100);
    return after < 0 ? 0 : after;
  }

  factory CheckoutCoupon.fromJson(Map<String, dynamic> json) {
    // The wire sends a comma-joined string, a list, or null.
    final allowed = json['allowed_products'];
    final ids = <int>{};

    if (allowed is List) {
      for (final id in allowed) {
        final parsed = _int(id);
        if (parsed > 0) ids.add(parsed);
      }
    } else if (allowed != null && '$allowed'.trim().isNotEmpty) {
      for (final part in '$allowed'.split(',')) {
        final parsed = _int(part.trim());
        if (parsed > 0) ids.add(parsed);
      }
    }

    return CheckoutCoupon(
      code: _str(json['coupon_code']),
      discountAmount: _num(json['discount_amount']),
      discountType: _str(json['discount_type']),
      allowedProducts: ids,
    );
  }
}

/// What the server says the cart comes to.
///
/// Authoritative. The ticket list computes its own running subtotal so the
/// steppers feel instant, but that figure is a preview — nothing is charged
/// from it, and this replaces it the moment the cart is built.
class CartTotals {
  final double subtotal;
  final double total;
  final double vat;
  final double discount;
  final double feeAmount;
  final String feeName;

  const CartTotals({
    this.subtotal = 0,
    this.total = 0,
    this.vat = 0,
    this.discount = 0,
    this.feeAmount = 0,
    this.feeName = '',
  });

  factory CartTotals.fromJson(Map<String, dynamic> json) {
    final coupons = (json['coupons'] as Map?)?.cast<String, dynamic>();
    final fees = (json['fees'] as Map?)?.cast<String, dynamic>();

    return CartTotals(
      subtotal: _num(json['subtotal']),
      total: _num(json['total']),
      vat: _num(json['vat']),
      discount: coupons == null ? 0 : _num(coupons['discount']),
      feeAmount: fees == null ? 0 : _num(fees['amount']),
      feeName: fees == null ? '' : _str(fees['name']),
    );
  }
}

/// What kind of input a per-ticket field needs.
enum UnitFieldKind { text, phone, checkbox, photo }

/// One input a ticket asks for, about one of the people it admits.
class UnitFieldSpec {
  final String field;
  final String label;
  final UnitFieldKind kind;

  const UnitFieldSpec(this.field, this.label, this.kind);
}

/// The inputs a ticket's flags require, in the order they are shown.
///
/// Mirrors unitFieldSpecs() in the web checkout's DetailsStep. The order is
/// part of the contract: both clients write to the same cart meta, and a
/// buyer who started on one and finished on the other should be asked the
/// same things in the same sequence.
List<UnitFieldSpec> unitFieldSpecs(CheckoutTicket ticket) => [
  if (ticket.flags.contactDetails) ...[
    const UnitFieldSpec('name', 'Full name', UnitFieldKind.text),
    const UnitFieldSpec('phone', 'Phone number', UnitFieldKind.phone),
  ],
  if (ticket.flags.carDetails) ...[
    const UnitFieldSpec('make', 'Vehicle make', UnitFieldKind.text),
    const UnitFieldSpec('model', 'Vehicle model', UnitFieldKind.text),
    const UnitFieldSpec('reg', 'Vehicle registration', UnitFieldKind.text),
  ],
  if (ticket.flags.carClub)
    const UnitFieldSpec('car_club', 'Car club name', UnitFieldKind.text),
  if (ticket.flags.vehiclePhoto)
    const UnitFieldSpec('vehicle_photo', 'Vehicle photo', UnitFieldKind.photo),
  if (ticket.flags.concours)
    const UnitFieldSpec(
      'concours',
      'Concours / special display',
      UnitFieldKind.checkbox,
    ),
];

/// One admission: a ticket, and which of that ticket's copies this is.
///
/// A cart line of three tickets is three people, each with their own answers,
/// so the details step works in units rather than lines.
class CheckoutUnit {
  final String pid;
  final int index;
  final CheckoutTicket ticket;

  const CheckoutUnit({
    required this.pid,
    required this.index,
    required this.ticket,
  });

  /// Unique within a cart — used to key form state and error messages.
  String get key => '$pid:$index';
}

/// Expands the server's cart lines into one entry per admission, in cart
/// order.
List<CheckoutUnit> cartUnits(
  Map<String, dynamic> cart,
  List<CheckoutTicket> tickets,
) {
  final byPid = {for (final t in tickets) t.pid: t};
  final units = <CheckoutUnit>[];

  cart.forEach((pid, line) {
    final ticket = byPid[pid];
    if (ticket == null) return;

    final qty = line is Map ? _int(line['qty']) : 0;

    for (var i = 0; i < qty; i++) {
      units.add(CheckoutUnit(pid: pid, index: i, ticket: ticket));
    }
  });

  return units;
}

/// The encrypted event id inside a CarEvents ticket URL, or null.
///
/// The events API sends `ticket_url`, which for its own ticketing is
/// `…/get-tickets/event.php?event_id=<eid>` — the same eid the checkout takes.
/// Reading it from there means nothing has to be deployed for the app to
/// address the checkout.
///
/// Null for an organiser's external ticketing link, which is the discriminator
/// that matters: those are somebody else's site and must keep opening in a
/// browser.
String? checkoutEidFromTicketUrl(String? ticketUrl) {
  if (ticketUrl == null || ticketUrl.trim().isEmpty) return null;

  final uri = Uri.tryParse(ticketUrl.trim());
  if (uri == null || !uri.hasScheme) return null;

  // Ours, not an organiser's. A link elsewhere that happened to carry an
  // event_id would otherwise be read as a CarEvents event.
  if (!uri.host.toLowerCase().endsWith('carevents.com')) return null;

  final eid = uri.queryParameters['event_id'];
  if (eid == null || eid.trim().isEmpty) return null;

  return eid.trim();
}

/// A cart that has been built, reserved and priced on the server.
///
/// What the ticket step hands to the details step. The token is the only
/// thing that matters — every later call is keyed by it — but the totals and
/// line items ride along so the next screen has something to show
/// immediately.
class CheckoutCart {
  final String token;
  final CartTotals totals;

  /// The server's line items, keyed by ticket. Passed through as received.
  final Map<String, dynamic> lines;

  const CheckoutCart({
    required this.token,
    this.totals = const CartTotals(),
    this.lines = const {},
  });
}
