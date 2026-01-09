class PostMedia {
  final String id;
  final String mediaUrl;
  final String server;
  final String mediaType; // 'image' or 'video'

  PostMedia({
    required this.id,
    required this.mediaUrl,
    required this.server,
    required this.mediaType,
  });

  factory PostMedia.fromJson(Map<String, dynamic> json) {
    return PostMedia(
      id: json['id']?.toString() ?? '',
      mediaUrl: json['media_url'] ?? '',
      server: json['server'] ?? 'cloudflare',
      mediaType: json['media_type'] ?? 'image',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'media_url': mediaUrl,
      'server': server,
      'media_type': mediaType,
    };
  }
}

class Post {
  final String id;
  final String caption;
  final String? ascLinkType;
  final String? ascLink;
  final List<PostMedia> media;

  // These fields are only available when fetching post details
  final String? authorName;
  final String? authorUsername;
  final String? authorAvatar;
  final int? authorId;
  final DateTime? createdAt;
  final int? likesCount;
  final int? commentsCount;
  final bool? isLiked;

  Post({
    required this.id,
    required this.caption,
    this.ascLinkType,
    this.ascLink,
    required this.media,
    this.authorName,
    this.authorUsername,
    this.authorAvatar,
    this.authorId,
    this.createdAt,
    this.likesCount,
    this.commentsCount,
    this.isLiked,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id']?.toString() ?? '',
      caption: json['caption'] ?? '',
      ascLinkType: json['asc_link_type'],
      ascLink: json['asc_link'],
      media:
          (json['media'] as List<dynamic>?)
              ?.map((m) => PostMedia.fromJson(m))
              .toList() ??
          [],
      authorName: json['author_name'],
      authorUsername: json['author_username'],
      authorAvatar: json['author_avatar'],
      authorId: json['author_id'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      likesCount: json['likes_count'],
      commentsCount: json['comments_count'],
      isLiked: json['is_liked'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'caption': caption,
      'asc_link_type': ascLinkType,
      'asc_link': ascLink,
      'media': media.map((m) => m.toJson()).toList(),
      'author_name': authorName,
      'author_username': authorUsername,
      'author_avatar': authorAvatar,
      'author_id': authorId,
      'created_at': createdAt?.toIso8601String(),
      'likes_count': likesCount,
      'comments_count': commentsCount,
      'is_liked': isLiked,
    };
  }

  // Helper to get the first media thumbnail
  String get thumbnailUrl {
    if (media.isEmpty) return '';
    return media.first.mediaUrl;
  }

  // Helper to check if post has video
  bool get hasVideo {
    return media.any((m) => m.mediaType == 'video');
  }

  // Helper to get first video
  PostMedia? get firstVideo {
    try {
      return media.firstWhere((m) => m.mediaType == 'video');
    } catch (e) {
      return null;
    }
  }
}

class PostsResponse {
  final int totalPages;
  final int page;
  final int limit;
  final List<Post> data;

  PostsResponse({
    required this.totalPages,
    required this.page,
    required this.limit,
    required this.data,
  });

  factory PostsResponse.fromJson(Map<String, dynamic> json) {
    return PostsResponse(
      totalPages: json['total_pages'] ?? 0,
      page: json['page'] ?? 1,
      limit: json['limit'] ?? 9,
      data:
          (json['data'] as List<dynamic>?)
              ?.map((p) => Post.fromJson(p))
              .toList() ??
          [],
    );
  }
}
