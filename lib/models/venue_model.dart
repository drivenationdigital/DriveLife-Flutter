class Venue {
  final String id;
  final String title;
  final String coverImage;
  final String logo;
  final String venueLocation;
  final double distance;
  final String site;
  final bool? isOwner;

  Venue({
    required this.id,
    required this.title,
    required this.coverImage,
    required this.logo,
    required this.venueLocation,
    required this.distance,
    required this.site,
    this.isOwner,
  });

  factory Venue.fromJson(Map<String, dynamic> json) {
    try {
      return Venue(
        id: json['ID']?.toString() ?? '',
        title: _parseString(json['title']),
        coverImage: _parseString(json['cover_image']),
        logo: _parseString(json['logo']),
        venueLocation: _parseVenueLocation(json['venue_location']),
        distance: _parseDistance(json['distance']),
        site: _parseString(json['site']),
        isOwner: json['is_owner'] != null
            ? (json['is_owner'] is bool
                  ? json['is_owner']
                  : (json['is_owner'].toString().toLowerCase() == 'true'))
            : null,
      );
    } catch (e) {
      print('❌ Error parsing venue: $e');
      print('JSON: $json');
      rethrow;
    }
  }

  static String _parseString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  static String _parseVenueLocation(dynamic location) {
    if (location == null) return '';
    if (location is String) return location;
    if (location is Map) {
      // If it's a map, try to extract address or formatted_address
      return location['address'] ??
          location['formatted_address'] ??
          location['name'] ??
          '';
    }
    return location.toString();
  }

  static double _parseDistance(dynamic distance) {
    if (distance == null) return 0.0;
    if (distance is double) return distance;
    if (distance is int) return distance.toDouble();
    if (distance is String) return double.tryParse(distance) ?? 0.0;
    return 0.0;
  }

  Map<String, dynamic> toJson() {
    return {
      'ID': id,
      'title': title,
      'cover_image': coverImage,
      'logo': logo,
      'venue_location': venueLocation,
      'distance': distance,
      'site': site,
      'is_owner': isOwner,
    };
  }
}

class VenuesResponse {
  final List<Venue> data;
  final int totalPages;
  final int page;
  final int limit;
  final String filter;
  final VenuesResponseOther? other;

  VenuesResponse({
    required this.data,
    required this.totalPages,
    required this.page,
    required this.limit,
    required this.filter,
    this.other,
  });

  factory VenuesResponse.fromJson(Map<String, dynamic> json) {
    try {
      List<Venue> venues = [];

      if (json['data'] != null && json['data'] is List) {
        final dataList = json['data'] as List;
        for (var item in dataList) {
          try {
            if (item is Map<String, dynamic>) {
              venues.add(Venue.fromJson(item));
            }
          } catch (e) {
            print('❌ Error parsing individual venue: $e');
            print('Venue data: $item');
            // Continue processing other venues
          }
        }
      }

      return VenuesResponse(
        data: venues,
        totalPages: json['total_pages'] ?? 0,
        page: json['page'] ?? 1,
        limit: json['limit'] ?? 10,
        filter: json['filter']?.toString() ?? '{}',
        other: json['other'] != null
            ? VenuesResponseOther.fromJson(
                json['other'] as Map<String, dynamic>,
              )
            : null,
      );
    } catch (e) {
      print('❌ Error parsing VenuesResponse: $e');
      print('Full JSON: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data.map((e) => e.toJson()).toList(),
      'total_pages': totalPages,
      'page': page,
      'limit': limit,
      'filter': filter,
      'other': other?.toJson(),
    };
  }
}

class VenuesResponseOther {
  final int offset;
  final double lat;
  final double lng;
  final int radius;

  VenuesResponseOther({
    required this.offset,
    required this.lat,
    required this.lng,
    required this.radius,
  });

  factory VenuesResponseOther.fromJson(Map<String, dynamic> json) {
    return VenuesResponseOther(
      offset: json['offset'] ?? 0,
      lat: _parseDouble(json['lat']),
      lng: _parseDouble(json['lng']),
      radius: json['radius'] ?? 0,
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  Map<String, dynamic> toJson() {
    return {'offset': offset, 'lat': lat, 'lng': lng, 'radius': radius};
  }
}
