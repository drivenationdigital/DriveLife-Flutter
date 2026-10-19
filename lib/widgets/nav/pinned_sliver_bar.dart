import 'package:flutter/material.dart';

/// Holds a fixed-height bar at the top of a scroll view once it is reached.
///
/// For navigation that should not scroll away — a set of tabs, a selector.
/// The chrome above it floats off as you read on; this stays, because
/// losing it mid-list would mean scrolling back to the top to change tab.
///
/// The height is declared rather than measured: a persistent header has to
/// know its extent before it is laid out, so this and whatever it holds have
/// to agree by hand. Change one and change the other.
class PinnedSliverBar extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  /// Painted behind the child. Opaque, always — pinned over a scrolling
  /// list, any transparency means content sliding visibly underneath it.
  final Color color;

  const PinnedSliverBar({
    required this.child,
    required this.height,
    this.color = Colors.white,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: color,
      child: SizedBox(height: height, child: child),
    );
  }

  @override
  bool shouldRebuild(PinnedSliverBar old) =>
      old.child != child || old.height != height || old.color != color;
}
