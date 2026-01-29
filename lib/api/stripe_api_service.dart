import 'dart:convert';
import 'package:http/http.dart' as http;

class StripeApiService {
  static const String baseUrl =
      'https://www.drive-life.com'; // Replace with your WordPress URL

  /// Create Payment Intent V2
  /// Returns: {paymentIntentId, clientSecret, customer, ephemeralKey}
  static Future<Map<String, dynamic>> createPaymentIntentV2({
    required int userId, // From your app, not WordPress
    required int amount, // In pence/cents
    required String currency,
    required String customerEmail,
    required String customerName,
    required String shippingMethod,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/wp-json/app-store/v2/create-payment-intent',
      );

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId, // ✅ From app user provider
          'amount': amount,
          'currency': currency,
          'customer_email': customerEmail,
          'customer_name': customerName,
          'shipping_method': shippingMethod,
          'items': items,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == false) {
          throw Exception(data['message'] ?? 'Failed to create payment intent');
        }

        return data['data'];
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating payment intent: $e');
    }
  }

  /// Create Order V2 (after successful Stripe payment)
  /// Returns: {orderId, orderNumber, orderKey, total}
  static Future<Map<String, dynamic>> createOrderV2({
    required int userId, // From your app
    required String paymentIntentId,
    required String shippingMethod,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/wp-json/app-store/v2/create-order');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId, // ✅ From app user provider
          'payment_intent_id': paymentIntentId,
          'shipping_method': shippingMethod,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == false) {
          throw Exception(data['message'] ?? 'Failed to create order');
        }

        return data['data'];
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating order: $e');
    }
  }

  /// Cancel Payment Intent V2
  static Future<void> cancelPaymentIntentV2(String intentId) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/wp-json/app-store/v2/cancel-payment-intent',
      );

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'intent_id': intentId}),
      );

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Failed to cancel payment');
      }
    } catch (e) {
      throw Exception('Error canceling payment: $e');
    }
  }

  /// Create Setup Intent V2 (for saving cards)
  static Future<String> createSetupIntentV2({
    required int userId,
    required String email,
    required String name,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/wp-json/app-store/v2/create-setup-intent',
      );

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'email': email, 'name': name}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == false) {
          throw Exception(data['message'] ?? 'Failed to create setup intent');
        }

        return data['data']['clientSecret'];
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating setup intent: $e');
    }
  }

  /// Delete Payment Method V2
  static Future<void> deletePaymentMethodV2(String paymentMethodId) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/wp-json/app-store/v2/delete-payment-method',
      );

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'payment_method_id': paymentMethodId}),
      );

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Failed to delete payment method');
      }
    } catch (e) {
      throw Exception('Error deleting payment method: $e');
    }
  }
}
