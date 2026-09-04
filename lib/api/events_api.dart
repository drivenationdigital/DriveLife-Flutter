import 'dart:io';
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

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/get-events-trending',
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

      // The event's own site wins over the user's country. `country` was
      // accepted and then ignored, so a UK event opened by someone in Canada
      // asked the US blog for that id and 404'd — post ids only mean anything
      // within their own blog. The server treats this as a hint and falls back
      // to the other blog, so a wrong guess is now recoverable rather than
      // fatal, but sending the right one saves the second lookup.
      final site = (country != null && country.trim().isNotEmpty)
          ? country
          : userCountry;

      final queryParams = {
        'event_id': eventId,
        'user_id': userId.toString(),
        'site': site,
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
    int? clubId,
  }) async {
    try {
      final token = await _authService.getParentUserToken();
      if (token == null) {
        print('No auth token found');
        return null;
      }

      final user = await _authService.getParentUser();

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
        if (clubId != null) 'club_id': clubId,
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

  /// Community gallery: direct-to-Cloudflare upload, then batch registration.
  /// Mints a one-shot Cloudflare Images direct-upload URL.
  ///
  /// Split out of the old batch helper so a caller can drive one image at a
  /// time: retry a single failure without redoing the whole gallery, and
  /// register as it goes instead of betting the batch on a final call.
  static Future<({String uploadUrl, String imageId})>
  createCommunityGalleryUpload() async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not signed in');

    final response = await http.post(
      Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/event-community-gallery/create-upload',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get upload URL (${response.statusCode})');
    }

    final data = jsonDecode(response.body);
    return (
      uploadUrl: data['upload_url'] as String,
      imageId: data['image_id'] as String,
    );
  }

  /// Uploads one file to a minted Cloudflare URL.
  ///
  /// [onSent] reports bytes as they go on the wire, so a big photo advances the
  /// bar instead of the UI sitting still until the whole file lands.
  static Future<void> uploadCommunityGalleryFile({
    required String uploadUrl,
    required File file,
    void Function(int sent, int total)? onSent,
  }) async {
    final length = await file.length();

    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    var sent = 0;

    request.files.add(
      http.MultipartFile(
        'file',
        file.openRead().map((chunk) {
          sent += chunk.length;
          onSent?.call(sent, length);
          return chunk;
        }),
        length,
        filename: file.path.split('/').last,
      ),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception('Cloudflare upload failed (${response.statusCode})');
    }
  }

  /// Attaches already-uploaded Cloudflare image IDs to an event.
  ///
  /// Safe to call repeatedly with small batches — that is the point: an image
  /// registered as soon as it lands is not lost if the app dies mid-gallery.
  /// Attaches uploaded Cloudflare images to a gallery.
  ///
  /// A gallery is its own thing now, so [eventId] is optional: pass nothing and
  /// the photos land in a standalone gallery titled [galleryName].
  ///
  /// Photos arrive in chunks. The first call creates the gallery and returns
  /// its `gallery_id`; pass that back as [galleryId] on later chunks so they
  /// append to the same gallery instead of creating one each.
  static Future<Map<String, dynamic>?> registerCommunityGalleryMedia({
    String? eventId,
    required List<String> mediaIds,
    String? galleryName,
    String? entityType = 'event',
    int? galleryId,
    String placeId = '',
    String placeLabel = '',
    double? lat,
    double? lng,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not signed in');

    // Tolerate a missing or unparseable id rather than throwing: an untagged
    // gallery legitimately has no entity.
    final entityId = int.tryParse(eventId ?? '') ?? 0;
    final hasEntity =
        entityId > 0 && entityType != null && entityType != 'none';

    // A Google place has no post id, so it can never satisfy hasEntity — it
    // travels as its own fields instead.
    final hasPlace = entityType == 'location' && placeLabel.isNotEmpty;

    final response = await http.post(
      Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/event-community-gallery/register',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        // entity_* is what the server reads; event_id is still sent for an
        // event so an older build of the API keeps working.
        if (hasEntity) 'entity_type': entityType,
        if (hasEntity) 'entity_id': entityId,
        if (hasEntity && entityType == 'event') 'event_id': entityId,
        if (hasPlace) ...{
          'entity_type': 'location',
          'place_id': placeId,
          'place_label': placeLabel,
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
        },
        if (galleryId != null && galleryId > 0) 'gallery_id': galleryId,
        'media_ids': mediaIds,
        // Omitted rather than sent empty, so the server falls back to the
        // event's own name for photos added from its gallery tab.
        if (galleryName != null && galleryName.trim().isNotEmpty)
          'gallery_name': galleryName.trim(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to register images (${response.statusCode})');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Runs one pass of the vehicle scan over a gallery.
  ///
  /// Incremental by design: each photo is a model round trip, so the server
  /// processes a handful per call. Keep calling while `done` is false. Every
  /// response carries all suggestions found so far, so stopping early still
  /// leaves something usable.
  ///
  /// `available` is false where the site has no AI library installed — the
  /// caller should hide the section rather than show an error.
  static Future<Map<String, dynamic>> scanGallery({
    required int galleryId,
    int limit = 4,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not signed in');

    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/galleries/scan'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'gallery_id': galleryId, 'limit': limit}),
    );

    // A 404 means this build of the API predates the scan endpoint. That is a
    // deployment state, not a bug in the gallery, and it must be reported
    // distinctly — it used to look identical to "found no cars".
    if (response.statusCode == 404) {
      throw Exception('Photo scanning is not available on the server yet');
    }

    if (response.statusCode != 200) {
      throw Exception('Scan failed (${response.statusCode})');
    }

    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  /// Saves the tags on a gallery. Owner only.
  ///
  /// The list REPLACES what was stored for this gallery (and [mediaId]), so
  /// the caller sends what it is showing rather than diffing adds and removes.
  /// [mediaId] 0 tags the whole gallery; a photo row id tags that one photo.
  ///
  /// Each tag is `{entity_type: 'user'|'car', entity_id: int, registration?}`.
  static Future<List<Map<String, dynamic>>> saveGalleryTags({
    required int galleryId,
    required List<Map<String, dynamic>> tags,
    int mediaId = 0,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not signed in');

    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/galleries/tags'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'gallery_id': galleryId,
        'media_id': mediaId,
        'tags': tags,
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      throw Exception(body['message']?.toString() ?? 'Could not save the tags');
    }

    return (body['tags'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// The tags on a gallery.
  static Future<List<Map<String, dynamic>>> fetchGalleryTags({
    required int galleryId,
    int? mediaId,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not signed in');

    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/galleries/tags').replace(
        queryParameters: {
          'gallery_id': '$galleryId',
          if (mediaId != null) 'media_id': '$mediaId',
        },
      ),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) return const [];

    final body = jsonDecode(response.body);
    final list = (body is Map ? body['tags'] : null) as List? ?? const [];

    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Removes a whole gallery and every photo in it. Owner only.
  ///
  /// Irreversible on the Cloudflare side — the stored originals are purged —
  /// so callers must confirm first.
  static Future<void> deleteGallery(int galleryId) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not signed in');

    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/galleries/delete'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'gallery_id': galleryId}),
    );

    if (response.statusCode == 200) return;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(
      body['message']?.toString() ?? 'Could not delete the gallery',
    );
  }

  /// Galleries for a profile tab, or for an event or venue.
  ///
  /// With no arguments this returns the signed-in user's own galleries, which
  /// is what the profile Galleries tab needs.
  static Future<List<Map<String, dynamic>>> fetchGalleries({
    int? userId,
    String? entityType,
    int? entityId,
    int page = 1,
    int perPage = 20,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not signed in');

    final query = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      if (userId != null && userId > 0) 'user_id': '$userId',
      if (entityType != null && entityId != null && entityId > 0) ...{
        'entity_type': entityType,
        'entity_id': '$entityId',
      },
    };

    final response = await http.get(
      Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/galleries',
      ).replace(queryParameters: query),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load galleries (${response.statusCode})');
    }

    final body = jsonDecode(response.body);
    final list = (body is Map ? body['galleries'] : null) as List? ?? [];

    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<Map<String, dynamic>?> uploadCommunityGalleryImages({
    required String eventId,
    required List<ImageData> images,
    Function(double progress)? onProgress,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('❌ [EventsAPI] No token available');
        return null;
      }

      final uploadedIds = <String>[];
      final total = images.length;

      for (int i = 0; i < total; i++) {
        final imageData = images[i];
        if (imageData.file == null) continue;

        // Step 1 — mint a direct-upload URL
        final urlResponse = await http.post(
          Uri.parse(
            '${ApiConfig.baseUrl}/wp-json/app/v2/event-community-gallery/create-upload',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
        if (urlResponse.statusCode != 200) {
          throw Exception('Failed to get upload URL');
        }
        final urlData = jsonDecode(urlResponse.body);
        final uploadUrl = urlData['upload_url'] as String;
        final imageId = urlData['image_id'] as String;

        // Step 2 — upload straight to Cloudflare
        final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
        final file = imageData.file!;
        request.files.add(
          http.MultipartFile(
            'file',
            http.ByteStream(file.openRead()),
            await file.length(),
            filename: file.path.split('/').last,
          ),
        );

        final streamed = await request.send();
        final response = await http.Response.fromStream(streamed);
        if (response.statusCode != 200) {
          throw Exception('CF upload failed: ${response.statusCode}');
        }

        uploadedIds.add(imageId);
        onProgress?.call(
          ((i + 1) / total) * 90,
        ); // reserve last 10% for register
      }

      if (uploadedIds.isEmpty) {
        throw Exception('No images uploaded');
      }

      print(
        '✅ [EventsAPI] Uploaded ${uploadedIds.length} images, registering...',
      );
      print('Uploaded IDs: $uploadedIds');

      // Step 3 — register the batch against the event
      final registerResponse = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/wp-json/app/v2/event-community-gallery/register',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'event_id': int.parse(eventId),
          'media_ids': uploadedIds,
        }),
      );

      if (registerResponse.statusCode != 200) {
        throw Exception('Failed to register images');
      }

      onProgress?.call(100);
      return jsonDecode(registerResponse.body) as Map<String, dynamic>;
    } catch (e) {
      print('❌ [EventsAPI] Community gallery upload failed: $e');
      rethrow; // screen shows the error snackbar
    }
  }

  /// Deletes community gallery photos.
  ///
  /// The server is the authority on who may delete what — the uploader, or the
  /// event owner. [CommunityPhoto.canDelete] only decides whether to offer the
  /// control; a 403 here means the answer was no.
  ///
  /// Returns the row ids actually removed.
  static Future<List<int>> deleteCommunityGalleryImages({
    required List<int> imageIds,
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not signed in');

    final response = await http.post(
      Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/event-community-gallery/delete',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'image_ids': imageIds}),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 403) {
      throw Exception(
        body['message']?.toString() ?? 'You cannot delete that photo',
      );
    }

    if (response.statusCode != 200) {
      throw Exception('Could not delete (${response.statusCode})');
    }

    return (body['deleted'] as List<dynamic>? ?? const [])
        .map((e) => int.tryParse('$e') ?? 0)
        .where((id) => id != 0)
        .toList();
  }

  /// Sets the order of an event's community gallery. Event owner only.
  ///
  /// [imageIds] are row ids in the order they should appear. Ids left out keep
  /// no position and fall in behind the ordered ones, so the owner does not
  /// have to drag every photo in a large gallery to fix the top of it.
  /// Saves the order of a gallery's photos, owner only.
  ///
  /// Scoped by [galleryId] when given — one gallery's order — otherwise by
  /// entity, which orders the merged pool on that event or venue.
  static Future<void> reorderCommunityGallery({
    String? eventId,
    int? galleryId,
    required List<int> imageIds,
    String entityType = 'event',
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not signed in');

    final entityId = int.tryParse(eventId ?? '') ?? 0;
    final byGallery = galleryId != null && galleryId > 0;

    if (!byGallery && entityId <= 0) {
      throw Exception('Nothing to reorder');
    }

    final response = await http.post(
      Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/event-community-gallery/reorder',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        if (byGallery) 'gallery_id': galleryId,
        if (!byGallery) ...{
          'entity_type': entityType,
          'entity_id': entityId,
          if (entityType == 'event') 'event_id': entityId,
        },
        'image_ids': imageIds,
      }),
    );

    if (response.statusCode == 200) return;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(body['message']?.toString() ?? 'Could not save the order');
  }

  /// Picks the photo that represents this gallery — its cover, and what shows
  /// for it in the media tab in place of the event's own image.
  ///
  /// Owner only. Pass null for [imageId] to clear it. Scoped by [galleryId]
  /// when given, otherwise by entity.
  static Future<void> setCommunityGalleryCover({
    String? eventId,
    int? galleryId,
    required int? imageId,
    String entityType = 'event',
  }) async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not signed in');

    final entityId = int.tryParse(eventId ?? '') ?? 0;
    final byGallery = galleryId != null && galleryId > 0;

    if (!byGallery && entityId <= 0) {
      throw Exception('Nothing to set a cover on');
    }

    final response = await http.post(
      Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/event-community-gallery/set-cover',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        if (byGallery) 'gallery_id': galleryId,
        if (!byGallery) ...{
          'entity_type': entityType,
          'entity_id': entityId,
          if (entityType == 'event') 'event_id': entityId,
        },
        'image_id': imageId ?? 0,
      }),
    );

    if (response.statusCode == 200) return;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(body['message']?.toString() ?? 'Could not set the cover');
  }

  /// Photos in a gallery.
  ///
  /// Addressable two ways: by [galleryId] for one specific gallery — the only
  /// way to reach one that is tagged to nothing — or by entity, which merges
  /// every gallery on that event or venue as before.
  static Future<Map<String, dynamic>?> fetchCommunityGallery({
    String? eventId,
    int? galleryId,
    int page = 1,
    int perPage = 30,
    String entityType = 'event',
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('❌ [EventsAPI] No token available');
        return null;
      }

      final entityId = int.tryParse(eventId ?? '') ?? 0;
      final byGallery = galleryId != null && galleryId > 0;

      if (!byGallery && entityId <= 0) {
        print('❌ [EventsAPI] fetchCommunityGallery needs a gallery or entity');
        return null;
      }

      final response = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/wp-json/app/v2/event-community-gallery/list',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          if (byGallery) 'gallery_id': galleryId,
          if (!byGallery) ...{
            'entity_type': entityType,
            'entity_id': entityId,
            if (entityType == 'event') 'event_id': entityId,
          },
          'page': page,
          'per_page': perPage,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('❌ [EventsAPI] fetchCommunityGallery failed: $e');
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
      final token = await _authService.getToken();
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
      final token = await _authService.getToken();
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

  /// Cancel an event
  static Future<Map<String, dynamic>?> cancelEvent({
    required String eventId,
    required String site,
  }) async {
    try {
      // Get user and token
      final token = await _authService.getToken();
      if (token == null) {
        print('❌ [EventDetailService] No user found for cancel event');
        return null;
      }

      // Make API request
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/ce-cancel-event',
      );

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'event_id': eventId, 'country': site}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        print('✅ [EventDetailService] Event cancelled successfully');
        return data;
      } else {
        print(
          '❌ [EventDetailService] Failed to cancel event: ${response.statusCode}',
        );
        throw Exception('Failed to cancel event: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [EventDetailService] Error cancelling event: $e');
      return null;
    }
  }

  /// Delete an event
  static Future<Map<String, dynamic>?> deleteEvent({
    required String eventId,
    required String site,
  }) async {
    try {
      // Get user and token
      final token = await _authService.getToken();

      if (token == null) {
        print('❌ [EventDetailService] No user found for delete event');
        return null;
      }

      // Make API request
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/ce-delete-event',
      );

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'event_id': eventId, 'country': site}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        print('✅ [EventDetailService] Event deleted successfully');
        return data;
      } else {
        print(
          '❌ [EventDetailService] Failed to delete event: ${response.statusCode}',
        );
        throw Exception('Failed to delete event: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [EventDetailService] Error deleting event: $e');
      return null;
    }
  }

  /// Fetches event details for the owner with 5-minute caching
  static Future<Map<String, dynamic>?> getProfileEventForOwner({
    required String eventId,
    required String site,
  }) async {
    try {
      // // Check cache first
      // final cachedData = await _getCachedData(eventId);
      // if (cachedData != null) {
      //   return cachedData;
      // }

      final user = await _authService.getUser();
      final token = await _authService.getToken();

      if (user == null || token == null) {
        print('❌ [EventsAPI] No user found');
        return null;
      }

      final userId = user['id'];

      // Make API request
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/wp-json/app/v2/get-profile-event-for-owner?user_id=$userId&event_id=$eventId&country=$site',
      );

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // // Cache the response
        // await _cacheData(eventId, data);

        return data;
      } else {
        throw Exception('Failed to load event details: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching event details: $e');
      rethrow;
    }
  }
}
