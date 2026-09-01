import 'package:drivelife/models/event_editor_models.dart';
import 'package:flutter/foundation.dart';

/// A whole event, as returned by `GET dl-accounts/v1/event-edit`.
///
/// The response is already grouped the way the editor thinks — `basics`,
/// `dates`, `description`, `media`, `tickets`, `discounts`, `show_cars`,
/// `car_clubs`, `traders`, `publish` — so this mirrors that rather than
/// flattening it. Only the fields the app can currently show are pulled out;
/// [raw] keeps the untouched response so nothing is lost while the remaining
/// tabs catch up.
class EventEditData {
  final int eventId;

  /// The encrypted id this event must be addressed by. Round-tripped so a
  /// later save can reach the same endpoint.
  final String encryptedId;
  final String postType;

  // ── basics ──
  final String title;
  final List<String> categoryIds;
  final String location;
  final double? lat;
  final double? lng;

  // ── dates ──
  final DateTime? startDate;
  final DateTime? endDate;
  final String? startTime; // "HH:MM"
  final String? endTime;
  final String timezone;
  final bool isRecurring;

  // ── description ──
  final String description;
  final String websiteUrl;
  final String publicEmail;
  final String publicPhone;
  final String facebookUrl;
  final String instagramUrl;
  final String tiktokUrl;

  // ── media ──
  final String? coverImageUrl;
  final List<String> galleryUrls;

  // ── tickets ──
  final int ticketType;
  final String entryDetails;
  final String externalTicketsUrl;
  final String externalEntryDetails;

  // ── publish ──
  final String status;
  final int visibility;
  final String permalink;

  /// Discounts, show cars, car clubs and traders — the four sections the app's
  /// own endpoint has no fields for.
  final EventExtrasDraft extras;

  /// The undecoded response, for fields not yet surfaced.
  final Map<String, dynamic> raw;

  const EventEditData({
    required this.eventId,
    required this.encryptedId,
    required this.postType,
    required this.title,
    required this.categoryIds,
    required this.location,
    required this.lat,
    required this.lng,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.timezone,
    required this.isRecurring,
    required this.description,
    required this.websiteUrl,
    required this.publicEmail,
    required this.publicPhone,
    required this.facebookUrl,
    required this.instagramUrl,
    required this.tiktokUrl,
    required this.coverImageUrl,
    required this.galleryUrls,
    required this.ticketType,
    required this.entryDetails,
    required this.externalTicketsUrl,
    required this.externalEntryDetails,
    required this.status,
    required this.visibility,
    required this.permalink,
    required this.extras,
    required this.raw,
  });

  static Map<String, dynamic> _block(Map<String, dynamic> json, String key) =>
      json[key] as Map<String, dynamic>? ?? const {};

  static String _str(dynamic value) => value?.toString() ?? '';

  static double? _double(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int _int(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  /// Pulls a URL out of a media entry, which may be a plain string or an
  /// object carrying `url`.
  static String? _mediaUrl(dynamic value) {
    if (value == null) return null;
    if (value is String) return value.isEmpty ? null : value;
    if (value is Map) {
      final url = value['url']?.toString();
      return (url == null || url.isEmpty) ? null : url;
    }
    return null;
  }

  factory EventEditData.fromResponse(Map<String, dynamic> json) {
    final basics = _block(json, 'basics');
    final dates = _block(json, 'dates');
    final description = _block(json, 'description');
    final media = _block(json, 'media');
    final tickets = _block(json, 'tickets');
    final publish = _block(json, 'publish');

    final coords = basics['location_coords'] as Map<String, dynamic>?;

    // The window lives in `date_rows`; the app currently shows a single row, so
    // the first is used and the rest kept in [raw] until the Dates tab can
    // handle multi-day and recurring events the way the dashboard does.
    final rows = dates['date_rows'] as List<dynamic>? ?? const [];
    final firstRow = rows.isEmpty
        ? const <String, dynamic>{}
        : (rows.first as Map<String, dynamic>? ?? const {});

    if (rows.length > 1) {
      debugPrint(
        'EventEditData: event has ${rows.length} date rows; the app shows the '
        'first only.',
      );
    }

    final gallery = (media['gallery'] as List<dynamic>? ?? const [])
        .map(_mediaUrl)
        .whereType<String>()
        .toList();

    return EventEditData(
      eventId: _int(json['event_id']),
      encryptedId: _str(json['encrypted_id']),
      postType: _str(json['post_type']),

      title: _str(basics['title']),
      categoryIds: (basics['category_ids'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      location: _str(basics['location']),
      lat: _double(coords?['lat'] ?? coords?['latitude']),
      lng: _double(coords?['lng'] ?? coords?['longitude']),

      startDate: DateTime.tryParse(_str(firstRow['start_date'])),
      endDate: DateTime.tryParse(_str(firstRow['end_date'])),
      startTime: _str(firstRow['start_time']).isEmpty
          ? null
          : _str(firstRow['start_time']),
      endTime: _str(firstRow['end_time']).isEmpty
          ? null
          : _str(firstRow['end_time']),
      timezone: _str(dates['timezone']),
      isRecurring: dates['is_recurring'] == true,

      description: _str(description['description']),
      websiteUrl: _str(description['website_url']),
      publicEmail: _str(description['public_email']),
      publicPhone: _str(description['public_phone']),
      facebookUrl: _str(description['facebook_url']),
      instagramUrl: _str(description['instagram_url']),
      tiktokUrl: _str(description['tiktok_url']),

      coverImageUrl: _mediaUrl(media['cover_image']),
      galleryUrls: gallery,

      ticketType: _int(tickets['ticket_type'], fallback: 1),
      entryDetails: _str(tickets['entry_details']),
      externalTicketsUrl: _str(tickets['external_tickets_url']),
      externalEntryDetails: _str(tickets['external_entry_details']),

      status: _str(publish['status']).isEmpty
          ? 'draft'
          : _str(publish['status']),
      visibility: _int(publish['visibility'], fallback: 1),
      permalink: _str(publish['permalink']),

      extras: EventExtrasDraft(
        discounts: (json['discounts'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EventDiscount.fromJson)
            .toList(),
        showCars: ShowCarsConfig.fromJson(_block(json, 'show_cars')),
        carClubs: CarClubsConfig.fromJson(_block(json, 'car_clubs')),
        traders: TradersConfig.fromJson(_block(json, 'traders')),
      ),

      raw: json,
    );
  }

  /// One-line summary for checking a pull went as expected.
  String get debugSummary =>
      'EventEditData(#$eventId "$title", ${categoryIds.length} categories, '
      '${galleryUrls.length} gallery images, '
      '${extras.discounts.length} discounts, '
      'showCars=${extras.showCars.enabled}'
      '(${extras.showCars.categories.length}), '
      'carClubs=${extras.carClubs.enabled}, '
      'traders=${extras.traders.enabled}'
      '(${extras.traders.categories.length}), '
      'status=$status)';
}
