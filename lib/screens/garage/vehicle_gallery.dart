import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A vehicle's photographs, swiped left and right.
///
/// Replaces the single full-bleed cover. One photograph had to carry the
/// whole top of the screen, and for a lot of vehicles it could not — a
/// portrait shot, a dark one, one framed for a thumbnail — which is the
/// thing this is here to fix rather than a feature on top.
///
/// The page's own rules, which are not decoration:
///
///   * it does not run under the status bar. The clock and the signal
///     bars sat on whatever the top of somebody's photograph happened to
///     be, and no choice of icon colour works for both a white sky and a
///     black tyre. There is a flat black band above instead.
///   * the fade at the bottom is shallow and only at the bottom. It is
///     there to join the photograph to the panel below it, not to darken
///     the picture — a tall scrim over a gallery dims every photograph
///     to make one piece of text legible somewhere else.
class VehicleGallery extends StatefulWidget {
  /// Every photograph, cover first. Never empty — the caller passes a
  /// single-item list for a vehicle with only a cover, and the dots and
  /// the counter take themselves away.
  final List<String> images;

  /// How tall the photographs are, not counting the status bar band.
  final double height;

  /// The colour the bottom fades into: the panel underneath.
  final Color fadeInto;

  /// Opening one full screen.
  final void Function(int index)? onTap;

  /// Removing one. Null for anybody who may not.
  final void Function(int index)? onLongPress;

  const VehicleGallery({
    super.key,
    required this.images,
    required this.height,
    required this.fadeInto,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<VehicleGallery> createState() => _VehicleGalleryState();
}

class _VehicleGalleryState extends State<VehicleGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final images = widget.images;
    final many = images.length > 1;

    return SizedBox(
      height: widget.height + top,
      child: Stack(
        children: [
          // The band behind the status bar stays the panel's colour, so
          // the clock always has flat black under it whatever the
          // photograph is doing.
          Positioned.fill(
            top: top,
            child: PageView.builder(
              controller: _controller,
              itemCount: images.length,
              // Only when there is somewhere to go. A one-photograph
              // gallery that still rubber-bands under the thumb reads as
              // something broken rather than as a gallery of one.
              physics: many
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => GestureDetector(
                // Opaque rather than the default: CachedNetworkImage
                // swaps between a placeholder, the image and an error
                // widget, and deferToChild would make the tap depend on
                // which of the three happened to be showing.
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap == null ? null : () => widget.onTap!(i),
                onLongPress: widget.onLongPress == null
                    ? null
                    : () => widget.onLongPress!(i),
                child: CachedNetworkImage(
                  imageUrl: images[i],
                  fit: BoxFit.cover,
                  memCacheWidth:
                      (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                  placeholder: (_, __) =>
                      const ColoredBox(color: Color(0xFF1C1C1E)),
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1C1C1E)),
                ),
              ),
            ),
          ),

          // IgnorePointer is load-bearing. A DecoratedBox filling a Stack
          // absorbs pointer events, so without this the fade sits over
          // the gallery and swallows every swipe and every tap — see
          // test/hero_cover_tap_test.dart, which pins exactly that.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 110,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.fadeInto.withValues(alpha: 0),
                      widget.fadeInto.withValues(alpha: 0.55),
                      widget.fadeInto,
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
          ),

          if (many) ...[
            Positioned(left: 20, bottom: 16, child: _dots(images.length)),
            Positioned(
              right: 16,
              bottom: 14,
              child: _counter(_page + 1, images.length),
            ),
          ],
        ],
      ),
    );
  }

  /// One dot per photograph, the current one drawn as a bar.
  ///
  /// A bar rather than a larger dot: at this size a dot that only grows
  /// is hard to pick out against its neighbours, and the shape reads at
  /// a glance where a two-point diameter difference does not.
  Widget _dots(int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: i == _page ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _page
                  ? const Color(0xFFAE9159)
                  : Colors.white.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ],
    );
  }

  /// "1 / 4", on a dark chip.
  ///
  /// The dots say where you are in a gallery you can see the whole of;
  /// this says how much there is when there are more dots than anybody
  /// counts at a glance.
  Widget _counter(int current, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: 13,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            '$current / $total',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
