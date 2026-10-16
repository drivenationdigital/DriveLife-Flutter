import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// The shell's header and section tabs, floating at the top of the feed.
///
/// Follows the finger: scrolling down pushes it away, scrolling back up
/// brings it with you. Nothing else moves it.
class FloatingChromeHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  /// Unused while [snapConfiguration] is null, and kept for when it is not.
  ///
  /// A floating header that declares a snapConfiguration asserts "vsync must
  /// not be null if the floating header changes size animatedly" the first
  /// time a drag ends, so the two travel together.
  @override
  final TickerProvider vsync;

  const FloatingChromeHeader({
    required this.child,
    required this.height,
    required this.vsync,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  /// No snap, deliberately.
  ///
  /// Snapping hid the header on a bare touch. Flutter runs the snap from
  /// `isScrollingNotifier` going quiet, and the target is the scroll
  /// direction at that moment:
  ///
  /// ```dart
  /// direction == ScrollDirection.forward ? 0.0 : maxExtent
  /// ```
  ///
  /// A touch that does not move still counts as a scroll starting and
  /// stopping, and by then the direction has gone back to `idle` — which is
  /// not `forward`, so the header animates to `maxExtent` and disappears.
  /// Putting a finger on the feed to read it is the one gesture that should
  /// leave the chrome exactly where it is.
  ///
  /// Without it the header simply tracks the scroll, so it only leaves when
  /// the feed is actually pulled up past it. A short flick back can leave it
  /// part shown; that resolves itself on the next scroll either way, and is
  /// a far smaller annoyance than the header vanishing under your thumb.
  @override
  FloatingHeaderSnapConfiguration? get snapConfiguration => null;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Opaque: it floats over the feed, and anything less means posts sliding
    // visibly behind the header.
    return Material(
      color: Colors.white,
      child: SizedBox(height: height, child: child),
    );
  }

  @override
  bool shouldRebuild(FloatingChromeHeader old) =>
      old.child != child || old.height != height;
}
