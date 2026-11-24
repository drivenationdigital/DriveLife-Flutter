/// Where adverts go in the feed, worked out rather than guessed.
///
/// ── WHY THIS IS ARITHMETIC AND NOT A MODULO IN A BUILDER ────────────
///
/// `if (index % 7 == 0) return Ad()` is how every feed does this once,
/// and it is wrong in three ways that all look fine on the first
/// screenful:
///
///   1. index 0 is an advert, so the app opens on one
///   2. the post at that index is never drawn — the feed silently
///      swallows a post for every advert shown
///   3. the last item can be an advert with nothing after it, so the
///      feed appears to end on one
///
/// (2) is the one that matters. The list has to get LONGER by the
/// number of adverts, and every index after an advert has to shift. So
/// there are two index spaces here — DISPLAY (what the ListView asks
/// for) and POST (what the data is) — and the whole job of this class
/// is translating between them without losing anything.
///
/// ── NOTHING IS INSERTED INTO THE DATA ───────────────────────────────
///
/// The posts list is never touched. Adverts exist only as positions
/// computed from its length, which means pagination, de-duplication and
/// refresh all carry on knowing nothing about advertising — and
/// switching adverts off is one boolean rather than a rebuild of the
/// list.
class FeedAdSlots {
  /// How many posts are read before the first advert.
  ///
  /// Four, so somebody opening the app sees a screenful of the thing
  /// they came for first. An advert in the first two positions is the
  /// single most complained-about pattern in a social feed, and the
  /// first impression is the one that decides whether the app gets
  /// opened tomorrow.
  final int firstAfter;

  /// How many posts between adverts after that.
  final int every;

  /// Whether to place any at all.
  ///
  /// False for a member. The ad-free experience is a paid benefit, and
  /// it is this flag — see MembershipProvider.
  final bool enabled;

  const FeedAdSlots({
    this.firstAfter = 4,
    this.every = 6,
    this.enabled = true,
  });

  /// The empty one. For a member, and for a feed that has not loaded.
  static const FeedAdSlots none = FeedAdSlots(enabled: false);

  /// Display slots per cycle: the posts, then the advert.
  int get _stride => every + 1;

  /// How many adverts belong in a feed of [postCount] posts.
  ///
  /// An advert is only placed when at least one post follows it, so a
  /// feed never ends on one — the loading spinner under an advert
  /// reads as "that is all, here is an advert", which is the last
  /// impression to leave somebody with.
  int adCount(int postCount) {
    if (!enabled || postCount <= firstAfter) return 0;

    return ((postCount - firstAfter - 1) ~/ every) + 1;
  }

  /// How many rows the list draws for [postCount] posts.
  int displayCount(int postCount) => postCount + adCount(postCount);

  /// Whether the row at [displayIndex] is an advert.
  bool isAd(int displayIndex, int postCount) {
    if (!enabled || displayIndex < firstAfter) return false;

    final offset = displayIndex - firstAfter;

    if (offset % _stride != 0) return false;

    // Past the last advert this many posts can support. Without this
    // the tail of the list is adverts for posts that do not exist.
    return (offset ~/ _stride) < adCount(postCount);
  }

  /// Which advert this is, counting from nought. Null when the row is
  /// not an advert.
  ///
  /// The caller uses it to pick WHICH advert to show, so that two on
  /// one screen are never the same one.
  int? adIndexAt(int displayIndex, int postCount) {
    if (!isAd(displayIndex, postCount)) return null;

    return (displayIndex - firstAfter) ~/ _stride;
  }

  /// How many adverts sit before [displayIndex].
  int adsBefore(int displayIndex, int postCount) {
    if (!enabled || displayIndex <= firstAfter) return 0;

    final placed = ((displayIndex - 1 - firstAfter) ~/ _stride) + 1;
    final total = adCount(postCount);

    return placed < total ? placed : total;
  }

  /// The post behind [displayIndex].
  ///
  /// Meaningless for a row that is an advert — check [isAd] first. It
  /// still returns a number rather than throwing, because a feed that
  /// crashes on an off-by-one is worse than one that draws a post
  /// twice.
  int postIndexFor(int displayIndex, int postCount) =>
      displayIndex - adsBefore(displayIndex, postCount);
}
