/// One of DriveLife's own long-form videos.
///
/// ── WHY IT CARRIES A postId ─────────────────────────────────────────
///
/// Because likes and comments already exist, and they key off a post.
/// InteractionsAPI.fetchComments, addComment, maybeLikePost and the
/// whole CommentItem widget all take a post id and nothing else.
///
/// So a video is a POST of its own kind on the server, not a separate
/// thing with its own parallel social stack. That decision buys the
/// entire comment system - replies, likes on comments, image comments,
/// moderation, deletion, notifications - for free, and it means a
/// comment on a video behaves exactly like every other comment in the
/// app because it IS one.
///
/// The alternative, a `video_comments` table, would have been a second
/// implementation of something hard that is already finished.
class LongVideo {
  /// The post this video is, for likes and comments.
  final String postId;

  final String title;

  /// The blurb under the title on the watch screen. Often empty.
  final String description;

  /// Still shown on the card and behind the player before it starts.
  final String thumbnailUrl;

  /// The file itself. Empty means the video is not playable yet, which
  /// is a real state on a card whose upload is still processing.
  final String videoUrl;

  /// How long it runs. Zero means nobody told us - the card then shows
  /// no duration rather than "0:00", which reads as broken.
  final int durationSeconds;

  final DateTime? publishedAt;

  final int likeCount;
  final int commentCount;

  /// Whether the signed-in person has liked it.
  final bool liked;

  /// Who it is by, for the line under the title.
  final String authorName;
  final String authorAvatar;

  /// The uploader, so an admin can be offered Delete on their own.
  final int authorId;

  /// How many times somebody actually watched it.
  final int viewCount;

  /// Whether [thumbnailUrl] was chosen by hand rather than taken from
  /// the video. Only the edit screen cares - everything else just
  /// draws whatever thumbnailUrl holds.
  final bool hasCustomThumbnail;

  /// Where the video actually lives: 'cloudflare' or 'youtube'.
  ///
  /// ── WHY A STRING AND NOT A BOOL ─────────────────────────────────
  ///
  /// isYoutube would do everything the app needs today, and would be
  /// the wrong shape the first time a third source appears. The server
  /// sends a word; this keeps the word.
  ///
  /// Defaults to Cloudflare, so a payload from a server that has not
  /// been updated yet - and every row created before this existed -
  /// reads correctly rather than as an unknown kind.
  final String source;

  /// Whether this is the hero on the Watch tab.
  ///
  /// One video carries it at a time - see dl_videos_set_featured in
  /// endpoints/videos.php. Nothing is featured on a fresh
  /// installation, and the screen falls back to the newest video
  /// until somebody chooses one.
  final bool isFeatured;

  /// Whether YouTube calls this a Short.
  ///
  /// Decided once when the video is stored, not from its length -
  /// Shorts were a minute, then three, and plenty of ordinary videos
  /// are shorter than that. See dl_videos_is_youtube_short.
  final bool isShort;

  /// Whether this is an episode of the DriveLife podcast.
  ///
  /// Decided entirely by who published it - see DL_PODCAST_USER_IDS in
  /// endpoints/videos.php. There is no podcast flag on an upload and
  /// nothing for anybody to tick: the same video published by somebody
  /// else would simply not be an episode.
  final bool isPodcast;

  /// The eleven-character YouTube id, for a YouTube-backed video.
  ///
  /// Empty for a Cloudflare one. The watch screen prefers this over
  /// parsing [videoUrl], and falls back to parsing when an older
  /// server sends the URL without the id.
  final String youtubeId;

  const LongVideo({
    required this.postId,
    required this.title,
    this.description = '',
    this.thumbnailUrl = '',
    this.videoUrl = '',
    this.durationSeconds = 0,
    this.publishedAt,
    this.likeCount = 0,
    this.commentCount = 0,
    this.liked = false,
    this.authorName = '',
    this.authorAvatar = '',
    this.authorId = 0,
    this.viewCount = 0,
    this.hasCustomThumbnail = false,
    this.source = 'cloudflare',
    this.youtubeId = '',
    this.isPodcast = false,
    this.isFeatured = false,
    this.isShort = false,
  });

  bool get isPlayable => videoUrl.isNotEmpty;

  /// Whether this one plays in a YouTube embed rather than from
  /// Cloudflare Stream.
  bool get isYoutube => source == 'youtube';

  /// Duration as somebody reads it: "8:04", or "1:12:30" past an hour.
  ///
  /// Empty when unknown, so the caller can leave the line out entirely
  /// rather than print a zero.
  String get lengthLabel => formatDuration(durationSeconds);

  /// The same formatting for a position inside the video, where zero
  /// IS meaningful and has to render.
  static String formatPosition(int seconds) {
    final value = seconds < 0 ? 0 : seconds;
    final hours = value ~/ 3600;
    final minutes = (value % 3600) ~/ 60;
    final secs = value % 60;

    final two = secs.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$two';
    }

    return '$minutes:$two';
  }

  /// Views, as somebody reads them: 942, 1.2K, 3.4M.
  ///
  /// Empty for zero. A brand new video saying "0 views" is a fact
  /// nobody needs and reads as a judgement on it.
  String get viewLabel {
    if (viewCount <= 0) return '';

    if (viewCount < 1000) return '$viewCount views';

    if (viewCount < 1000000) {
      final thousands = viewCount / 1000;

      return '${thousands.toStringAsFixed(thousands < 10 ? 1 : 0)}K views';
    }

    final millions = viewCount / 1000000;

    return '${millions.toStringAsFixed(millions < 10 ? 1 : 0)}M views';
  }

  static String formatDuration(int seconds) {
    if (seconds <= 0) return '';

    return formatPosition(seconds);
  }

  LongVideo copyWith({
    int? likeCount,
    int? commentCount,
    bool? liked,
    int? viewCount,
    /// The real length, once something has found it out.
    ///
    /// A YouTube video is created not knowing how long it is - see
    /// dl_videos_create_youtube - and the watch screen learns it from
    /// the player's metadata a second after opening. Named apart from
    /// the field so the ordinary no-argument copyWith keeps whatever
    /// duration it already had.
    int? durationSecondsOverride,
  }) {
    return LongVideo(
      postId: postId,
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
      videoUrl: videoUrl,
      durationSeconds: durationSecondsOverride ?? durationSeconds,
      publishedAt: publishedAt,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      liked: liked ?? this.liked,
      authorName: authorName,
      authorAvatar: authorAvatar,
      authorId: authorId,
      viewCount: viewCount ?? this.viewCount,
      hasCustomThumbnail: hasCustomThumbnail,
      source: source,
      youtubeId: youtubeId,
      isPodcast: isPodcast,
      isFeatured: isFeatured,
      isShort: isShort,
    );
  }

  /// Built defensively: this is a server payload and every field here
  /// has been seen arriving as a string, a number, or absent.
  factory LongVideo.fromJson(Map<String, dynamic> json) {
    int asInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();

      return int.tryParse('${value ?? ''}') ?? 0;
    }

    bool asBool(Object? value) {
      if (value is bool) return value;

      final text = '${value ?? ''}'.toLowerCase();

      return text == '1' || text == 'true';
    }

    DateTime? asDate(Object? value) {
      final text = '${value ?? ''}'.trim();

      if (text.isEmpty) return null;

      return DateTime.tryParse(text);
    }

    return LongVideo(
      postId: '${json['post_id'] ?? json['id'] ?? ''}',
      title: '${json['title'] ?? ''}'.trim(),
      description: '${json['description'] ?? ''}'.trim(),
      thumbnailUrl: '${json['thumbnail_url'] ?? json['thumbnail'] ?? ''}',
      videoUrl: '${json['video_url'] ?? json['url'] ?? ''}',
      durationSeconds: asInt(json['duration'] ?? json['duration_seconds']),
      publishedAt: asDate(json['published_at'] ?? json['date']),
      likeCount: asInt(json['like_count'] ?? json['likes']),
      commentCount: asInt(json['comment_count'] ?? json['comments']),
      liked: asBool(json['liked'] ?? json['is_liked']),
      authorName: '${json['author_name'] ?? ''}'.trim(),
      authorAvatar: '${json['author_avatar'] ?? ''}',
      authorId: asInt(json['author_id']),
      viewCount: asInt(json['view_count']),
      hasCustomThumbnail: asBool(json['has_custom_thumbnail']),
      source: '${json['source'] ?? 'cloudflare'}'.trim().isEmpty
          ? 'cloudflare'
          : '${json['source'] ?? 'cloudflare'}'.trim(),
      youtubeId: '${json['youtube_id'] ?? ''}'.trim(),
      isPodcast: asBool(json['is_podcast']),
      isFeatured: asBool(json['is_featured']),
      isShort: asBool(json['is_short']),
    );
  }
}
