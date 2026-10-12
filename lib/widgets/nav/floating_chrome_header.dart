import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// The shell's header and section tabs, floating at the top of the feed.
///
/// Snaps rather than following the finger pixel for pixel on release: a
/// header left half shown is neither usable nor out of the way.
class FloatingChromeHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  /// Drives the snap animation.
  ///
  /// Required, not optional: a floating header that declares a
  /// snapConfiguration asserts "vsync must not be null if the floating
  /// header changes size animatedly" the first time a drag ends. It is only
  /// reached on release, which is why this crashed on the first flick rather
  /// than on the first frame.
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

  @override
  FloatingHeaderSnapConfiguration get snapConfiguration =>
      FloatingHeaderSnapConfiguration(
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 240),
      );

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
