
/// Models for the event editor sections that exist in the Next.js dashboard
/// (`drivelife-account`) but not yet in the app: discounts, show cars, car
/// clubs and traders.
///
/// Field names and semantics mirror `context/EventCreateContext.tsx` so the two
/// clients describe the same event the same way. Two deliberate translations:
///
///  * The dashboard uses `NaN` for "unset" on numeric fields. Dart has a proper
///    null, so these are nullable and `NaN` never appears.
///  * Dates are `DateTime` here and ISO `yyyy-MM-dd` strings on the wire, which
///    is the format the dashboard sends.
///
/// The JSON keys are snake_case to match the dashboard's save payload
/// (`lib/eventSaveMapper.ts`), so these will serialise straight into
/// `dl-accounts/v1/event-update` when the app is pointed at it.
library;

import 'package:flutter/material.dart';

/// Client-side id for a row that may not have been saved yet.
///
/// The dashboard generates these too — a category has to be identifiable in the
/// list, and referenced by a discount, before the server has ever seen it.
String newEditorId(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

String? _isoDate(DateTime? date) {
  if (date == null) return null;
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

/// Parses a number that may arrive as a string, and treats blank/NaN as unset.
num? _num(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.isNaN ? null : value;
  final parsed = num.tryParse(value.toString());
  return (parsed == null || parsed.isNaN) ? null : parsed;
}

int? _int(dynamic value) => _num(value)?.toInt();

/// "HH:MM" from a datetime, or null when there is no datetime.
///
/// The car-clubs window arrives as one value but is edited as a date and a
/// time, so the two halves are separated on the way in.
String? _timeOf(DateTime? value) {
  if (value == null) return null;
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
double? _double(dynamic value) => _num(value)?.toDouble();
bool _bool(dynamic value) => value == true || value == 1 || value == '1';
String _str(dynamic value) => value?.toString() ?? '';

// ── Discounts ────────────────────────────────────────────────────────────────

enum DiscountKind { percentage, fixed }

/// A promo code applied at checkout.
class EventDiscount {
  final String id;

  /// What the buyer types. Stored uppercase, as the dashboard does.
  final String code;
  final DiscountKind kind;
  final double amount;

  /// Total redemptions allowed; null = unlimited.
  final int? usageLimit;

  /// Redemptions allowed per customer; null = unlimited.
  final int? perCustomerLimit;

  /// Read-only, from the server.
  final int usageCount;

  /// Total discount given across all orders using this code. Read-only.
  final double discountGiven;

  /// Empty = applies to every ticket. Stored empty rather than listing every
  /// id, so a ticket added later isn't silently excluded.
  final List<String> applicableTicketIds;

  final DateTime? availableFrom;
  final DateTime? availableUntil;

  /// Free-form note shown under the code, e.g. "Club members only".
  final String note;

  const EventDiscount({
    required this.id,
    this.code = '',
    this.kind = DiscountKind.percentage,
    this.amount = 0,
    this.usageLimit,
    this.perCustomerLimit,
    this.usageCount = 0,
    this.discountGiven = 0,
    this.applicableTicketIds = const [],
    this.availableFrom,
    this.availableUntil,
    this.note = '',
  });

  factory EventDiscount.blank() => EventDiscount(id: newEditorId('discount'));

  bool get appliesToAllTickets => applicableTicketIds.isEmpty;

  bool get isExpired =>
      availableUntil != null && availableUntil!.isBefore(DateTime.now());

  bool get isUsedUp => usageLimit != null && usageCount >= usageLimit!;

  EventDiscount copyWith({
    String? code,
    DiscountKind? kind,
    double? amount,
    int? Function()? usageLimit,
    int? Function()? perCustomerLimit,
    List<String>? applicableTicketIds,
    DateTime? Function()? availableFrom,
    DateTime? Function()? availableUntil,
    String? note,
  }) {
    return EventDiscount(
      id: id,
      code: code ?? this.code,
      kind: kind ?? this.kind,
      amount: amount ?? this.amount,
      // Nullable fields take a callback so "clear it" is expressible —
      // `usageLimit: null` alone can't be told apart from "leave it".
      usageLimit: usageLimit == null ? this.usageLimit : usageLimit(),
      perCustomerLimit: perCustomerLimit == null
          ? this.perCustomerLimit
          : perCustomerLimit(),
      usageCount: usageCount,
      discountGiven: discountGiven,
      applicableTicketIds: applicableTicketIds ?? this.applicableTicketIds,
      availableFrom: availableFrom == null ? this.availableFrom : availableFrom(),
      availableUntil: availableUntil == null
          ? this.availableUntil
          : availableUntil(),
      note: note ?? this.note,
    );
  }

  /// Reads a discount from the `discounts` array of
  /// `dl-accounts/v1/event-edit`.
  ///
  /// Those rows come from `cc_get_coupons_for_event`, which returns a
  /// WooCommerce-coupon-shaped record — so the keys are Woo's (`ID`,
  /// `discount_type`, `usage_limit_per_user`, `date_expires`) rather than the
  /// editor's. Each field below accepts the Woo spelling first and the editor
  /// spelling as a fallback, because I have not seen a live response: the
  /// helper is not in the checked-out source, so this is written from Woo's
  /// documented shape and needs confirming against real data.
  factory EventDiscount.fromJson(Map<String, dynamic> json) {
    dynamic pick(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value != null && value.toString().isNotEmpty) return value;
      }
      return null;
    }

    // Woo stores 'percent' / 'fixed_cart' / 'fixed_product'.
    final rawKind = _str(pick(['kind', 'discount_type'])).toLowerCase();
    final isPercent = rawKind.contains('percent') || rawKind.isEmpty;

    return EventDiscount(
      id: _str(pick(['id', 'ID', 'encrypted_id'])).isEmpty
          ? newEditorId('discount')
          : _str(pick(['id', 'ID', 'encrypted_id'])),
      code: _str(pick(['code', 'post_title'])),
      kind: isPercent ? DiscountKind.percentage : DiscountKind.fixed,
      amount: _double(pick(['amount', 'coupon_amount'])) ?? 0,
      usageLimit: _int(pick(['usage_limit'])),
      perCustomerLimit: _int(
        pick(['per_customer_limit', 'usage_limit_per_user']),
      ),
      usageCount: _int(pick(['usage_count'])) ?? 0,
      discountGiven: _double(pick(['discount_given'])) ?? 0,
      applicableTicketIds:
          (pick(['applicable_ticket_ids', 'product_ids']) as List<dynamic>? ??
                  const [])
              .map((e) => e.toString())
              .toList(),
      availableFrom: _parseDate(pick(['available_from', 'date_created'])),
      availableUntil: _parseDate(pick(['available_until', 'date_expires'])),
      note: _str(pick(['note', 'description'])),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code.toUpperCase(),
    'kind': kind.name,
    'amount': amount,
    'usage_limit': usageLimit,
    'per_customer_limit': perCustomerLimit,
    'applicable_ticket_ids': applicableTicketIds,
    'available_from': _isoDate(availableFrom),
    'available_until': _isoDate(availableUntil),
    'note': note,
  };
}

// ── Show cars ────────────────────────────────────────────────────────────────

/// One class of show-car entry, e.g. "Modified" or "Classics".
class ShowCarCategory {
  final String id;
  final String name;
  final String description;
  final DateTime? applicationsOpen;
  final DateTime? applicationsClose;

  /// null = unlimited.
  final int? spacesAvailable;

  /// Kept separate from [ticketCost] so switching it off doesn't lose the
  /// value. A free category still goes through apply → approve; approval just
  /// confirms instead of asking for payment.
  final bool requireTicket;
  final double? ticketCost;

  /// Gates the public ticket URL for this category, so applicants to different
  /// categories get different links.
  final String secretCode;

  const ShowCarCategory({
    required this.id,
    this.name = '',
    this.description = '',
    this.applicationsOpen,
    this.applicationsClose,
    this.spacesAvailable,
    this.requireTicket = false,
    this.ticketCost,
    this.secretCode = '',
  });

  factory ShowCarCategory.blank() =>
      ShowCarCategory(id: newEditorId('showcar'));

  ShowCarCategory copyWith({
    String? name,
    String? description,
    DateTime? Function()? applicationsOpen,
    DateTime? Function()? applicationsClose,
    int? Function()? spacesAvailable,
    bool? requireTicket,
    double? Function()? ticketCost,
    String? secretCode,
  }) {
    return ShowCarCategory(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      applicationsOpen: applicationsOpen == null
          ? this.applicationsOpen
          : applicationsOpen(),
      applicationsClose: applicationsClose == null
          ? this.applicationsClose
          : applicationsClose(),
      spacesAvailable: spacesAvailable == null
          ? this.spacesAvailable
          : spacesAvailable(),
      requireTicket: requireTicket ?? this.requireTicket,
      ticketCost: ticketCost == null ? this.ticketCost : ticketCost(),
      secretCode: secretCode ?? this.secretCode,
    );
  }

  factory ShowCarCategory.fromJson(Map<String, dynamic> json) {
    return ShowCarCategory(
      id: _str(json['id']).isEmpty ? newEditorId('showcar') : _str(json['id']),
      name: _str(json['name']),
      description: _str(json['description']),
      applicationsOpen: _parseDate(json['applications_open']),
      applicationsClose: _parseDate(json['applications_close']),
      spacesAvailable: _int(json['spaces_available']),
      requireTicket: _bool(json['require_ticket']),
      ticketCost: _double(json['ticket_cost']),
      secretCode: _str(json['secret_code']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'applications_open': _isoDate(applicationsOpen),
    'applications_close': _isoDate(applicationsClose),
    'spaces_available': spacesAvailable,
    'require_ticket': requireTicket,
    'ticket_cost': ticketCost,
    'secret_code': secretCode,
  };
}

/// Event-wide show-car settings, plus its categories.
class ShowCarsConfig {
  final bool enabled;
  final bool limitEnabled;

  /// Overall cap across all categories; null = unset.
  final int? max;
  final List<ShowCarCategory> categories;
  final String info;

  const ShowCarsConfig({
    this.enabled = false,
    this.limitEnabled = false,
    this.max,
    this.categories = const [],
    this.info = '',
  });

  ShowCarsConfig copyWith({
    bool? enabled,
    bool? limitEnabled,
    int? Function()? max,
    List<ShowCarCategory>? categories,
    String? info,
  }) {
    return ShowCarsConfig(
      enabled: enabled ?? this.enabled,
      limitEnabled: limitEnabled ?? this.limitEnabled,
      max: max == null ? this.max : max(),
      categories: categories ?? this.categories,
      info: info ?? this.info,
    );
  }

  /// Reads the `show_cars` block from `dl-accounts/v1/event-edit`.
  ///
  /// That block is a discriminated union: `{enabled: false}` when the section
  /// is off, otherwise `{enabled: true, config: {...}, categories: [...]}`.
  /// There is no `limit_enabled` on the wire — a cap simply exists or is null,
  /// so the toggle is derived rather than stored.
  factory ShowCarsConfig.fromJson(Map<String, dynamic> json) {
    final config = json['config'] as Map<String, dynamic>? ?? const {};
    final max = _int(config['max']);

    return ShowCarsConfig(
      enabled: _bool(json['enabled']),
      limitEnabled: max != null,
      max: max,
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ShowCarCategory.fromJson)
          .toList(),
      info: _str(config['info']),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'limit_enabled': limitEnabled,
    'max': max,
    'categories': categories.map((c) => c.toJson()).toList(),
    'info': info,
  };
}

// ── Car clubs ────────────────────────────────────────────────────────────────

/// Car-club stand applications. One set of settings, no categories.
class CarClubsConfig {
  final bool enabled;
  final DateTime? applicationsOpen;
  final DateTime? applicationsClose;

  /// "HH:MM", paired with the dates above.
  final String applicationsOpenTime;
  final String applicationsCloseTime;
  final bool limitEnabled;
  final int? max;
  final bool requireTicket;
  final double? ticketCost;
  final String info;

  const CarClubsConfig({
    this.enabled = false,
    this.applicationsOpen,
    this.applicationsClose,
    this.applicationsOpenTime = '09:00',
    this.applicationsCloseTime = '17:00',
    this.limitEnabled = false,
    this.max,
    this.requireTicket = false,
    this.ticketCost,
    this.info = '',
  });

  CarClubsConfig copyWith({
    bool? enabled,
    DateTime? Function()? applicationsOpen,
    DateTime? Function()? applicationsClose,
    String? applicationsOpenTime,
    String? applicationsCloseTime,
    bool? limitEnabled,
    int? Function()? max,
    bool? requireTicket,
    double? Function()? ticketCost,
    String? info,
  }) {
    return CarClubsConfig(
      enabled: enabled ?? this.enabled,
      applicationsOpen: applicationsOpen == null
          ? this.applicationsOpen
          : applicationsOpen(),
      applicationsClose: applicationsClose == null
          ? this.applicationsClose
          : applicationsClose(),
      applicationsOpenTime: applicationsOpenTime ?? this.applicationsOpenTime,
      applicationsCloseTime: applicationsCloseTime ?? this.applicationsCloseTime,
      limitEnabled: limitEnabled ?? this.limitEnabled,
      max: max == null ? this.max : max(),
      requireTicket: requireTicket ?? this.requireTicket,
      ticketCost: ticketCost == null ? this.ticketCost : ticketCost(),
      info: info ?? this.info,
    );
  }

  /// Reads the `car_clubs` block from `dl-accounts/v1/event-edit`.
  ///
  /// Same union shape as show cars. The window arrives as two datetimes
  /// (`open_date` / `close_date`) rather than the separate date and time the
  /// editor shows, so both halves are split out of the one value here.
  factory CarClubsConfig.fromJson(Map<String, dynamic> json) {
    final config = json['config'] as Map<String, dynamic>? ?? const {};

    final open = _parseDate(config['open_date']);
    final close = _parseDate(config['close_date']);
    final max = _int(config['max']);

    return CarClubsConfig(
      enabled: _bool(json['enabled']),
      applicationsOpen: open,
      applicationsClose: close,
      applicationsOpenTime: _timeOf(open) ?? '09:00',
      applicationsCloseTime: _timeOf(close) ?? '17:00',
      limitEnabled: max != null,
      max: max,
      requireTicket: _bool(config['require_ticket']),
      ticketCost: _double(config['ticket_cost']),
      info: _str(config['info']),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'applications_open': _isoDate(applicationsOpen),
    'applications_close': _isoDate(applicationsClose),
    'applications_open_time': applicationsOpenTime,
    'applications_close_time': applicationsCloseTime,
    'limit_enabled': limitEnabled,
    'max': max,
    'require_ticket': requireTicket,
    'ticket_cost': ticketCost,
    'info': info,
  };
}

// ── Traders ──────────────────────────────────────────────────────────────────

/// Curated icon set, matching the dashboard's four choices.
enum TraderIcon { utensils, shirt, wrench, handshake }

extension TraderIconDisplay on TraderIcon {
  String get label => switch (this) {
    TraderIcon.utensils => 'Food & drink',
    TraderIcon.shirt => 'Apparel',
    TraderIcon.wrench => 'Tools / parts',
    TraderIcon.handshake => 'Sponsors',
  };

  /// Material equivalents of the dashboard's Font Awesome classes.
  IconData get icon => switch (this) {
    TraderIcon.utensils => Icons.restaurant,
    TraderIcon.shirt => Icons.checkroom,
    TraderIcon.wrench => Icons.build,
    TraderIcon.handshake => Icons.handshake,
  };
}

TraderIcon traderIconFromName(String name) => TraderIcon.values.firstWhere(
  (i) => i.name == name,
  orElse: () => TraderIcon.utensils,
);

/// How a pitch is paid for. Never free, unlike show cars.
///
/// `online` takes payment at checkout through a hidden ticket; `inPerson` is
/// invoice or pay-on-the-day, which the organiser marks confirmed once cleared.
/// Both run the same pending → approved → confirmed → rejected flow.
enum TraderPaymentMode { online, inPerson }

extension TraderPaymentModeDisplay on TraderPaymentMode {
  String get label => switch (this) {
    TraderPaymentMode.online => 'Pay online',
    TraderPaymentMode.inPerson => 'Pay in person',
  };

  /// Wire value — snake_case, matching the dashboard.
  String get wireValue => switch (this) {
    TraderPaymentMode.online => 'online',
    TraderPaymentMode.inPerson => 'in_person',
  };
}

class TraderCategory {
  final String id;
  final String name;
  final TraderIcon icon;
  final DateTime? applicationsOpen;
  final DateTime? applicationsClose;
  final String info;
  final TraderPaymentMode paymentMode;

  /// Pitch fee. Recorded for both modes — in-person just collects it offline.
  final double? ticketCost;
  final int? spacesAvailable;
  final String secretCode;

  const TraderCategory({
    required this.id,
    this.name = '',
    this.icon = TraderIcon.utensils,
    this.applicationsOpen,
    this.applicationsClose,
    this.info = '',
    this.paymentMode = TraderPaymentMode.online,
    this.ticketCost,
    this.spacesAvailable,
    this.secretCode = '',
  });

  factory TraderCategory.blank() => TraderCategory(id: newEditorId('trader'));

  TraderCategory copyWith({
    String? name,
    TraderIcon? icon,
    DateTime? Function()? applicationsOpen,
    DateTime? Function()? applicationsClose,
    String? info,
    TraderPaymentMode? paymentMode,
    double? Function()? ticketCost,
    int? Function()? spacesAvailable,
    String? secretCode,
  }) {
    return TraderCategory(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      applicationsOpen: applicationsOpen == null
          ? this.applicationsOpen
          : applicationsOpen(),
      applicationsClose: applicationsClose == null
          ? this.applicationsClose
          : applicationsClose(),
      info: info ?? this.info,
      paymentMode: paymentMode ?? this.paymentMode,
      ticketCost: ticketCost == null ? this.ticketCost : ticketCost(),
      spacesAvailable: spacesAvailable == null
          ? this.spacesAvailable
          : spacesAvailable(),
      secretCode: secretCode ?? this.secretCode,
    );
  }

  factory TraderCategory.fromJson(Map<String, dynamic> json) {
    return TraderCategory(
      id: _str(json['id']).isEmpty ? newEditorId('trader') : _str(json['id']),
      name: _str(json['name']),
      icon: traderIconFromName(_str(json['icon'])),
      applicationsOpen: _parseDate(json['applications_open']),
      applicationsClose: _parseDate(json['applications_close']),
      info: _str(json['info']),
      paymentMode: _str(json['payment_mode']) == 'in_person'
          ? TraderPaymentMode.inPerson
          : TraderPaymentMode.online,
      ticketCost: _double(json['ticket_cost']),
      spacesAvailable: _int(json['spaces_available']),
      secretCode: _str(json['secret_code']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon.name,
    'applications_open': _isoDate(applicationsOpen),
    'applications_close': _isoDate(applicationsClose),
    'info': info,
    'payment_mode': paymentMode.wireValue,
    'ticket_cost': ticketCost,
    'spaces_available': spacesAvailable,
    'secret_code': secretCode,
  };
}

class TradersConfig {
  final bool enabled;
  final List<TraderCategory> categories;

  const TradersConfig({this.enabled = false, this.categories = const []});

  TradersConfig copyWith({bool? enabled, List<TraderCategory>? categories}) {
    return TradersConfig(
      enabled: enabled ?? this.enabled,
      categories: categories ?? this.categories,
    );
  }

  /// Reads the `traders` block from `dl-accounts/v1/event-edit`.
  factory TradersConfig.fromJson(Map<String, dynamic> json) {
    return TradersConfig(
      enabled: _bool(json['enabled']),
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TraderCategory.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'categories': categories.map((c) => c.toJson()).toList(),
  };
}

/// The four sections together — what the editor holds and what the save call
/// will eventually send.
class EventExtrasDraft {
  final List<EventDiscount> discounts;
  final ShowCarsConfig showCars;
  final CarClubsConfig carClubs;
  final TradersConfig traders;

  const EventExtrasDraft({
    this.discounts = const [],
    this.showCars = const ShowCarsConfig(),
    this.carClubs = const CarClubsConfig(),
    this.traders = const TradersConfig(),
  });

  EventExtrasDraft copyWith({
    List<EventDiscount>? discounts,
    ShowCarsConfig? showCars,
    CarClubsConfig? carClubs,
    TradersConfig? traders,
  }) {
    return EventExtrasDraft(
      discounts: discounts ?? this.discounts,
      showCars: showCars ?? this.showCars,
      carClubs: carClubs ?? this.carClubs,
      traders: traders ?? this.traders,
    );
  }

  factory EventExtrasDraft.fromJson(Map<String, dynamic> json) {
    return EventExtrasDraft(
      discounts: (json['discounts'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EventDiscount.fromJson)
          .toList(),
      showCars: ShowCarsConfig.fromJson(
        json['show_cars'] as Map<String, dynamic>? ?? const {},
      ),
      carClubs: CarClubsConfig.fromJson(
        json['car_clubs'] as Map<String, dynamic>? ?? const {},
      ),
      traders: TradersConfig.fromJson(
        json['traders'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'discounts': discounts.map((d) => d.toJson()).toList(),
    'show_cars': showCars.toJson(),
    'car_clubs': carClubs.toJson(),
    'traders': traders.toJson(),
  };
}
