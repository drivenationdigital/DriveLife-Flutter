import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class QrCodeAPI {
  static const String _baseUrl = 'https://www.carevents.com/uk';
  static const _storage = FlutterSecureStorage();

  /// Verify a scanned QR code
  static Future<Map<String, dynamic>?> verifyScan(
    String qrCode,
    int userId,
  ) async {
    try {
      final token = await _storage.read(key: 'token');

      if (token == null) {
        print('No auth token found');
        return {
          'status': 'error',
          'message': 'Authentication required',
          'available': false,
        };
      }

      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/verify-qr-code');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'qr_code': qrCode, 'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('QR code verified successfully: $data for $qrCode');
        return data;
      } else {
        print('Failed to verify QR code: ${response.statusCode}');
        return {
          'status': 'error',
          'message': 'Failed to verify QR code',
          'available': false,
        };
      }
    } catch (e) {
      print('Error verifying QR code: $e');
      return {
        'status': 'error',
        'message': 'Failed to verify QR code',
        'available': false,
      };
    }
  }

  /// Link a QR code to an entity (profile, vehicle, etc)
  static Future<Map<String, dynamic>?> linkEntity({
    required int entityId,
    required String qrCode,
    required String entityType, // "profile", "vehicle", etc
  }) async {
    try {
      final token = await _storage.read(key: 'token');

      if (token == null) {
        print('No auth token found');
        return null;
      }

      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/link-qr-code-entity');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'entity_id': entityId,
          'qr_code': qrCode,
          'entity_type': entityType,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Failed to link QR code: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error linking QR code: $e');
      return null;
    }
  }

  /// Unlink a QR code from an entity
  static Future<Map<String, dynamic>?> unlinkEntity({
    required String qrCode,
    required int entityId,
    required String entityType,
  }) async {
    try {
      final token = await _storage.read(key: 'token');

      if (token == null) {
        print('No auth token found');
        return null;
      }

      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/unlink-qr-code-entity');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'qr_code': qrCode,
          'entity_id': entityId,
          'entity_type': entityType,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Failed to unlink QR code: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error unlinking QR code: $e');
      return null;
    }
  }

  /// Get entity ID from QR code
  static Future<Map<String, dynamic>?> getLinkedEntity(String qrCode) async {
    try {
      final token = await _storage.read(key: 'token');

      final uri = Uri.parse('$_baseUrl/wp-json/app/v1/get-linked-entity');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'qr_code': qrCode}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 404) {
        print('QR code not linked to any entity');
        return null;
      } else {
        print('Failed to get linked entity: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error getting linked entity: $e');
      return null;
    }
  }

  /// Extract QR code from URL
  static String? extractQrCodeFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final allowedHosts = ['mydrivelife.com', 'qr.mydrivelife.com'];

      if (allowedHosts.contains(uri.host)) {
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          return pathSegments.last;
        }
      }
      return null;
    } catch (e) {
      print('Error parsing QR code URL: $e');
      return null;
    }
  }
}
