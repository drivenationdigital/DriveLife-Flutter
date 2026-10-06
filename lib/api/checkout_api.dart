import 'dart:async';
import 'dart:convert';

import 'package:drivelife/config/app_environment.dart';
import 'package:flutter/foundation.dart';
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
  ///
  /// Follows the app's environment: the checkout proxy talks to whichever
  /// WordPress it was deployed against, so a staging app must use the staging
  /// accounts app or its event ids and cart tokens will not match.
  static String get baseUrl => AppEnvironment.accountsBase;

  /// Where a buyer is sent to finish paying.
  ///
  /// A vanity host pointed at the same application: `checkout.carevents.com`
  /// rewrites `/<eventEid>` internally to `/get-tickets/<eventEid>`, so the
  /// buyer sees a short payments-branded URL rather than the dashboard's.
  ///
  /// Staging has no such subdomain and uses the real path instead; either way
  /// the event id is appended to this.
  static String get checkoutBaseUrl => AppEnvironment.checkoutLinkBase;

  static const Duration _timeout = Duration(seconds: 25);

  /// Prints a checkout call, in any build a developer is running.
  ///
  /// The buyer-facing messages are deliberately vague — "Ticketing service
  /// error (HTTP 500)" reads the same for a misconfigured blog as for a
  /// declined card — so without this there is nothing to debug from. That is
  /// not hypothetical: a production-only `createIntent` failure (2026-10-05)
  /// took days to place because a debug build pointed at production printed
  /// nothing at all.
  ///
  /// So: on for staging and for every debug build, including a debug build
  /// pointed at production, which is exactly when a production-only failure
  /// has to be diagnosed. Off in release, where these payloads would carry a
  /// real buyer's name, email and phone — which is what the original
  /// staging-only gate was protecting, and still is.
  static void _log(String message) {
    if (!AppEnvironment.isStaging && !kDebugMode) return;
    debugPrint('🎟️ [Checkout] $message');
  }

  /// A JSON object from the PHP, whatever shape "empty" arrived in.
  ///
  /// PHP has one array type and json_encode writes an empty one as `[]`, not
  /// `{}`. So any map the backend can send empty — a cleared cart, a cart
  /// with no coupons, totals that have not been computed — arrives as a LIST
  /// and a straight cast throws. Removing the last ticket crashed on exactly
  /// this.
  static Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? value.cast<String, dynamic>() : const {};

  static Future<Map<String, dynamic>> _action(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    http.Response response;

    _log('→ $action');

    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/checkout'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'action': action, ...payload}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      _log('✖ $action timed out after ${_timeout.inSeconds}s');
      throw const CheckoutException(
        'The ticketing service took too long to respond. Please try again.',
      );
    } catch (e) {
      _log('✖ $action could not reach $baseUrl: $e');
      throw const CheckoutException(
        "Couldn't reach the ticketing service. Please check your connection "
        'and try again.',
      );
    }

    // Truncated: a ticket list or a cart dump drowns the console and the
    // useful part of an error is always at the front.
    final preview = response.body.length > 900
        ? '${response.body.substring(0, 900)}…'
        : response.body;

    _log('← $action HTTP ${response.statusCode} $preview');

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
  static Future<CheckoutInfo> info(String eventEid) async {
    final info = CheckoutInfo.fromJson(
      await _action('info', {'eventEid': eventEid}),
    );

    // Said plainly, because the raw reply cannot show it: this event's terms
    // and conditions run to thousands of characters and push `providers` and
    // `stripe` past the truncation long before they are reached.
    //
    // Which methods an event offers, and whose Stripe account it would charge,
    // is the first thing to know when a checkout behaves unexpectedly.
    final stripe = info.stripe;

    _log(
      'info: providers=${info.providerIds.join(',')} '
      'stripeKey=${stripe.key.isEmpty ? 'MISSING' : '${stripe.key.substring(0, stripe.key.length.clamp(0, 11))}…'} '
      'stripeAccount=${stripe.account ?? 'NONE (platform account)'} '
      'site=${info.event.site} currency=${info.event.currency}',
    );

    return info;
  }

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

    return CartTotals.fromJson(_asMap(body['totals']));
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

    final coupon = body['coupon'] is Map ? _asMap(body['coupon']) : null;

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

  /// Takes one admission back out of the cart.
  ///
  /// Per unit, not per line: removing "one of the three" is the thing a buyer
  /// actually wants. Returns the cart as it now stands, and whether that
  /// emptied it — an empty cart has nothing left to pay for, so the caller
  /// sends them back to the ticket list rather than to an order of nothing.
  static Future<({Map<String, dynamic> lines, bool isEmpty})> removeUnit(
    String cartToken,
    String ticketId,
    int metaIndex,
  ) async {
    final body = await _action('removeUnit', {
      'cartToken': cartToken,
      'ticketId': ticketId,
      'metaIndex': metaIndex,
    });

    return (
      lines: _asMap(body['cart_data']),
      isEmpty: body['cart_empty'] == true,
    );
  }

  /// Opens a PayPal order sized to the cart.
  ///
  /// The amount is never sent: the PHP prices the cart itself and rejects
  /// anything that no longer matches. All that comes back is PayPal's order
  /// id, which is what the buyer approves and what the capture then charges.
  ///
  /// [returnUrl] and [cancelUrl] are where PayPal sends the buyer afterwards.
  /// The website omits them because its JS popup calls back in the page; the
  /// app has no popup, so they are how the buyer gets back here.
  static Future<({String orderId, Uri approveUrl, double total})> paypalCreate(
    String cartToken,
    String eventEid,
    String site, {
    required String returnUrl,
    required String cancelUrl,
  }) async {
    final body = await _action('paypalCreate', {
      'cartToken': cartToken,
      'eventEid': eventEid,
      'site': site,
      'returnUrl': returnUrl,
      'cancelUrl': cancelUrl,
    });

    final orderId = '${body['orderId'] ?? ''}';

    if (orderId.isEmpty) {
      throw const CheckoutException(
        "We couldn't start the PayPal payment. Please try again.",
      );
    }

    // PayPal's own approval link wherever it gave one. Assembling the URL
    // from the order id means choosing a host, and choosing wrong — sandbox
    // order, live checkout — shows the buyer a bare "Something went wrong".
    final given = '${body['approveUrl'] ?? ''}'.trim();

    final host = '${body['environment'] ?? ''}' == 'live'
        ? 'https://www.paypal.com'
        : 'https://www.sandbox.paypal.com';

    final approveUrl = given.isNotEmpty
        ? Uri.parse(given)
        : Uri.parse('$host/checkoutnow?token=$orderId');

    return (
      orderId: orderId,
      approveUrl: approveUrl,
      total: double.tryParse('${body['total'] ?? 0}') ?? 0,
    );
  }

  /// Captures the order the buyer approved at PayPal.
  ///
  /// Server-side, against the charge PayPal actually recorded — the app only
  /// ever carries the order id, never an amount. Comes back in Stripe's
  /// vocabulary so the completion path is the same whichever method was used.
  static Future<({String transactionId, String paymentStatus})> paypalCapture(
    String cartToken,
    String eventEid,
    String paypalOrderId,
    String site,
  ) async {
    final body = await _action('paypalCapture', {
      'cartToken': cartToken,
      'eventEid': eventEid,
      'paypalOrderId': paypalOrderId,
      'site': site,
    });

    return (
      transactionId: '${body['transactionId'] ?? ''}',
      paymentStatus: '${body['paymentStatus'] ?? ''}',
    );
  }

  /// Opens a Mollie payment and returns where to send the buyer.
  ///
  /// Mollie is the one provider with no mobile SDK, deliberately: the buyer
  /// finishes on Mollie's own hosted page and goes from there into their
  /// banking app for 3-D Secure. So this hands back a URL rather than
  /// something to confirm in the app, and [returnUrl] is the `drivelife://`
  /// link that brings them back.
  ///
  /// [form] is the order form, stashed on the cart server-side. Mollie
  /// confirms by webhook as well as by return, so if the buyer never comes
  /// back — app killed, browser closed after paying — the webhook can still
  /// complete their order with the same details they typed.
  static Future<
    ({
      String paymentId,
      Uri? checkoutUrl,
      String paymentStatus,
      String transactionId,
      double total,
    })
  >
  mollieCreate(
    String cartToken,
    String eventEid,
    String site, {
    required String returnUrl,
    required Map<String, String> form,
  }) async {
    final body = await _action('mollieCreate', {
      'cartToken': cartToken,
      'eventEid': eventEid,
      'site': site,
      'returnUrl': returnUrl,
      'form': form,
    });

    final paymentId = '${body['paymentId'] ?? ''}'.trim();

    if (paymentId.isEmpty) {
      throw const CheckoutException(
        "We couldn't start the Mollie payment. Please try again.",
      );
    }

    final url = '${body['checkoutUrl'] ?? ''}'.trim();

    return (
      paymentId: paymentId,
      // Absent when the payment settled outright with no 3-D Secure, which
      // leaves nowhere to send the buyer and nothing to send them for.
      checkoutUrl: url.isEmpty ? null : Uri.tryParse(url),
      paymentStatus: '${body['paymentStatus'] ?? ''}'.trim(),
      transactionId: '${body['transactionId'] ?? ''}'.trim(),
      total: double.tryParse('${body['total'] ?? 0}') ?? 0,
    );
  }

  /// Reads Mollie's verdict on a payment the buyer has come back from.
  ///
  /// The verdict is Mollie's, never the return itself: a buyer can close
  /// Mollie's page and open the return link by hand, so coming back proves
  /// nothing. The PHP checks the payment belongs to this cart and is for the
  /// right amount before answering.
  ///
  /// [orderCompleted] means the webhook finished the order first — common,
  /// since Mollie calls it the moment the payment clears, which can beat the
  /// buyer's own redirect. The order is already there, so it must not be
  /// saved a second time.
  static Future<
    ({
      String transactionId,
      String paymentStatus,
      bool orderCompleted,
      String orderId,
      String? orderNumber,
    })
  >
  mollieStatus(
    String cartToken,
    String eventEid,
    String paymentId,
    String site,
  ) async {
    final body = await _action('mollieStatus', {
      'cartToken': cartToken,
      'eventEid': eventEid,
      'paymentId': paymentId,
      'site': site,
    });

    final number = '${body['orderNumber'] ?? ''}'.trim();

    return (
      transactionId: '${body['transactionId'] ?? ''}'.trim(),
      paymentStatus: '${body['paymentStatus'] ?? ''}'.trim(),
      orderCompleted: body['orderCompleted'] == true,
      orderId: '${body['orderId'] ?? ''}'.trim(),
      orderNumber: number.isEmpty ? null : number,
    );
  }

  /// Charges a Square card token.
  ///
  /// [sourceId] is the single-use nonce the In-App Payments SDK produces;
  /// [verificationToken] is the SCA result from its buyer-verification flow.
  /// Square requires the latter for UK/EEA cards and ignores it elsewhere, so
  /// it is always sent when there is one.
  ///
  /// No amount travels: the PHP prices the cart and charges the organiser's
  /// own Square account.
  static Future<({String transactionId, String paymentStatus})> squarePay(
    String cartToken,
    String eventEid,
    String sourceId,
    String verificationToken,
    String site,
  ) async {
    final body = await _action('squarePay', {
      'cartToken': cartToken,
      'eventEid': eventEid,
      'sourceId': sourceId,
      'verificationToken': verificationToken,
      'site': site,
    });

    return (
      transactionId: '${body['transactionId'] ?? ''}',
      paymentStatus: '${body['paymentStatus'] ?? ''}',
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

    /// Which gateway [paymentIntentId] came from. For PayPal the backend
    /// re-checks it against the charge it recorded when it captured, and
    /// takes the status from there rather than from us.
    String provider = 'stripe',
  }) async {
    final body = await _action('saveOrder', {
      'cartToken': cartToken,
      'eventEid': eventEid,
      'paymentIntentId': paymentIntentId,
      'paymentStatus': paymentStatus,
      'form': form,
      'boxOffice': false,
      'provider': provider,
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
