class VenueDetail {
  final String id;
  final String title;
  final String location;
  final String? description;
  final VenueCoverPhoto coverPhoto;
  final VenueLogo logo;
  final List<VenueEvent> events;
  final bool isFollowing;
  final bool isOwner;
  final String status;

  // Socials
  final String? venueEmail;
  final String? venuePhone;
  final String? website;
  final String? facebook;
  final String? instagram;

  VenueDetail({
    required this.id,
    required this.title,
    required this.location,
    this.description,
    required this.coverPhoto,
    required this.logo,
    required this.events,
    required this.isFollowing,
    required this.isOwner,
    required this.status,
    this.venueEmail,
    this.venuePhone,
    this.website,
    this.facebook,
    this.instagram,
  });

  factory VenueDetail.fromJson(Map<String, dynamic> json) {
    try {
      return VenueDetail(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        location: json['location']?.toString() ?? '',
        description: json['description']?.toString(),
        coverPhoto: VenueCoverPhoto.fromJson(json['cover_photo'] ?? {}),
        logo: VenueLogo.fromJson(json['logo'] ?? {}),
        events:
            (json['events'] as List?)
                ?.map((e) => VenueEvent.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        isFollowing: json['is_following'] == true,
        isOwner: json['is_owner'] == true,
        venueEmail: json['venue_email']?.toString(),
        venuePhone: json['venue_phone']?.toString(),
        website: json['website']?.toString(),
        facebook: json['facebook']?.toString(),
        instagram: json['instagram']?.toString(),
        status: json['status']?.toString() ?? '',
      );
    } catch (e) {
      print('❌ Error parsing VenueDetail: $e');
      print('JSON: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'location': location,
      'description': description,
      'cover_photo': coverPhoto.toJson(),
      'logo': logo.toJson(),
      'events': events.map((e) => e.toJson()).toList(),
      'is_following': isFollowing,
      'venue_email': venueEmail,
      'venue_phone': venuePhone,
      'website': website,
      'facebook': facebook,
      'instagram': instagram,
      'is_owner': isOwner,
      'status': status,
    };
  }
}

class VenueCoverPhoto {
  final String id;
  final String type;
  final String url;
  final String alt;

  VenueCoverPhoto({
    required this.id,
    required this.type,
    required this.url,
    required this.alt,
  });

  factory VenueCoverPhoto.fromJson(Map<String, dynamic> json) {
    return VenueCoverPhoto(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'image',
      url: json['url']?.toString() ?? '',
      alt: json['alt']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'type': type, 'url': url, 'alt': alt};
  }
}

class VenueLogo {
  final String id;
  final String url;

  VenueLogo({required this.id, required this.url});

  factory VenueLogo.fromJson(Map<String, dynamic> json) {
    return VenueLogo(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'url': url};
  }
}

class VenueEvent {
  final int id;
  final String title;
  final String startDate;
  final String location;
  final String endDate;
  final String entryType;
  final String thumbnail;
  final String? ticketsUrl;

  VenueEvent({
    required this.id,
    required this.title,
    required this.startDate,
    required this.location,
    required this.endDate,
    required this.entryType,
    required this.thumbnail,
    this.ticketsUrl,
  });

  factory VenueEvent.fromJson(Map<String, dynamic> json) {
    return VenueEvent(
      id: json['id'] ?? 0,
      title: json['title']?.toString() ?? '',
      startDate: json['start_date']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      endDate: json['end_date']?.toString() ?? '',
      entryType: json['entry_type']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
      ticketsUrl: json['tickets_url']?.toString(),
    );
  }

  // Format date helper
  String getFormattedDate() {
    try {
      final date = DateTime.parse(startDate);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];

      // Get ordinal suffix
      String getOrdinal(int day) {
        if (day >= 11 && day <= 13) return 'th';
        switch (day % 10) {
          case 1:
            return 'st';
          case 2:
            return 'nd';
          case 3:
            return 'rd';
          default:
            return 'th';
        }
      }

      return '${date.day}${getOrdinal(date.day)} ${months[date.month - 1]} ${date.year}';
    } catch (e) {
      return startDate;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'start_date': startDate,
      'location': location,
      'end_date': endDate,
      'entry_type': entryType,
      'thumbnail': thumbnail,
      'tickets_url': ticketsUrl,
    };
  }
}
