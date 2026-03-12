import 'dart:convert';
import 'dart:typed_data';
import 'package:drivelife/config/api_config.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:http/http.dart' as http;


class EventOffer {
  final int id;
  final String title;
  final String subtitle;
  final String description;
  final String locationName;
  final String validFrom;
  final String validTo;
  final String? imageUrl;

  const EventOffer({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.locationName,
    required this.validFrom,
    required this.validTo,
    this.imageUrl,
  });

  factory EventOffer.fromJson(Map<String, dynamic> json) {
    return EventOffer(
      id: json['id'] as int,
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      locationName: (json['location_name'] ?? '').toString(),
      validFrom: (json['valid_from'] ?? '').toString(),
      validTo: (json['valid_to'] ?? '').toString(),
      imageUrl: json['image_url'] as String?,
    );
  }

  @override
  String toString() => 'EventOffer(id: $id, title: $title)';
}

class OffersResult {
  final List<EventOffer> offers;
  final String? error;

  bool get hasError => error != null;

  const OffersResult({required this.offers, this.error});

  const OffersResult.success(this.offers) : error = null;
  const OffersResult.failure(this.error) : offers = const [];
}

class OffersApi {
  static final AuthService _authService = AuthService();

  static Future<OffersResult?> getPossibleEventOffers() async {
     final token = await _authService.getToken();
    final user = await _authService.getUser();

    if (token == null || user == null) {
      print('❌ [EventsAPI] No token or user found');
      return null;
    }

    // Handle last_location being either a Map or an empty array
    final lastLocation = user['last_location'];
    final isLocationValid = lastLocation is Map && lastLocation.isNotEmpty;

    final userCountry = isLocationValid
        ? (lastLocation['country'] ?? 'GB')
        : 'GB';
  
    final userLat =isLocationValid ? lastLocation['latitude'] : null;
    final userLng = isLocationValid ? lastLocation['longitude'] : null;

    print('📍 [OffersAPI] Fetching offers for country: $userCountry, lat: $userLat, lng: $userLng');

    final uri = Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/get-possible-event-offers');

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            // Body can be empty — auth is header-based
            body: jsonEncode({
              'country': userCountry,
              if (userLat != null && userLng != null)
                'location': {'latitude': userLat, 'longitude': userLng},
            }),
          )
          .timeout(const Duration(seconds: 15));

      final body = _parseBody(response.body);
      print('📦 [OffersAPI] Response: ${response.statusCode}, body: $body');

      if (response.statusCode == 401) {
        return OffersResult.failure(
          body?['error']?.toString() ?? 'Unauthorised',
        );
      }

      if (response.statusCode != 200) {
        return OffersResult.failure('Server error (${response.statusCode})');
      }

      if (body == null) {
        return const OffersResult.failure('Invalid response from server');
      }

      if (body['success'] != true) {
        return OffersResult.failure(
          body['error']?.toString() ?? 'Unknown error',
        );
      }

      final raw = body['offers'];
      if (raw == null || raw is! List) {
        return const OffersResult.success([]);
      }

      final offers = raw
          .whereType<Map<String, dynamic>>()
          .map(EventOffer.fromJson)
          .toList();

      return OffersResult.success(offers);
    } on http.ClientException catch (e) {
      return OffersResult.failure('Network error: ${e.message}');
    } catch (e) {
      return OffersResult.failure('Unexpected error: $e');
    }
  }

  static Future<OfferRedemptionResult> getRedemptionDetails({
    required int offerId,
  }) async {
    final token = await _authService.getToken();
    if (token == null) {
      return OfferRedemptionResult.failure('Not authenticated');
    }

    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/wp-json/app/v2/get-offer-redemption'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'offer_id': offerId}),
          )
          .timeout(const Duration(seconds: 15));

      final body = _parseBody(res.body);
      if (body == null) {
        return OfferRedemptionResult.failure('Invalid response');
      }

      if (res.statusCode == 401) {
        return OfferRedemptionResult.failure(body['error'] ?? 'Unauthorised');
      }

      if (body['success'] != true) {
        if (body['error'] == 'already_redeemed') {
          return OfferRedemptionResult.redeemed(
            body['redeemed_at']?.toString() ?? '',
          );
        }
        return OfferRedemptionResult.failure(
          body['error']?.toString() ?? 'Unknown error',
        );
      }

      final offer = (body['offer'] as Map).cast<String, dynamic>();
      final qr = (body['qr'] as Map).cast<String, dynamic>();

      // Decode base64 PNG if present
      Uint8List? qrBytes;
      final b64 = qr['base64_png']?.toString() ?? '';
      if (b64.isNotEmpty) {
        try {
          qrBytes = base64Decode(b64);
        } catch (_) {}
      }

      return OfferRedemptionResult.success(
        OfferRedemptionData(
          id: offer['id'] as int,
          title: offer['title']?.toString() ?? '',
          subtitle: offer['subtitle']?.toString() ?? '',
          description: offer['description']?.toString() ?? '',
          locationName: offer['location_name']?.toString() ?? '',
          imageUrl: offer['image_url']?.toString(),
          validFrom: offer['valid_from']?.toString() ?? '',
          validTo: offer['valid_to']?.toString() ?? '',
          qrBytes: qrBytes,
          qrUrl: qr['url']?.toString(),
          qrPayload: qr['payload']?.toString() ?? '',
        ),
      );
    } on http.ClientException catch (e) {
      return OfferRedemptionResult.failure('Network error: ${e.message}');
    } catch (e) {
      return OfferRedemptionResult.failure('Unexpected error: $e');
    }
  }

  static Map<String, dynamic>? _parseBody(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

class OfferRedemptionData {
  final int id;
  final String title;
  final String subtitle;
  final String description;
  final String locationName;
  final String? imageUrl;
  final String validFrom;
  final String validTo;
 
  // QR — one of these will be non-null
  final Uint8List? qrBytes;   // server-generated PNG as bytes
  final String? qrUrl;        // fallback network URL
  final String qrPayload;     // raw encrypted string (client-side fallback)
 
  const OfferRedemptionData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.locationName,
    this.imageUrl,
    required this.validFrom,
    required this.validTo,
    this.qrBytes,
    this.qrUrl,
    required this.qrPayload,
  });
 
  bool get hasServerQr => qrBytes != null;
}
 
class OfferRedemptionResult {
  final OfferRedemptionData? data;
  final String? error;
  final bool alreadyRedeemed;
  final String? redeemedAt;
 
  bool get hasError => error != null;
 
  const OfferRedemptionResult._({
    this.data,
    this.error,
    this.alreadyRedeemed = false,
    this.redeemedAt,
  });
 
  factory OfferRedemptionResult.success(OfferRedemptionData d) =>
      OfferRedemptionResult._(data: d);
 
  factory OfferRedemptionResult.failure(String e) =>
      OfferRedemptionResult._(error: e);
 
  factory OfferRedemptionResult.redeemed(String at) =>
      OfferRedemptionResult._(
        error: 'already_redeemed',
        alreadyRedeemed: true,
        redeemedAt: at,
      );
}
 