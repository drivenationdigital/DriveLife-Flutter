import 'dart:convert';
import 'package:http/http.dart' as http;

class OrderApiService {
  static const String baseUrl = 'https://www.drive-life.com';

  // Create order with optional billing details
  static Future<Map<String, dynamic>> createOrderV2({
    required int userId,
    required String paymentIntentId,
    required String shippingMethod,
    Map<String, dynamic>? billingDetails, // Optional
  }) async {
    try {
      final body = {
        'user_id': userId,
        'payment_intent_id': paymentIntentId,
        'shipping_method': shippingMethod,
      };

      if (billingDetails != null) {
        body['billing'] = billingDetails;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/wp-json/app-store/v2/create-order'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == false) {
          throw Exception(data['message']);
        }
        return data['data'];
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error creating order: $e');
    }
  }

  // Get all orders for a user
  static Future<Map<String, dynamic>> getUserOrders({
    required int userId,
    int page = 1,
    int perPage = 20,
    String? status,
  }) async {
    try {
      final queryParams = {
        'user_id': userId.toString(),
        'page': page.toString(),
        'per_page': perPage.toString(),
      };

      if (status != null) {
        queryParams['status'] = status;
      }

      final uri = Uri.parse(
        '$baseUrl/wp-json/app-store/v1/orders',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load orders: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching orders: $e');
    }
  }

  // Get single order by ID
  static Future<Map<String, dynamic>> getOrderById({
    required int orderId,
    int? userId, // Optional for verification
  }) async {
    try {
      final queryParams = userId != null
          ? {'user_id': userId.toString()}
          : <String, String>{};

      final uri = Uri.parse(
        '$baseUrl/wp-json/app-store/v1/orders/$orderId',
      ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Order#$orderId not found');
      } else if (response.statusCode == 403) {
        throw Exception('Unauthorized access');
      } else {
        throw Exception('Failed to load order: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching order: $e');
    }
  }
}
