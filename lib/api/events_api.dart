import 'dart:convert';
import 'package:drivelife/models/event_media.dart';
import 'package:drivelife/utils/event_media_uploader.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../config/api_config.dart';

class EventsAPI {
  static final AuthService _authService = AuthService();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final _uploader = ChunkedFileUploader(apiUrl: ApiConfig.baseUrl);

  /// Fetch paginated events with optional filters
  static Future<Map<String, dynamic>?> getEvents({
    required int page,
    int limit = 10,
    String? category,
    String? location,
    String? dateFilter,
    double? latitude,
    double? longitude,
    String? country,
    int radius = 25,
    DateTime? customDateFrom, // NEW
    DateTime? customDateTo, // NEW
    String? customLocation, // NEW
    double? customLat, // NEW
    double? customLng, // NEW
  }) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getUser();

      if (token == null || user == null) {
        print('❌ [EventsAPI] No token or user found');
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
        'site': country ?? userCountry,
      };

      // Build filters in the exact format expected
      final filters = <String, dynamic>{
        'event_location': [location ?? 'national'],
        'custom_location': null,
        'event_date': [dateFilter ?? 'anytime'],
        'event_start': '',
        'event_end': '',
        'location': [location ?? 'national'],
      };

      // Add categories as array of IDs
      if (category != null && category.isNotEmpty) {
        // Split comma-separated slugs and convert to category IDs
        final categoryList = category.split(',');
        filters['event_category'] = categoryList;
      } else {
        filters['event_category'] = [];
      }

      // Handle specific date filters
      if (dateFilter != null && dateFilter.isNotEmpty) {
        final now = DateTime.now();
        switch (dateFilter.toLowerCase()) {
          case 'today':
            filters['event_start'] = _formatDate(now);
            filters['event_end'] = _formatDate(now);
            filters['event_date'] = ['today'];
            break;
          case 'tomorrow':
            final tomorrow = now.add(const Duration(days: 1));
            filters['event_start'] = _formatDate(tomorrow);
            filters['event_end'] = _formatDate(tomorrow);
            filters['event_date'] = ['tomorrow'];
            break;
          case 'this-weekend':
            final daysUntilSaturday = (6 - now.weekday) % 7;
            final saturday = now.add(Duration(days: daysUntilSaturday));
            final sunday = saturday.add(const Duration(days: 1));
            filters['event_start'] = _formatDate(saturday);
            filters['event_end'] = _formatDate(sunday);
            filters['event_date'] = ['this-weekend'];
            break;
          case 'custom': // NEW
            // Pass custom dates if provided
            filters['event_date'] = ['custom'];
            // These will be passed as separate parameters
            break;
          case 'anytime':
          default:
            filters['event_date'] = ['anytime'];
            filters['event_start'] = '';
            filters['event_end'] = '';
        }
      }

      // Handle location-based filters
      if (location != null && location.isNotEmpty) {
        filters['event_location'] = [location.toLowerCase()];
        filters['location'] = [location.toLowerCase()];

        if (location.toLowerCase() == 'near-me') {
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
          // NEW
          filters['custom_location'] =
              'custom'; // Will be replaced with actual location
          // Custom lat/lng will be passed as separate parameters
        } else {
          filters['custom_location'] = null;
        }
      }

      // Handle custom date range
      if (dateFilter == 'custom' &&
          customDateFrom != null &&
          customDateTo != null) {
        filters['event_start'] = _formatDate(customDateFrom);
        filters['event_end'] = _formatDate(customDateTo);
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
      queryParams['version'] = '2';

      print('🔍 [EventsAPI] Filters: ${jsonEncode(filters)}');

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/get-events-trending',
      ).replace(queryParameters: queryParams);

      print('🌐 [EventsAPI] Fetching events: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print(
          '✅ [EventsAPI] Events fetched: ${data['data']?.length ?? 0} events',
        );
        return data;
      } else {
        print('❌ [EventsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return null;
    }
  }

  /// Fetch single event details
  static Future<Map<String, dynamic>?> getEvent({
    required String eventId,
    String? country,
  }) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getUser();

      if (token == null || user == null) {
        print('❌ [EventsAPI] No token or user found');
        return null;
      }

      final userId = user['id'];

      final lastLocation = user['last_location'];
      final userCountry = (lastLocation is Map && lastLocation.isNotEmpty)
          ? (lastLocation['country'] ?? 'GB')
          : 'GB';

      final queryParams = {
        'event_id': eventId,
        'user_id': userId.toString(),
        'site': country ?? userCountry,
      };

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/get-event',
      ).replace(queryParameters: queryParams);

      print('🌐 [EventsAPI] Fetching event: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ [EventsAPI] Event fetched: ${data['title']}');
        return data;
      } else {
        print('❌ [EventsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return null;
    }
  }

  /// Endpoint example: /wp-json/app/v2/my-event-tickets
  static Future<Map<String, dynamic>?> getMyEventTickets({
    String? site, // optional override, e.g. "GB"
  }) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getUser();

      print(user);

      if (token == null || user == null) {
        print('❌ [TicketsAPI] No token or user found');
        return null;
      }

      final lastLocation = user['last_location'];
      final userCountry = (lastLocation is Map && lastLocation.isNotEmpty)
          ? (lastLocation['country'] ?? 'GB')
          : 'GB';

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/get-my-event-tickets',
      ).replace(queryParameters: {'site': (site ?? userCountry)});

      print('🌐 [TicketsAPI] Fetching my tickets: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        return data;
      } else {
        print('❌ [TicketsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [TicketsAPI] Exception: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getOrderTickets({
    required String order, // encrypted order id OR plain numeric id
    bool admin = false,
    String? site, // optional, if your backend supports site switching via param
  }) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getUser();

      if (token == null || user == null) {
        print('❌ [TicketsAPI] No token or user found');
        return null;
      }

      final lastLocation = user['last_location'];
      final userCountry = (lastLocation is Map && lastLocation.isNotEmpty)
          ? (lastLocation['country'] ?? 'GB')
          : 'GB';

      final queryParams = <String, String>{
        'order': order,
        'admin': admin ? '1' : '0',
        // include only if your route accepts it
        if (site != null) 'site': site,
        if (site == null) 'site': userCountry,
      };

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/view-order-tickets',
      ).replace(queryParameters: queryParams);

      print('🌐 [TicketsAPI] Fetching order tickets: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final ok = data['success'] == true;

        if (ok) {
          final header = data['data']?['header'];
          print(
            '✅ [TicketsAPI] Tickets fetched for order: ${header?['order_id']}',
          );
        } else {
          print('❌ [TicketsAPI] API success=false: ${data['message']}');
        }

        return data;
      } else {
        print('❌ [TicketsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [TicketsAPI] Exception: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getFeaturedEvents({
    String? country,
    int limit = 5,
  }) async {
    try {
      final user = await _authService.getUser();

      if (user == null) {
        print('❌ [EventsAPI] No user found');
        return null;
      }

      final lastLocation = user['last_location'];
      final userCountry = (lastLocation is Map && lastLocation.isNotEmpty)
          ? (lastLocation['country'] ?? 'GB')
          : 'GB';

      final site = country ?? userCountry;

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/get-featured-events',
      ).replace(queryParameters: {'site': site, 'limit': limit.toString()});

      print('🌐 [EventsAPI] Fetching featured events: $uri');

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print('❌ [EventsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return null;
    }
  }

  /// Fetch event categories
  static Future<List<Map<String, dynamic>>?> getEventCategories({
    String? country,
  }) async {
    try {
      final user = await _authService.getUser();

      if (user == null) {
        print('❌ [EventsAPI] No user found');
        return null;
      }

      // Handle last_location being either a Map or an empty array
      final lastLocation = user['last_location'];
      final userCountry = (lastLocation is Map && lastLocation.isNotEmpty)
          ? (lastLocation['country'] ?? 'GB')
          : 'GB';

      final site = country ?? userCountry;

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/get-event-categories',
      ).replace(queryParameters: {'site': site});

      print('🌐 [EventsAPI] Fetching categories: $uri');

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final categories = data.cast<Map<String, dynamic>>();
        print(
          '✅ [EventsAPI] Categories fetched: ${categories.length} categories',
        );
        return categories;
      } else {
        print('❌ [EventsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return null;
    }
  }

  /// Toggle event like/unlike (favorite)
  static Future<bool> toggleEventLike({
    required String eventId,
    String? site,
  }) async {
    try {
      final user = await _authService.getUser();

      if (user == null) {
        print('❌ [EventsAPI] No user found');
        return false;
      }

      final userId = user['id'];
      final userSite =
          site ?? user['last_location']?['country']?.toLowerCase() ?? 'gb';

      // Format event ID with site prefix if needed
      String formattedEventId = eventId;
      if (userSite.toLowerCase() != 'gb') {
        formattedEventId = '${userSite.toLowerCase()}_$eventId';
      }

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/favourite-event',
      );

      print(
        '🌐 [EventsAPI] Toggling event favorite: $formattedEventId (site: $userSite)',
      );

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'event_id': formattedEventId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print(
          '✅ [EventsAPI] Event favorite toggled: ${data['is_liked'] ?? data['is_favourite']}',
        );
        return true;
      } else {
        print('❌ [EventsAPI] Error ${response.statusCode}: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return false;
    }
  }

  /// Get user's liked events
  static Future<List<Map<String, dynamic>>?> getLikedEvents({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getUser();

      if (token == null || user == null) {
        print('❌ [EventsAPI] No token or user found');
        return null;
      }

      final userId = user['id'];

      final queryParams = {
        'user_id': userId.toString(),
        'page': page.toString(),
        'per_page': limit.toString(),
      };

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/get-liked-events',
      ).replace(queryParameters: queryParams);

      print('🌐 [EventsAPI] Fetching liked events: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> events = data['data'] ?? [];
        print('✅ [EventsAPI] Liked events fetched: ${events.length} events');
        return events.cast<Map<String, dynamic>>();
      } else {
        print('❌ [EventsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return null;
    }
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Get user's created and saved events
  static Future<Map<String, dynamic>?> getProfileEvents({
    required String userId,
  }) async {
    try {
      final token = await _authService.getToken();
      final user = await _authService.getUser();

      if (token == null || user == null) {
        print('❌ [EventsAPI] No token or user found');
        return null;
      }

      final sessionUserId = user['id'];

      final uri =
          Uri.parse(
            '${ApiConfig.baseUrl}/wp-json/app/v2/get-profile-events',
          ).replace(
            queryParameters: {
              'user_id': userId.toString(),
              'session_user_id': sessionUserId.toString(),
            },
          );

      print('🌐 [EventsAPI] Fetching profile events: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ [EventsAPI] Profile events fetched');
        return data;
      } else {
        print('❌ [EventsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return null;
    }
  }

  /// Save/Create event
  static Future<Map<String, dynamic>?> saveEvent({
    String? eventId,
    required String title,
    required String country,
    required Map<String, dynamic> location,
    required List<String> categories,
    required String visibility,
    required String status,
    required List<Map<String, dynamic>> dates,
    required String description,
    String? externalTicketsUrl,
    String? ticketType,
    String? entryDetailsFree,
    String? entryDetails,
  }) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        print('No auth token found');
        return null;
      }

      final user = await _authService.getUser();

      if (user == null) {
        print('❌ [EventsAPI] No user found');
        return null;
      }

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/save-event-data',
      );

      print('🌐 [EventsAPI] Saving event: $title');

      final body = {
        if (eventId != null) 'event_id': eventId,
        'user_id': user['id'],
        'title': title,
        'country': country,
        'location': location,
        'categories': categories,
        'visibility': visibility,
        'status': status,
        'dates': dates,
        'description': description,
        if (externalTicketsUrl != null)
          'external_tickets_url': externalTicketsUrl,
        if (ticketType != null) 'ticket_type': ticketType,
        if (entryDetailsFree != null) 'entry_details_free': entryDetailsFree,
        if (entryDetails != null) 'entry_details': entryDetails,
      };

      print('📦 [EventsAPI] Event data: ${jsonEncode(body)}');
      // return null; // Remove this line to enable actual API call

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
        print('✅ [EventsAPI] Event saved: ${data['event_id']}');
        return data;
      } else {
        print('❌ [EventsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return null;
    }
  }

  /// Upload event images with chunked upload and progress
  static Future<Map<String, dynamic>?> uploadEventImages({
    required String eventId,
    required List<ImageData> images,
    required String type, // 'cover' or 'gallery'
    Function(double progress)? onProgress,
  }) async {
    try {
      print('🌐 [EventsAPI] Uploading $type images for event $eventId');

      final result = await _uploader.updateEventImages(
        eventId: eventId,
        mediaList: images,
        mediaGroup: type,
        onOverallProgress: onProgress,
      );

      print('✅ [EventsAPI] Images uploaded successfully');
      return result;
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return null;
    }
  }

  /// Remove event image
  static Future<Map<String, dynamic>?> removeEventImage({
    required String eventId,
    required String mediaId,
  }) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        print('❌ [EventsAPI] No token available');
        return null;
      }

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/remove-event-image-cloudflare',
      );

      print('🌐 [EventsAPI] Removing image $mediaId from event $eventId');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'event_id': eventId, 'media_id': mediaId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ [EventsAPI] Image removed successfully');
        return data;
      } else {
        print('❌ [EventsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return null;
    }
  }

  /// Get event edit data
  static Future<Map<String, dynamic>?> getEventEditData({
    required String eventId,
    required String country,
  }) async {
    try {
      final token = await _storage.read(key: 'token');
      if (token == null) {
        print('❌ [EventsAPI] No token available');
        return null;
      }

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/get-event-edit-data?event_id=$eventId&country=$country&version=2',
      );

      print('🌐 [EventsAPI] Fetching event edit data for event $eventId');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ [EventsAPI] Event edit data fetched successfully');
        return data;
      } else {
        print('❌ [EventsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return null;
    }
  }

  /// Search for events, users, venues
  static Future<Map<String, dynamic>?> discoverSearch({
    required String search,
    required String type, // 'users', 'events', 'venues', 'all'
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final user = await _authService.getUser();

      if (user == null) {
        print('❌ [EventsAPI] No user found');
        return null;
      }

      final userId = user['id'];
      final site = user['last_location']?['country'] ?? 'GB';

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v1/discover-search',
      );

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'search': search,
          'user_id': userId,
          'page': page,
          'type': type,
          'per_page': perPage,
          'site': site,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print(data);
        return data;
      } else {
        print('❌ [EventsAPI] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [EventsAPI] Exception: $e');
      return null;
    }
  }
}
