import 'dart:async';
import 'dart:convert';
import 'package:drivelife/utils/chunk_upload_utility.dart';
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

  static Future<dynamic> addVehicleToGaragelegacy(
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

  static Future<Map<String, dynamic>?> updateVehiclelegacy(
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

  static Future<dynamic> addVehicleToGarage(
    Map<String, dynamic> data,
    String userId, {
    Function(int current, int total, double percentage)? onUploadProgress,
  }) async {
    try {
      // Extract cover photo if present
      final coverPhoto = data['cover_photo'];
      String? coverPhotoUrl;

      // If cover photo is provided, upload it in chunks first
      if (coverPhoto != null && coverPhoto.isNotEmpty) {
        print('Uploading cover photo in chunks...');

        coverPhotoUrl = await ChunkUploadUtility.uploadAndGetUrl(
          base64Image: coverPhoto,
          userId: int.parse(userId),
          type: 'garage',
          onProgress: onUploadProgress,
        );

        if (coverPhotoUrl == null) {
          throw Exception('Failed to upload cover photo');
        }

        print('Cover photo uploaded successfully: $coverPhotoUrl');
      }

      // Prepare the request body
      final body = <String, dynamic>{...data, 'user_id': userId};

      // Replace base64 cover_photo with the uploaded URL
      if (coverPhotoUrl != null) {
        body['cover_photo'] = coverPhotoUrl;
        body['use_uploaded_url'] =
            true; // Flag to tell backend to use URL directly
      }

      print('Adding vehicle to garage...');
      print(body);

      final uri = Uri.parse('$_apiUrl/wp-json/app/v2/add-vehicle-to-garage');

      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final responseData = jsonDecode(response.body);
      print(responseData);
      return responseData;
    } on TimeoutException {
      throw {
        'message': 'Failed to add your vehicle, your connection timed out',
        'name': 'TimeOutError',
      };
    } catch (e) {
      print('Error adding vehicle to garage: $e');
      rethrow;
    }
  }

  /// Update vehicle in garage with chunk-based image upload
  /// This method handles large cover photos by uploading them in chunks
  /// Update vehicle in garage with chunk-based image upload
  ///
  /// This method handles large cover photos by uploading them in chunks
  ///
  /// Parameters:
  /// - [vehicleId]: Vehicle ID to update
  /// - [payload]: Updated vehicle data
  /// - [userId]: User ID
  /// - [onUploadProgress]: Optional callback for upload progress (current, total, percentage)
  static Future<Map<String, dynamic>?> updateVehicle(
    String vehicleId,
    Map<String, dynamic> payload,
    String userId, {
    Function(int current, int total, double percentage)? onUploadProgress,
  }) async {
    try {
      // Extract cover photo if present
      final coverPhoto = payload['cover_photo'];
      String? coverPhotoValue;
      bool isNewUpload = false;

      // If cover photo is provided, check what type it is
      if (coverPhoto != null && coverPhoto.isNotEmpty) {
        if (coverPhoto.startsWith('data:image')) {
          // It's a new base64 image, upload it
          print('Uploading new cover photo in chunks...');

          coverPhotoValue = await ChunkUploadUtility.uploadAndGetUrl(
            base64Image: coverPhoto,
            userId: int.parse(userId),
            type: 'garage',
            onProgress: onUploadProgress,
          );

          if (coverPhotoValue == null) {
            throw Exception('Failed to upload cover photo');
          }

          isNewUpload = true;
          print('Cover photo uploaded successfully with ID: $coverPhotoValue');
        } else {
          // It's an existing URL or ID, use it directly
          coverPhotoValue = coverPhoto;
          print('Using existing cover photo: $coverPhotoValue');
        }
      }

      // Prepare the request body
      final body = <String, dynamic>{
        ...payload,
        'user_id': userId,
        'garage_id': vehicleId,
      };

      // Replace base64 cover_photo with the media ID or keep existing value
      if (coverPhotoValue != null) {
        body['cover_photo'] = coverPhotoValue;
      }

      if (isNewUpload) {
        body['use_uploaded_url'] = true; // Flag for new uploads
      }

      print('Updating vehicle...');
      print(body);

      final response = await http.put(
        Uri.parse('$_apiUrl/wp-json/app/v2/garage/$vehicleId'),
        headers: const {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }

      print('Update failed with status: ${response.statusCode}');
      return null;
    } catch (e) {
      print('Error updating vehicle: $e');
      return null;
    }
  }

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

  static Future<Map<String, dynamic>?> addVehicleModLegacy(
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

  static Future<Map<String, dynamic>?> updateVehicleModLegacy(
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

  /// Add vehicle modification with chunk-based image upload
  ///
  /// Parameters:
  /// - [payload]: Mod data including mod_image
  /// - [userId]: User ID
  /// - [onUploadProgress]: Optional callback for upload progress (current, total, percentage)
  static Future<Map<String, dynamic>?> addVehicleMod(
    Map<String, dynamic> payload,
    String userId, {
    Function(int current, int total, double percentage)? onUploadProgress,
  }) async {
    try {
      // Extract mod image if present
      final modImage = payload['mod_image'];
      String? modImageUrl;

      // If mod image is provided, upload it in chunks first
      if (modImage != null && modImage.isNotEmpty) {
        print('Uploading mod image in chunks...');

        modImageUrl = await ChunkUploadUtility.uploadAndGetUrl(
          base64Image: modImage,
          userId: int.parse(userId),
          type: 'mod',
          onProgress: onUploadProgress,
        );

        if (modImageUrl == null) {
          throw Exception('Failed to upload mod image');
        }

        print('Mod image uploaded successfully: $modImageUrl');
      }

      // Prepare the request body
      final body = <String, dynamic>{...payload, 'user_id': userId};

      // Replace base64 mod_image with the uploaded URL
      if (modImageUrl != null) {
        body['mod_image'] = modImageUrl;
        body['use_uploaded_url'] = true;
      }

      print('Adding vehicle mod...');
      print(body);

      final response = await http.post(
        Uri.parse('$_apiUrl/wp-json/app/v3/add-vehicle-mod'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
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

  /// Update vehicle modification with chunk-based image upload
  ///
  /// Parameters:
  /// - [payload]: Updated mod data
  /// - [modId]: Mod ID to update
  /// - [userId]: User ID
  /// - [onUploadProgress]: Optional callback for upload progress (current, total, percentage)
  static Future<Map<String, dynamic>?> updateVehicleMod(
    Map<String, dynamic> payload,
    String modId,
    String userId, {
    Function(int current, int total, double percentage)? onUploadProgress,
  }) async {
    try {
      // Extract mod image if present
      final modImage = payload['mod_image'];
      String? modImageValue;
      bool isNewUpload = false;

      // If mod image is provided, check what type it is
      if (modImage != null && modImage.isNotEmpty) {
        if (modImage.startsWith('data:image')) {
          // It's a new base64 image, upload it
          print('Uploading new mod image in chunks...');

          modImageValue = await ChunkUploadUtility.uploadAndGetUrl(
            base64Image: modImage,
            userId: int.parse(userId),
            type: 'mod',
            onProgress: onUploadProgress,
          );

          if (modImageValue == null) {
            throw Exception('Failed to upload mod image');
          }

          isNewUpload = true;
          print('Mod image uploaded successfully with ID: $modImageValue');
        } else {
          // It's an existing URL or ID, use it directly
          modImageValue = modImage;
          print('Using existing mod image: $modImageValue');
        }
      }

      // Prepare the request body
      final body = <String, dynamic>{
        ...payload,
        'mod_id': modId,
        'user_id': userId,
      };

      // Replace base64 mod_image with the media ID or keep existing value
      if (modImageValue != null) {
        body['mod_image'] = modImageValue;
      }

      if (isNewUpload) {
        body['use_uploaded_url'] = true;
      }

      print('Updating vehicle mod...');
      print(body);

      final response = await http.post(
        Uri.parse('$_apiUrl/wp-json/app/v3/update-vehicle-mod'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
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
