/// Models backing the Media tab.
///
/// [PendingImage] maps `app/v2/media-matches` (dl-media-matches.php).
/// [EventGallery] and [PopularImage] map `app/v2/media-galleries` and
/// `app/v2/media-popular` (dl-media-sections.php).
library;

/// A photo the AI matched to one of your garage vehicles, awaiting your call.
class PendingImage {
  /// Cloudflare media ID — the primary key on the recognition table.
  final String id;
  final String imageUrl;

  /// Poster's username, without the leading `@`.
  final String username;
  final String? userAvatarUrl;
  final bool userVerified;

  /// Venue or event the photo was taken at. Null when the post had no location.
  final String? locationName;

  /// Server-formatted upload time, e.g. "Added 2 hours ago".
  final String addedLabel;

  /// The post this photo belongs to, for opening it from the review screen.
  final int? postId;

  /// True when the AI matched visually at only Medium confidence, so the
  /// backend flagged it as worth a closer look.
  final bool flagged;

  const PendingImage({
    required this.id,
    required this.imageUrl,
    required this.username,
    required this.addedLabel,
    this.userAvatarUrl,
    this.userVerified = false,
    this.locationName,
    this.postId,
    this.flagged = false,
  });

  factory PendingImage.fromJson(Map<String, dynamic> json) {
    final poster = (json['posted_by'] as Map<String, dynamic>?) ?? const {};
    final match = (json['match'] as Map<String, dynamic>?) ?? const {};

    return PendingImage(
      id: json['media_id']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      username: poster['username']?.toString() ?? 'someone',
      userAvatarUrl: _nonEmpty(poster['profile_image']),
      userVerified: poster['user_verified'] == true,
      locationName: _nonEmpty(json['location_name']),
      addedLabel: json['added_label']?.toString() ?? '',
      postId: _asInt(json['post_id']),
      flagged: match['flagged'] == true,
    );
  }

  /// Null for missing, null-literal, or blank strings — the API sends all three
  /// for an absent avatar or location depending on how the row was written.
  static String? _nonEmpty(dynamic value) {
    final s = value?.toString().trim();
    return (s == null || s.isEmpty || s == 'null') ? null : s;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

/// One page of matches plus the whole-queue counts the UI shows as badges.
class PendingImagesResponse {
  final List<PendingImage> data;
  final int pending;
  final int accepted;
  final int declined;
  final int total;
  final int page;
  final int totalPages;

  const PendingImagesResponse({
    this.data = const [],
    this.pending = 0,
    this.accepted = 0,
    this.declined = 0,
    this.total = 0,
    this.page = 1,
    this.totalPages = 0,
  });

  bool get hasMore => page < totalPages;

  factory PendingImagesResponse.fromJson(Map<String, dynamic> json) {
    final counts = (json['counts'] as Map<String, dynamic>?) ?? const {};

    return PendingImagesResponse(
      data: ((json['data'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PendingImage.fromJson)
          .where((image) => image.id.isNotEmpty)
          .toList(),
      pending: _asInt(counts['pending']),
      accepted: _asInt(counts['accepted']),
      declined: _asInt(counts['declined']),
      total: _asInt(json['total']),
      page: _asInt(json['page'], fallback: 1),
      totalPages: _asInt(json['total_pages']),
    );
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

/// A gallery card in the media tab.
class EventGallery {
  /// The gallery itself. Null for a padded "no photos yet" card, which stands
  /// for an event that has no gallery to open.
  ///
  /// Cards used to be addressed by entity, which meant permission resolved to
  /// the EVENT owner — so a gallery's own owner could not curate their own
  /// photos when they reached it from here.
  final int? galleryId;

  final int eventId;
  final String title;
  final String? coverImageUrl;
  final String? locationName;
  final String? dateLabel;
  final int photoCount;

  /// Name the uploader gave the batch, when there is one. Null for photos
  /// added from an event's own gallery tab, which has no name field.
  final String? galleryName;

  /// Which blog the event lives on - 3 UK, 1 US. An event id only means
  /// anything within its own blog, so this is what makes opening it reliable.
  final int? blogId;

  /// 'event' or 'venue'. A gallery can hang off either, and they open on
  /// different screens - opening a venue as an event is what produced
  /// "failed to load event".
  final String entityType;

  const EventGallery({
    this.galleryId,
    required this.eventId,
    required this.title,
    this.coverImageUrl,
    this.locationName,
    this.dateLabel,
    this.photoCount = 0,
    this.galleryName,
    this.blogId,
    this.entityType = 'event',
  });

  bool get isVenue => entityType == 'venue';

  /// What to show as the card's heading: the gallery's own name when the
  /// uploader gave one, otherwise the event it belongs to.
  String get displayTitle =>
      (galleryName != null && galleryName!.isNotEmpty) ? galleryName! : title;

  /// 'GB' or 'US', for the calls that address events by site.
  String get site => blogId == 1 ? 'US' : 'GB';

  /// "Hardwick Hall · 31/05/2026", dropping whichever half is missing.
  String get subtitle => [
    locationName,
    dateLabel,
  ].where((s) => s != null && s.isNotEmpty).join(' · ');

  /// A real gallery, as opposed to an upcoming-event placeholder.
  bool get isGallery => galleryId != null && galleryId! > 0;

  factory EventGallery.fromJson(Map<String, dynamic> json) => EventGallery(
    galleryId: json['gallery_id'] == null ? null : _int(json['gallery_id']),
    eventId: _int(json['event_id']),
    title: json['title']?.toString() ?? 'Event',
    coverImageUrl: _str(json['cover_image']),
    locationName: _str(json['location']),
    dateLabel: _str(json['date_label']),
    photoCount: _int(json['photo_count']),
    galleryName: _str(json['gallery_name']),
    blogId: json['blog_id'] == null ? null : _int(json['blog_id']),
    // Older API builds send no entity_type; those rows are all events.
    entityType: _str(json['entity_type']) ?? 'event',
  );
}

/// Event galleries plus how the backend sourced them.
class EventGalleriesResponse {
  final List<EventGallery> data;

  /// True when no event has photos yet and these are suggestions to seed.
  final bool isFallback;

  const EventGalleriesResponse({this.data = const [], this.isFallback = false});

  /// The row is padded with upcoming events that have nothing uploaded yet, so
  /// the hint explaining the empty cards is worth showing.
  bool get hasEmptyGalleries => data.any((g) => g.photoCount == 0);

  factory EventGalleriesResponse.fromJson(Map<String, dynamic> json) =>
      EventGalleriesResponse(
        data: ((json['data'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EventGallery.fromJson)
            .toList(),
        isFallback: json['source']?.toString() == 'upcoming',
      );
}

/// A single tile in the "Popular images" grid.
class PopularImage {
  final int postId;
  final String imageUrl;
  final int likesCount;

  const PopularImage({
    required this.postId,
    required this.imageUrl,
    this.likesCount = 0,
  });

  factory PopularImage.fromJson(Map<String, dynamic> json) => PopularImage(
    postId: _int(json['post_id']),
    imageUrl: _str(json['thumbnail']) ?? _str(json['image_url']) ?? '',
    likesCount: _int(json['likes_count']),
  );
}

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

String? _str(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty || s == 'null') ? null : s;
}
