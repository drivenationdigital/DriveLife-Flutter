/// A poll attached to a post, answered in the comments sheet.
///
/// Posts without a poll simply have none of this — the sheet asks, gets null,
/// and renders exactly what it rendered before.
class PollOption {
  final int id;
  final String label;
  final int votes;

  const PollOption({
    required this.id,
    required this.label,
    this.votes = 0,
  });

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
    id: int.tryParse('${json['id']}') ?? 0,
    label: '${json['label'] ?? ''}',
    votes: int.tryParse('${json['votes']}') ?? 0,
  );
}

/// One person's vote, for the author's own view of the results.
class PollVoter {
  final int optionId;
  final int userId;
  final String username;
  final String displayName;
  final String? avatar;

  const PollVoter({
    required this.optionId,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatar,
  });

  factory PollVoter.fromJson(Map<String, dynamic> json) => PollVoter(
    optionId: int.tryParse('${json['option_id']}') ?? 0,
    userId: int.tryParse('${json['user_id']}') ?? 0,
    username: '${json['username'] ?? ''}',
    displayName: '${json['display_name'] ?? json['username'] ?? ''}',
    avatar: '${json['avatar'] ?? ''}'.isEmpty ? null : '${json['avatar']}',
  );
}

class PostPoll {
  final int pollId;
  final int postId;
  final String question;
  final List<PollOption> options;
  final int totalVotes;

  /// The option this viewer picked, or 0 if they have not voted.
  ///
  /// A vote cannot be changed, so this is also what decides whether the
  /// options are still buttons or have become results.
  final int myOptionId;

  /// When voting stops. Null only for polls made before polls could close.
  final DateTime? endsAt;

  /// Whether that moment has passed — decided by the server, not by this
  /// device's clock, so a phone with the wrong time cannot vote late or be
  /// locked out early.
  final bool isClosed;

  /// Whether the viewer wrote the post. Only they may see who voted.
  final bool isAuthor;

  const PostPoll({
    required this.pollId,
    required this.postId,
    required this.question,
    this.options = const [],
    this.totalVotes = 0,
    this.myOptionId = 0,
    this.endsAt,
    this.isClosed = false,
    this.isAuthor = false,
  });

  bool get hasVoted => myOptionId > 0;

  /// Whether the options are still answerable by this viewer.
  bool get canVote => !isClosed && !hasVoted;

  /// The option or options with the most votes.
  ///
  /// A list because a tie is a real outcome, not an error — two options on
  /// four votes each is a drawn poll, and picking one of them arbitrarily
  /// would announce a winner that did not win.
  List<PollOption> get winners {
    if (options.isEmpty || totalVotes == 0) return const [];

    final most = options
        .map((o) => o.votes)
        .reduce((a, b) => a > b ? a : b);

    if (most == 0) return const [];

    return options.where((o) => o.votes == most).toList(growable: false);
  }

  /// "3 days left", "2 hours left", or null when it has closed or never ends.
  String? get timeLeftLabel {
    final ends = endsAt;
    if (ends == null || isClosed) return null;

    final left = ends.difference(DateTime.now());
    if (left.isNegative) return null;

    if (left.inDays >= 1) {
      return '${left.inDays} ${left.inDays == 1 ? 'day' : 'days'} left';
    }

    if (left.inHours >= 1) {
      return '${left.inHours} ${left.inHours == 1 ? 'hour' : 'hours'} left';
    }

    final minutes = left.inMinutes;
    if (minutes >= 1) {
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} left';
    }

    return 'Closing now';
  }

  /// Whole percent of the vote for one option, rounded.
  ///
  /// Zero total reads as zero rather than dividing by it — a poll nobody has
  /// answered yet is the normal first state, not an error.
  int percentFor(PollOption option) {
    if (totalVotes <= 0) return 0;
    return ((option.votes * 100) / totalVotes).round();
  }

  factory PostPoll.fromJson(Map<String, dynamic> json) => PostPoll(
    pollId: int.tryParse('${json['poll_id']}') ?? 0,
    postId: int.tryParse('${json['post_id']}') ?? 0,
    question: '${json['question'] ?? ''}',
    options: (json['options'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PollOption.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    totalVotes: int.tryParse('${json['total_votes']}') ?? 0,
    myOptionId: int.tryParse('${json['my_option_id']}') ?? 0,
    // The server sends UTC; comparisons here are against local time, so it is
    // converted rather than compared as written.
    endsAt: _parseUtc(json['ends_at']),
    isClosed: json['is_closed'] == true,
    isAuthor: json['is_author'] == true,
  );

  static DateTime? _parseUtc(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty || raw == 'null') return null;

    // "2026-09-13 14:05:00" with no zone marker is UTC from this API.
    final normalised = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    return DateTime.tryParse(
      normalised.endsWith('Z') ? normalised : '${normalised}Z',
    )?.toLocal();
  }
}
