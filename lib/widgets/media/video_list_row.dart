import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/models/long_video.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One video, as a row in a vertical list.
///
/// Shared by the creator page and the Watch tab's filtered lists,
/// because "a video in a list" is one thing and two copies of it drift
/// - the first time somebody fixes a duration badge in one of them is
/// the moment the app has two different-looking lists of the same
/// data.
///
/// The subtitle is passed in rather than derived here: a creator's
/// page wants "2 days ago · 1.2K views" and the Watch tab wants the
/// creator's name, and that is a decision belonging to the screen
/// rather than to the row.
class VideoListRow extends StatelessWidget {
  const VideoListRow({
    super.key,
    required this.video,
    required this.subtitle,
    required this.onTap,
    this.watchedSeconds = 0,
  });

  final LongVideo video;
  final String subtitle;
  final VoidCallback onTap;

  /// How far into it this person got, from [WatchProgress].
  ///
  /// Zero - the default - draws nothing, which is the right answer for
  /// a video nobody has started and for a caller that does not track
  /// it.
  final int watchedSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 130,
                height: 82,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _thumbnail(theme),

                    // Where it came from. Only on a YouTube video - a
                    // DriveLife upload carries no badge, because the
                    // absence of one is what says "ours".
                    if (video.isYoutube)
                      Positioned(
                        left: 7,
                        top: 7,
                        child: Container(
                          width: 26,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF0000),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),

                    VideoProgressBar(
                      video: video,
                      watchedSeconds: watchedSeconds,
                    ),

                    // Only when it is known. A blank corner beats a
                    // pill reading "0:00" on a video whose length
                    // nobody has established yet.
                    if (video.durationSeconds > 0)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            video.lengthLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.subtextColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(ThemeProvider theme) {
    final empty = ColoredBox(color: videoBlockColour(theme));

    if (video.thumbnailUrl.isEmpty) return empty;

    return CachedNetworkImage(
      imageUrl: video.thumbnailUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => empty,
      errorWidget: (_, __, ___) => empty,
    );
  }
}

/// How far through a video somebody got, along the bottom of its
/// artwork.
///
/// ── WHEN IT DRAWS, AND WHEN IT DOES NOT ─────────────────────────────
///
/// Only for a video that is genuinely part-watched. Not for one nobody
/// has opened, which has nothing to say; and not for one watched to
/// the end, where a full bar reads as "in progress" and is the exact
/// opposite of the truth.
///
/// A duration of zero also means no bar - that is a video whose length
/// nothing has established yet, and a fraction with an unknown
/// denominator is not a fraction.
class VideoProgressBar extends StatelessWidget {
  const VideoProgressBar({
    super.key,
    required this.video,
    required this.watchedSeconds,
  });

  final LongVideo video;
  final int watchedSeconds;

  @override
  Widget build(BuildContext context) {
    final total = video.durationSeconds;

    if (watchedSeconds <= 0 || total <= 0 || watchedSeconds >= total) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: LinearProgressIndicator(
        value: watchedSeconds / total,
        // 4, not 3. At three points the bar reads as an artefact of
        // the image rather than as a deliberate mark - the same
        // conclusion the grid tile reached.
        minHeight: 4,
        backgroundColor: Colors.black26,
        valueColor: const AlwaysStoppedAnimation(Color(0xFFAE9159)),
      ),
    );
  }
}

/// The colour behind a thumbnail that has not arrived, and behind a
/// skeleton block.
///
/// Follows the theme: a pale block is invisible on a dark page and a
/// dark one is invisible on a light page.
Color videoBlockColour(ThemeProvider theme) =>
    theme.isDarkMode ? const Color(0xFF242424) : const Color(0xFFE8E8E8);

/// "2 days ago", rounded down and never precise - nobody needs to know
/// a video is 9 days old rather than "1 week ago".
String videoAgo(DateTime? value) {
  if (value == null) return '';

  final days = DateTime.now().difference(value.toLocal()).inDays;

  if (days < 0) return '';
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';

  if (days < 30) {
    final weeks = days ~/ 7;

    return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
  }

  if (days < 365) {
    final months = days ~/ 30;

    return months == 1 ? '1 month ago' : '$months months ago';
  }

  final years = days ~/ 365;

  return years == 1 ? '1 year ago' : '$years years ago';
}
