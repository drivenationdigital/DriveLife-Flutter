/// A YouTube channel DriveLife features.
///
/// The channel is the creator. A DriveLife account can be linked to
/// one, and most will not have one - somebody whose videos are worth
/// featuring usually has no reason to have signed up. See
/// endpoints/creators.php.
class Creator {
  /// The row id, which is what the admin endpoints address - and the
  /// only identifier every creator is guaranteed to have.
  final int id;

  /// The linked DriveLife account, or 0 when there is none.
  ///
  /// Zero rather than null because that is what the server sends for
  /// "no account", and because every use of it here is a question
  /// ([hasAccount]) rather than arithmetic. A link whose account has
  /// since been deleted also arrives as 0.
  final int userId;

  /// What to call them on a card.
  ///
  /// Already resolved by the server: the channel's name, or the linked
  /// member's name when there is no channel name on file. Nothing here
  /// has to know which, which is the point.
  final String name;

  final String avatarUrl;
  final String bio;

  /// Their YouTube channel id.
  final String channelId;

  /// The channel's page on YouTube, for a "view on YouTube" link.
  /// Built by the server so the URL shape lives in one place.
  final String channelUrl;

  /// Which playlist the sync reads.
  ///
  /// Normally the channel's uploads (a `UU...` id, derived from the
  /// channel), meaning every video they publish. A `PL...` id means
  /// somebody pointed this creator at one particular playlist - a
  /// podcast, say - and only that is pulled.
  final String playlistId;

  /// Whether this creator is pinned to one playlist rather than the
  /// whole channel.
  bool get isPlaylistOnly =>
      playlistId.isNotEmpty && !playlistId.startsWith('UU');

  /// Whether DriveLife puts them on the front of the Watch tab.
  ///
  /// An editorial choice, made in the admin tool. Different from
  /// [isFollowing], which is this person's own - the row is both,
  /// with theirs first.
  final bool isFeatured;

  /// Whether the signed-in person follows them.
  ///
  /// Always false for a signed-out viewer, which is correct rather
  /// than a special case: somebody with no account follows nobody.
  final bool isFollowing;

  /// Whether everything read from this channel is a podcast episode.
  ///
  /// The other half of the rule lives in DL_PODCAST_USER_IDS, which
  /// covers episodes uploaded through the app. A synced video has no
  /// uploader, so this is the only thing that can classify one - see
  /// dl_videos_is_podcast.
  final bool isPodcast;

  final int sortOrder;

  const Creator({
    required this.id,
    required this.name,
    this.userId = 0,
    this.avatarUrl = '',
    this.bio = '',
    this.channelId = '',
    this.channelUrl = '',
    this.playlistId = '',
    this.isFeatured = false,
    this.isFollowing = false,
    this.isPodcast = false,
    this.sortOrder = 0,
  });

  /// The same creator with following flipped, for the optimistic
  /// redraw while the request is in flight.
  Creator withFollowing(bool following) {
    return Creator(
      id: id,
      name: name,
      userId: userId,
      avatarUrl: avatarUrl,
      bio: bio,
      channelId: channelId,
      channelUrl: channelUrl,
      playlistId: playlistId,
      isFeatured: isFeatured,
      isFollowing: following,
      isPodcast: isPodcast,
      sortOrder: sortOrder,
    );
  }

  /// Whether this creator is also a DriveLife member.
  ///
  /// The normal answer is no. When it is yes, [userId] is what links a
  /// card through to their profile, their posts and their garage.
  bool get hasAccount => userId > 0;

  /// Their initials, for the circle before there is a picture.
  String get initials {
    final trimmed = name.trim();

    if (trimmed.isEmpty) return '?';

    final parts = trimmed.split(RegExp(r'\s+'));

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// Built defensively: this is a server payload and every field here
  /// has been seen arriving as a string, a number, or absent.
  factory Creator.fromJson(Map<String, dynamic> json) {
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

    return Creator(
      id: asInt(json['id']),
      userId: asInt(json['user_id']),
      name: '${json['name'] ?? ''}'.trim(),
      avatarUrl: '${json['avatar_url'] ?? ''}'.trim(),
      bio: '${json['bio'] ?? ''}'.trim(),
      channelId: '${json['channel_id'] ?? ''}'.trim(),
      channelUrl: '${json['channel_url'] ?? ''}'.trim(),
      playlistId: '${json['playlist_id'] ?? ''}'.trim(),
      isFeatured: asBool(json['is_featured']),
      isFollowing: asBool(json['is_following']),
      isPodcast: asBool(json['is_podcast']),
      sortOrder: asInt(json['sort_order']),
    );
  }
}
