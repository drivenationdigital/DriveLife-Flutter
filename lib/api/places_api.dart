import 'dart:convert';
import 'package:drivelife/config/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:drivelife/services/auth_service.dart';

class VenueApiService {
  static final AuthService _authService = AuthService();

  /// Fetch trending venues with filters
  static Future<Map<String, dynamic>?> getTrendingVenues({
    required int page,
    int limit = 10,
    bool paginate = false,
    String? location,
    double? latitude,
    double? longitude,
    String? country,
    int radius = 25,
    String? customLocation,
    double? customLat,
    double? customLng,
  }) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getUser();

      if (token == null || user == null) {
        print('❌ [VenueAPI] No token or user found');
        return null;
      }

      final userId = user['id'];

      // Handle last_location being either a Map or an empty array
      final lastLocation = user['last_location'];
      final isLocationValid = lastLocation is Map && lastLocation.isNotEmpty;

      final userCountry = isLocationValid
          ? (lastLocation['country'] ?? 'GB')
          : 'GB';
      final userLat =
          latitude ?? (isLocationValid ? lastLocation['latitude'] : null);
      final userLng =
          longitude ?? (isLocationValid ? lastLocation['longitude'] : null);

      // Build query parameters
      final queryParams = {
        'user_id': userId.toString(),
        'page': page.toString(),
        'per_page': limit.toString(),
        'paginate': paginate.toString(),
        'site': country ?? userCountry,
      };

      // Build filters for location only
      final filters = <String, dynamic>{
        'venue_location': [location ?? 'national'],
        'custom_location': null,
        'location': [location ?? 'national'],
      };

      // Handle location-based filters
      if (location != null && location.isNotEmpty) {
        filters['venue_location'] = [location.toLowerCase()];
        filters['location'] = [location.toLowerCase()];

        if (location.toLowerCase() == 'near-me') {
          if (userLat != null) filters['latitude'] = userLat;
          if (userLng != null) filters['longitude'] = userLng;
          filters['radius'] = radius;
          filters['custom_location'] = null;
        } else if (location == '25-miles') {
          if (userLat != null) filters['latitude'] = userLat;
          if (userLng != null) filters['longitude'] = userLng;
          filters['radius'] = 25;
          filters['custom_location'] = null;
        } else if (location == '50-miles') {
          if (userLat != null) filters['latitude'] = userLat;
          if (userLng != null) filters['longitude'] = userLng;
          filters['radius'] = 50;
          filters['custom_location'] = null;
        } else if (location == '100-miles') {
          if (userLat != null) filters['latitude'] = userLat;
          if (userLng != null) filters['longitude'] = userLng;
          filters['radius'] = 100;
          filters['custom_location'] = null;
        } else if (location == 'custom') {
          filters['custom_location'] = 'custom';
        } else if (location == 'national') {
          filters['venue_location'] = ['national'];
          filters['location'] = ['national'];
          filters['custom_location'] = null;
        } else {
          filters['custom_location'] = null;
        }
      }

      // Handle custom location
      if (location == 'custom' && customLocation != null) {
        if (customLat != null && customLng != null) {
          filters['custom_location'] = {
            'latitude': customLat,
            'longitude': customLng,
            'address': customLocation,
          };
        }
        filters['radius'] = radius;
      }

      queryParams['filters'] = jsonEncode(filters);

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/get-venues-trending',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print('❌ [VenueAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [VenueAPI] Exception: $e');
      return null;
    }
  }

  /// Follow or unfollow a venue
  static Future<Map<String, dynamic>?> followVenue({
    required String venueId,
  }) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getUser();

      if (token == null || user == null) {
        print('❌ [VenueAPI] No token or user found');
        return null;
      }

      final userId = user['id'];

      // Handle last_location being either a Map or an empty array
      final lastLocation = user['last_location'];
      final isLocationValid = lastLocation is Map && lastLocation.isNotEmpty;

      final userCountry = isLocationValid
          ? (lastLocation['country'] ?? 'GB')
          : 'GB';

      final body = {
        'venue_id': venueId,
        'user_id': userId.toString(),
        'site': userCountry,
      };

      final uri = Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v1/follow-venue');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print('❌ [VenueAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [VenueAPI] Exception: $e');
      return null;
    }
  }

  /// Fetch a single venue by ID
  static Future<Map<String, dynamic>?> getVenue({
    required String venueId,
    String? country,
  }) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getUser();

      if (token == null || user == null) {
        print('❌ [VenueAPI] No token or user found');
        return null;
      }

      final userId = user['id'];

      // Handle last_location being either a Map or an empty array
      final lastLocation = user['last_location'];
      final isLocationValid = lastLocation is Map && lastLocation.isNotEmpty;

      final userCountry =
          country ??
          (isLocationValid ? (lastLocation['country'] ?? 'GB') : 'GB');

      final queryParams = {
        'venue_id': venueId,
        'user_id': userId.toString(),
        'site': userCountry,
      };

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/get-venue',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print('❌ [VenueAPI] Error ${response.statusCode}: ${response.body}');
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Failed to fetch venue');
      }
    } catch (e) {
      print('❌ [VenueAPI] Exception: $e');
      rethrow;
    }
  }

  /// Get user's followed venues
  static Future<List<Map<String, dynamic>>?> getFollowedVenues({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getUser();

      if (token == null || user == null) {
        print('❌ [VenueAPI] No token or user found');
        return null;
      }

      final userId = user['id'];

      // Handle last_location being either a Map or an empty array
      final lastLocation = user['last_location'];
      final isLocationValid = lastLocation is Map && lastLocation.isNotEmpty;

      final userCountry = isLocationValid
          ? (lastLocation['country'] ?? 'GB')
          : 'GB';

      final queryParams = {
        'user_id': userId.toString(),
        'page': page.toString(),
        'per_page': limit.toString(),
        'site': userCountry,
      };

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/get-followed-venues',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final venues =
            (data['data'] as List?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [];
        print('✅ [VenueAPI] Followed venues fetched: ${venues.length}');
        return venues;
      } else {
        print('❌ [VenueAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [VenueAPI] Exception: $e');
      return null;
    }
  }

  static Future<List<dynamic>?> getFeaturedVenues({
    String? country,
    int limit = 5,
  }) async {
    try {
      final user = await _authService.getUser();

      if (user == null) {
        return null;
      }

      final lastLocation = user['last_location'];
      final userCountry = (lastLocation is Map && lastLocation.isNotEmpty)
          ? (lastLocation['country'] ?? 'GB')
          : 'GB';

      final site = country ?? userCountry;

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/featured-venues',
      ).replace(queryParameters: {'site': site, 'limit': limit.toString()});

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        // Extract the 'data' array from the response
        if (responseData['success'] == true && responseData['data'] != null) {
          return responseData['data'] as List<dynamic>;
        }
        return null;
      } else {
        return null;
      }
    } catch (e) {
      print('❌ [VenueAPI] Exception: $e');
      return null;
    }
  }

  static Future<Map<String, List<dynamic>>?> getMyVenues() async {
    try {
      final token = await _authService.getToken();

      if (token == null) {
        return null;
      }

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/get-my-venues',
      );

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (responseData['success'] == true && responseData['data'] != null) {
          final data = responseData['data'];
          return {
            'owned_venues': (data['owned_venues'] as List<dynamic>?) ?? [],
            'followed_venues':
                (data['followed_venues'] as List<dynamic>?) ?? [],
          };
        }
        return null;
      } else {
        print('❌ [VenueAPI] Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ [VenueAPI] Exception: $e');
      return null;
    }
  }
}
