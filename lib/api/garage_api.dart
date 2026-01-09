import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GarageAPI {
  static const String _apiUrl = 'https://www.carevents.com/uk';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<List<dynamic>?> getUserGarage(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/wp-json/app/v2/get-user-garage?user_id=$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
      return [];
    } catch (e) {
      print('Error fetching garage: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getGarageById(String garageId) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/wp-json/app/v2/get-garage?garage_id=$garageId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Error fetching garage by id: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getPostsForGarage(
    String garageId, {
    int page = 1,
    bool tagged = false,
  }) async {
    try {
      final uri = Uri.parse('$_apiUrl/wp-json/app/v2/get-garage-posts').replace(
        queryParameters: {
          'garage_id': garageId,
          'page': page.toString(),
          'limit': '9',
          'tagged': tagged ? '1' : '0',
        },
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Error fetching garage posts: $e');
      return null;
    }
  }

  static Future<List<dynamic>?> getVehicleMods(String garageId) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/wp-json/app/v2/get-vehicle-mods?garage_id=$garageId',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // ✅ Extract 'mods' array from response
        return data['mods'] as List<dynamic>;
      }
      return null;
    } catch (e) {
      print('Error fetching vehicle mods: $e');
      return null;
    }
  }
}
