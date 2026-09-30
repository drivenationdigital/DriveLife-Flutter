import 'dart:async';
import 'dart:convert';

import 'package:drivelife/models/checkout_models.dart';
import 'package:http/http.dart' as http;

/// Something the checkout refused to do, in words a buyer can read.
///
/// The backend's messages are written for buyers — "This event allows a
/// maximum of 6 items per order" — so they are shown as they arrive rather
/// than replaced with something generic.
class CheckoutException implements Exception {
  final String message;

  /// Whatever else came back with the error. `maxqty` responses carry
  /// `max_qty` and `current_qty`, for instance.
  final Map<String, dynamic> extra;

  const CheckoutException(this.message, [this.extra = const {}]);

  @override
  String toString() => message;
}

/// The ticket checkout's API.
///
/// One endpoint: `POST /api/checkout` with `{action, ...payload}`. It is the
/// Next.js checkout's own proxy, which is what turns the legacy PHP ticketing
/// endpoints — no CORS, text/html replies, positional arrays — into uniform
/// JSON. Going straight to the PHP would mean reimplementing that translation
/// here and keeping the two in step forever.
///
/// Anonymous by design: buyers need no account, so nothing here sends the
/// app's bearer token. Money is never computed on this side — the PHP prices
/// every cart itself and rejects anything that no longer matches.
class CheckoutApi {
  const CheckoutApi._();

  /// The account app, which serves the checkout proxy.
  ///
  /// `checkout.carevents.com` reaches the same route, but that host rewrites
  /// its top-level paths to `/get-tickets/...`; the API is cleaner from the
  /// canonical origin.
  static const String baseUrl = 'https://account.carevents.com';

  /// Where a buyer is sent to finish paying.
  ///
  /// A vanity host pointed at the same application: checkout.carevents.com/
  /// <eventEid> rewrites internally to /get-tickets/<eventEid>, so the buyer
  /// sees a short payments-branded URL rather than the account dashboard's.
  static const String checkoutBaseUrl = 'https://checkout.carevents.com';

  static const Duration _timeout = Duration(seconds: 25);

  static Future<Map<String, dynamic>> _action(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    http.Response response;

    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/checkout'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'action': action, ...payload}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const CheckoutException(
        'The ticketing service took too long to respond. Please try again.',
      );
    } catch (_) {
      throw const CheckoutException(
        "Couldn't reach the ticketing service. Please check your connection "
        'and try again.',
      );
    }

    Map<String, dynamic>? body;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = decoded.cast<String, dynamic>();
    } catch (_) {
      body = null;
    }

    if (body == null) {
      throw const CheckoutException(
        'Unexpected response from the ticketing service.',
      );
    }

    if (body['status'] == 'error') {
      final extra = Map<String, dynamic>.from(body)
        ..remove('status')
        ..remove('message');

      throw CheckoutException(
        '${body['message'] ?? 'Something went wrong.'}',
        extra,
      );
    }

    return body;
  }

  /// The event, its VAT display setting and the methods it accepts.
  static Future<CheckoutInfo> info(String eventEid) async =>
      CheckoutInfo.fromJson(await _action('info', {'eventEid': eventEid}));

  /// The ticket list.
  ///
  /// [code] reveals secret tickets and [coupon] reprices the rows, so both
  /// change what comes back — a cached list from before either was entered is
  /// the wrong list.
  static Future<List<CheckoutTicket>> tickets(
    String eventEid, {
    String cartToken = '',
    String code = '',
    String coupon = '',
    String cname = '',
  }) async {
    final body = await _action('tickets', {
      'eventEid': eventEid,
      'cartToken': cartToken,
      'code': code,
      'coupon': coupon,
      'cname': cname,
    });

    return ((body['tickets'] as List?) ?? const [])
        .whereType<Map>()
        .map((t) => CheckoutTicket.fromJson(t.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Opens a cart. Nothing is held until tickets are added and reserved.
  static Future<String> createCart(String eventEid) async {
    final body = await _action('createCart', {'eventEid': eventEid});
    return '${body['cartToken'] ?? ''}';
  }

  static Future<bool> verifyCart(String cartToken) async {
    final body = await _action('verifyCart', {'cartToken': cartToken});
    return body['valid'] == true;
  }

  /// Puts the chosen quantities in the cart.
  ///
  /// Returns the server's line items. A refusal on the per-order cap comes
  /// back as a normal response with `status: 'maxqty'`, not an error, so the
  /// caller has to look — treating it as success adds nothing to the cart and
  /// says nothing about why.
  static Future<Map<String, dynamic>> addToBasket(
    String eventEid,
    String cartToken,
    List<({String pid, int qty})> items, {
    String coupon = '',
  }) async {
    return _action('addToBasket', {
      'eventEid': eventEid,
      'cartToken': cartToken,
      'items': [
        for (final item in items) {'pid': item.pid, 'qty': item.qty},
      ],
      'coupon': coupon,
    });
  }

  /// Holds the stock. Throws when it can no longer be held.
  static Future<void> reserve(String cartToken) =>
      _action('reserve', {'cartToken': cartToken});

  /// What the server says the cart comes to.
  static Future<CartTotals> totals(String cartToken) async {
    final body = await _action('totals', {'cartToken': cartToken});

    return CartTotals.fromJson(
      (body['totals'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  /// Validates a discount code without committing to it.
  ///
  /// Returns null when the server accepted the request but found no coupon.
  /// A code that is wrong, expired or not for this event comes back as a
  /// [CheckoutException] carrying the server's own explanation, which is
  /// written for buyers and better than anything this layer could invent.
  ///
  /// Validating is not applying: the code is only put on the cart during
  /// add-to-basket, which is where it can still be rejected for covering none
  /// of the chosen tickets.
  static Future<CheckoutCoupon?> checkCoupon(
    String eventEid,
    String cartToken,
    String code,
  ) async {
    final body = await _action('applyCoupon', {
      'cartToken': cartToken,
      'code': code,
      'preCheckout': true,
      'eventEid': eventEid,
      'email': '',
    });

    final coupon = (body['coupon'] as Map?)?.cast<String, dynamic>();

    if (coupon == null) {
      final message = '${body['message'] ?? ''}'.trim();
      if (message.isNotEmpty) throw CheckoutException(message);
      return null;
    }

    return CheckoutCoupon.fromJson(coupon);
  }

  /// Checks a secret code, which unlocks hidden tickets.
  ///
  /// Returning normally is the whole of "accepted" — the endpoint answers with
  /// the PHP's own payload and signals a bad code as an error, which arrives
  /// here as a [CheckoutException] with the reason.
  ///
  /// The ticket list has to be fetched again afterwards with the same code:
  /// the tickets it reveals are not in the list that was already loaded.
  static Future<void> checkSecretCode(
    String eventEid,
    String cartToken,
    String code,
  ) => _action('checkSecret', {
    'cartToken': cartToken,
    'code': code,
    'eventEid': eventEid,
  });

  /// Saves the buyer's own details against the cart.
  static Future<void> saveBilling(
    String cartToken,
    Map<String, String> fields,
  ) => _action('saveBilling', {'cartToken': cartToken, 'fields': fields});

  /// Saves the display-board details, for events that ask for them.
  static Future<void> saveAttendee(
    String cartToken,
    Map<String, String> fields,
  ) => _action('saveAttendee', {'cartToken': cartToken, 'fields': fields});

  /// Saves one field on one ticket in the cart.
  ///
  /// Per unit, not per line: two tickets of the same kind are two people, and
  /// [metaIndex] is which of them this is.
  static Future<void> updateMeta(
    String cartToken,
    String ticketId,
    String field,
    String value,
    int metaIndex,
  ) => _action('updateMeta', {
    'cartToken': cartToken,
    'ticketId': ticketId,
    'field': field,
    'value': value,
    'metaIndex': metaIndex,
  });

  /// Opens a Stripe PaymentIntent for the cart, priced server-side.
  ///
  /// Returns the client secret and the amount Stripe will actually take. The
  /// app never sends an amount and never computes one — the PHP prices the
  /// cart and rejects anything that no longer matches.
  static Future<({String clientSecret, double total})> createIntent(
    String cartToken,
    String eventEid,
    String site,
  ) async {
    final body = await _action('createIntent', {
      'cartToken': cartToken,
      'eventEid': eventEid,
      'site': site,
    });

    final secret = '${body['clientSecret'] ?? ''}';

    if (secret.isEmpty) {
      throw const CheckoutException(
        "We couldn't start the payment. Please try again.",
      );
    }

    return (
      clientSecret: secret,
      total: double.tryParse('${body['total'] ?? 0}') ?? 0,
    );
  }

  /// Writes the order.
  ///
  /// Called twice in a normal purchase. Once with `pending` and no
  /// transaction, before any money moves, so the PaymentIntent and the order
  /// row can reference each other; then again once Stripe reports a result.
  /// The classic checkout does the same, and skipping the first call leaves a
  /// paid intent with no order behind it.
  static Future<({String orderId, String? orderNumber})> saveOrder(
    String cartToken,
    String eventEid, {
    String paymentIntentId = '',
    required String paymentStatus,
    required Map<String, String> form,
  }) async {
    final body = await _action('saveOrder', {
      'cartToken': cartToken,
      'eventEid': eventEid,
      'paymentIntentId': paymentIntentId,
      'paymentStatus': paymentStatus,
      'form': form,
      'boxOffice': false,
      'provider': 'stripe',
    });

    return (
      orderId: '${body['order_id'] ?? ''}',
      orderNumber: body['order_number'] == null
          ? null
          : '${body['order_number']}',
    );
  }

  /// Uploads one vehicle photo and returns its public URL.
  ///
  /// Two steps, the same as every other direct upload in the app: mint a
  /// one-time Cloudflare URL through the proxy, then send the bytes straight
  /// to Cloudflare. The file never passes through the ticketing backend, and
  /// what ends up in the cart is only the delivery URL.
  static Future<String> uploadVehiclePhoto(
    String eventEid,
    String filePath,
  ) async {
    final mint = await _action('mintPhotoUpload', {'eventEid': eventEid});
    final uploadUrl = '${mint['upload_url'] ?? ''}';

    if (uploadUrl.isEmpty) {
      throw const CheckoutException("Couldn't start the photo upload.");
    }

    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl))
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw CheckoutException(
        'Photo upload failed (HTTP ${streamed.statusCode}).',
      );
    }

    final decoded = jsonDecode(body);
    final variants = <String>[
      if (decoded is Map)
        ...(((decoded['result'] as Map?)?['variants'] as List?) ?? const [])
            .whereType<String>(),
    ];

    if (variants.isEmpty) {
      throw const CheckoutException(
        'The photo uploaded but no image URL came back.',
      );
    }

    // Cloudflare returns one URL per configured variant in no guaranteed
    // order, and one of them is a blurred placeholder. Ask for "public" by
    // name rather than taking the first.
    return variants.firstWhere(
      (v) => v.endsWith('/public'),
      orElse: () => variants.firstWhere(
        (v) => !v.endsWith('/blurred'),
        orElse: () => variants.first,
      ),
    );
  }

  /// Empties the cart and releases anything it was holding.
  ///
  /// Called when a buyer walks away. Best-effort on purpose: there is nothing
  /// useful to tell someone who has already left, and the reservation expires
  /// on its own regardless.
  static Future<void> clearCart(String cartToken) async {
    try {
      await _action('clearCart', {'cartToken': cartToken});
    } catch (_) {
      // The 60-minute reservation lapses by itself.
    }
  }
}
