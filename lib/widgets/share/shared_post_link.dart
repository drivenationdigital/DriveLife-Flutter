/// A DriveLife post or event link found inside a chat message.
///
/// ── WHY A LINK AND NOT A COLUMN ──────────────────────────────────────
///
/// Sharing a post into a chat could have been a `shared_post_id` column
/// on the Supabase `messages` table, which is what a purpose-built
/// design would do. It is a link in the message body instead, for three
/// reasons:
///
///   1. No migration. The messages table is live, realtime subscribers
///      read its columns, and a schema change is the one thing here that
///      cannot be rolled back by uploading a file.
///
///   2. Older app versions degrade to something sensible. A build that
///      does not know about shared posts shows a URL the person can tap,
///      rather than an empty bubble with a column it cannot read.
///
///   3. It survives being quoted, copied, or forwarded as text, because
///      the thing identifying the post IS the text.
///
/// The cost is this parser: the card is rendered by RECOGNISING the
/// message rather than by being told. That is a fair trade for a
/// feature whose failure mode should be "shows a link".
class SharedPostLink {
  /// 'post' or 'event'. They open different screens.
  final String kind;

  /// The post or event id, as it appeared in the URL.
  final String id;

  /// Whatever the sender typed around the link, with the link removed.
  ///
  /// Empty when they sent the post on its own, which is the common case
  /// — and then the bubble is just the card, with no empty line under it.
  final String note;

  const SharedPostLink({
    required this.kind,
    required this.id,
    required this.note,
  });

  bool get isEvent => kind == 'event';

  /// Matches the URLs _sharePost() builds, and little else.
  ///
  /// Deliberately anchored on the host. Matching any `/post/123` would
  /// turn somebody's link to another site into a DriveLife card
  /// promising content that is not there.
  ///
  /// The trailing `[^\s]*` eats `?ref=share` and anything after it, so
  /// the query string does not end up in the note.
  static final RegExp _pattern = RegExp(
    r'https?://(?:www\.)?app\.mydrivelife\.com/(post|event)/(\d+)[^\s]*',
    caseSensitive: false,
  );

  /// The first DriveLife post link in [content], or null.
  ///
  /// Only the first. A message with two links is a message, not a share,
  /// and stacking two cards in one bubble reads worse than the text
  /// does.
  static SharedPostLink? parse(String? content) {
    final text = content ?? '';

    if (text.isEmpty) return null;

    final match = _pattern.firstMatch(text);

    if (match == null) return null;

    final kind = (match.group(1) ?? 'post').toLowerCase();
    final id = match.group(2) ?? '';

    if (id.isEmpty) return null;

    // The link cut out, and the whitespace it leaves behind collapsed.
    // Without that, "Look at this\n\n<url>" leaves a bubble with two
    // blank lines hanging off the bottom of the card.
    final note = text
        .replaceRange(match.start, match.end, '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();

    return SharedPostLink(kind: kind, id: id, note: note);
  }
}
