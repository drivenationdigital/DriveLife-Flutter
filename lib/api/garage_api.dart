import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GarageAPI {
  static const String _apiUrl = 'https://www.carevents.com/uk';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // Match your JS TIMEOUT_MS_HIGH (adjust if you already have this elsewhere)
  static const Duration _timeoutHigh = Duration(seconds: 30);

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

  static Future<dynamic> addVehicleToGarage(
    Map<String, dynamic> data,
    String userId,
  ) async {
    final uri = Uri.parse('$_apiUrl/wp-json/app/v1/add-vehicle-to-garage');

    try {
      final body = <String, dynamic>{...data, 'user_id': userId};
      print(body);

      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      // JS returns parsed json no matter what
      final responseData = jsonDecode(response.body);
      print(responseData);
      return responseData;
    } on TimeoutException {
      // match JS TimeOutError shape
      throw {
        'message': 'Failed to add your vehicle, your connection timed out',
        'name': 'TimeOutError',
      };
    } catch (e) {
      print('Error adding vehicle to garage: $e');
      rethrow;
    }
  }

  // ADD TO garage_api.dart

  static Future<Map<String, dynamic>?> updateVehicle(
    String vehicleId,
    Map<String, dynamic> payload,
    String userId,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('${_apiUrl}/wp-json/app/v1/garage/$vehicleId'),
        headers: const {'Content-Type': 'application/json'},
        body: json.encode({...payload, 'user_id': userId}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error updating vehicle: $e');
      return null;
    }
  }

  // ADD TO garage_api.dart
  static Future<Map<String, dynamic>?> deleteVehicle(
    String garageId,
    String userId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${_apiUrl}/wp-json/app/v1/delete-garage'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_id': userId, 'garage_id': garageId}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error deleting vehicle: $e');
      return null;
    }
  }

  // ADD TO garage_api.dart

  static Future<Map<String, dynamic>?> addVehicleMod(
    Map<String, dynamic> payload,
    String userId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${_apiUrl}/wp-json/app/v2/add-vehicle-mod'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({...payload, 'user_id': userId}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error adding vehicle mod: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> updateVehicleMod(
    Map<String, dynamic> payload,
    String modId,
    String userId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${_apiUrl}/wp-json/app/v2/update-vehicle-mod'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({...payload, 'mod_id': modId, 'user_id': userId}),
      );

      final data = json.decode(response.body);
      print(data);
      if (response.statusCode == 200) {
        return data;
      }
      return null;
    } catch (e) {
      print('Error updating vehicle mod: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> deleteVehicleMod(
    String modId,
    String userId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${_apiUrl}/wp-json/app/v2/delete-vehicle-mod'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'mod_id': modId, 'user_id': userId}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error deleting vehicle mod: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getModById(String modId) async {
    try {
      final response = await http.get(
        Uri.parse('${_apiUrl}/wp-json/app/v2/get-vehicle-mod?mod_id=$modId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error getting mod: $e');
      return null;
    }
  }
}
