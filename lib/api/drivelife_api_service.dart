import 'dart:convert';
import 'package:drivelife/models/banner_model.dart';
import 'package:drivelife/models/product_model.dart';
import 'package:http/http.dart' as http;

class DriveLifeApiService {
  static const String baseUrl = 'https://www.drive-life.com';

  // Get featured products
  static Future<ProductsResponse> getFeaturedProducts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/wp-json/app-store/v2/get-featured-products'),
        headers: {'Content-Type': 'application/json'},
      );

      final json = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ProductsResponse.fromJson(json);
      } else {
        throw Exception(
          'Failed to load featured products: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching featured products: $e');
    }
  }

  // Get products by category
  static Future<ProductsResponse> getProductsByCategory({
    required String categorySlug,
    int page = 1,
    int perPage = 12,
  }) async {
    try {
      final queryParams = {
        'category': categorySlug,
        'page': page.toString(),
        'per_page': perPage.toString(),
      };

      final uri = Uri.parse(
        '$baseUrl/wp-json/app-store/v2/get-products-by-category',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      final json = jsonDecode(response.body);
      print(json);

      if (response.statusCode == 200) {
        if (json['success'] == false) {
          throw Exception(json['message'] ?? 'Category not found');
        }

        return ProductsResponse.fromJson(json);
      } else {
        throw Exception('Failed to load products: ${response.statusCode}');
      }
    } catch (e) {
      print(e);
      throw Exception('Error fetching products by category: $e');
    }
  }

  // Get single product by ID
  static Future<ProductsResponse> getProductById(int productId) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/wp-json/app-store/v2/get-product',
      ).replace(queryParameters: {'id': productId.toString()});

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      final json = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (json['success'] == false) {
          throw Exception(json['message'] ?? 'Product not found');
        }

        return ProductsResponse.fromJson(json);
      } else {
        throw Exception('Failed to load product: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching product: $e');
    }
  }

  // Get banners
  static Future<ProductsBannersResponse> getBanners() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/wp-json/app-store/v2/get-banners'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ProductsBannersResponse.fromJson(json);
      } else {
        throw Exception('Failed to load banners: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching banners: $e');
    }
  }

  // Search products (if you want to add search later)
  static Future<ProductsResponse> searchProducts({
    required String query,
    int page = 1,
    int perPage = 12,
  }) async {
    try {
      final queryParams = {
        'search': query,
        'page': page.toString(),
        'per_page': perPage.toString(),
      };

      final uri = Uri.parse(
        '$baseUrl/wp-json/app-store/v2/search-products',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ProductsResponse.fromJson(json);
      } else {
        throw Exception('Failed to search products: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching products: $e');
    }
  }

  // Get product categories
  static Future<List<CategoryInfo>> getProductCategories() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/wp-json/app-store/v2/get-categories'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as List<dynamic>;
        return json
            .map((e) => CategoryInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to load categories: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching categories: $e');
    }
  }

  static Future<Map<String, dynamic>> createPaymentIntent({
    required int amount,
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
        throw Exception(
          'Failed to create payment intent: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Error creating payment intent: $e');
    }
  }

  /// Create Order after successful payment
  static Future<Map<String, dynamic>> createOrder({
    required String paymentIntentId,
    required String shippingMethod,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/wp-json/app-store/v2/create-order');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
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
        throw Exception('Failed to create order: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error creating order: $e');
    }
  }
}
