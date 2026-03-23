import 'dart:convert';
import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:http/http.dart' as http;

class ReminderApiService {
  static final AuthService _authService = AuthService();

  // ── Headers ───────────────────────────────────────────────────────────────

  static Future<Map<String, String>> _getHeaders() async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final authToken = await _authService.getToken();
    if (authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }

    return headers;
  }
  

  // ── Fetch reminders for a garage ──────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchReminders(
    String garageId,
  ) async {
    try {
      final headers = await _getHeaders();

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/wp-json/app/v2/garage/reminders?garage_id=$garageId',
        ),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['reminders'] ?? []);
        }
        throw Exception(data['message'] ?? 'Failed to load reminders');
      }

      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      print('Error fetching reminders: $e');
      rethrow;
    }
  }

  // ── Add reminder ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> addReminder(
    Map<String, dynamic> payload,
    String userId,
  ) async {
    try {
      final headers = await _getHeaders();

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/garage/reminder'),
        headers: headers,
        body: json.encode({...payload, 'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return data;
        throw Exception(data['message'] ?? 'Failed to add reminder');
      }

      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      print('Error adding reminder: $e');
      rethrow;
    }
  }

  // ── Update reminder ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> updateReminder(
    Map<String, dynamic> payload,
    String reminderId,
    String userId,
  ) async {
    try {
      final headers = await _getHeaders();

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.baseUrl}/wp-json/app/v2/garage/reminder/$reminderId',
        ),
        headers: headers,
        body: json.encode({...payload, 'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return data;
        throw Exception(data['message'] ?? 'Failed to update reminder');
      }

      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      print('Error updating reminder: $e');
      rethrow;
    }
  }

  // ── Delete reminder ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> deleteReminder(
    String reminderId,
    String userId,
  ) async {
    try {
      final headers = await _getHeaders();

      final response = await http.delete(
        Uri.parse(
          '${ApiConfig.baseUrl}/wp-json/app/v2/garage/reminder/$reminderId',
        ),
        headers: headers,
        body: json.encode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return data;
        throw Exception(data['message'] ?? 'Failed to delete reminder');
      }

      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      print('Error deleting reminder: $e');
      rethrow;
    }
  }
}
