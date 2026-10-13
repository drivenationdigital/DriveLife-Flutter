import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'discover_filters.dart';
import 'discover_place.dart';

/// The results, as a sheet that can be dragged up over the map.
///
/// Collapsed it is a count and a row of cards you can flick through without
/// losing sight of the map; dragged up it becomes an ordinary list. Both show
/// the same [places], so the count in the header is always the number of
/// things you can actually reach.
class DiscoverResultsSheet extends StatefulWidget {
  /// How much room the floating bottom nav needs at the foot of the sheet,
  /// and under anything else that floats over the map. The bar is drawn on
  /// top of this screen, not above it, so nothing reserves this space
  /// automatically.
  static const double footerClearance = 86;

  /// The grabber, the header and one row of cards - what the sheet shows at
  /// rest.
  static const double _restingContent = 30 + 56 + 96;

  /// A fixed allowance for the home indicator, instead of the measured
  /// inset.
  ///
  /// Measuring would be more precise and is the wrong trade. See
  /// [collapsedFor]: this feeds minChildSize, which must never move, and the
  /// measured inset moves — `padding.bottom` collapses to zero under a
  /// keyboard, and Scaffold rewrites the MediaQuery around its own body, so
  /// even viewPadding is not dependable from in here. Being 34 logical pixels
  /// out on a device with no home indicator costs a little slack at the foot
  /// of the sheet. Being wrong by any amount at the wrong moment costs the
  /// whole sheet.
  static const double _assumedBottomInset = 34;

  /// Resting height, as the fraction of the screen that content needs.
  ///
  /// Derived rather than written down as a constant. DraggableScrollableSheet
  /// only speaks in fractions of the screen, and a fraction that leaves room
  /// for the cards and the floating nav on a tall phone hides the cards
  /// behind the nav on a short one. The map screen reads this too, to keep
  /// its own floating buttons above the sheet.
  ///
  /// Depends on the screen's height and nothing else, because this value
  /// becomes the sheet's minChildSize and DraggableScrollableSheet cannot
  /// have its minimum changed underneath it: the controller keeps the extent
  /// it already had, that extent is now out of bounds, and the sheet stops
  /// responding to drags entirely.
  ///
  /// That is not hypothetical. This was computed from the measured bottom
  /// inset, opening the location search focuses a text field, and a keyboard
  /// takes `padding.bottom` to zero — so every location search shifted the
  /// minimum and after a few the sheet could not be opened at all.
  static double collapsedFor(BuildContext context) {
    final needed = _restingContent + footerClearance + _assumedBottomInset;
    // Never more than half the screen: on a very small display the cards are
    // worth less than the map they would be covering.
    return (needed / MediaQuery.sizeOf(context).height).clamp(0.2, 0.5);
  }

  final List<DiscoverPlace> places;
  final bool loading;
  final DiscoverFilters filters;
  final DiscoverPlace? selected;
  final ValueChanged<DiscoverPlace> onTap;
  final ValueChanged<DiscoverPlace> onOpen;

  const DiscoverResultsSheet({
    super.key,
    required this.places,
    required this.loading,
    required this.filters,
    required this.selected,
    required this.onTap,
    required this.onOpen,
  });

  @override
  State<DiscoverResultsSheet> createState() => _DiscoverResultsSheetState();
}

class _DiscoverResultsSheetState extends State<DiscoverResultsSheet> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  /// Past this the sheet is tall enough to be worth reading as a list.
  static const double _listAbove = 0.42;

  bool _asList = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Switches between the card strip and the list, once the sheet has
  /// settled.
  ///
  /// Driven by ScrollEndNotification rather than by listening to the extent
  /// as it changes, and that is the whole point. The two layouts have
  /// different children, so swapping them rebuilds the ListView this gesture
  /// is being fed through — which cancels the drag. Watching the extent live
  /// meant the swap happened the instant it crossed [_listAbove], mid-drag,
  /// killing the gesture and letting the sheet snap back to the bottom.
  ///
  /// The sheet could therefore never be opened past that threshold at all: it
  /// was not stuck, it was being interrupted at exactly the same height every
  /// time.
  ///
  /// Waiting for the scroll to end also reads better. The content settles
  /// once, after the sheet arrives, instead of reshuffling under the finger
  /// on the way.
  bool _onScrollEnd(ScrollEndNotification _) {
    if (!_controller.isAttached) return false;
    final asList = _controller.size >= _listAbove;
    if (asList != _asList) {
      // Deferred: this fires from within the scroll's own notification
      // dispatch, and rebuilding the scrollable from inside that is the
      // "setState() or markNeedsBuild() called during build" crash.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _asList = asList);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = DiscoverResultsSheet.collapsedFor(context);

    return DraggableScrollableSheet(
      // Deliberately NOT keyed on the resting height. Re-keying builds a
      // second DraggableScrollableSheet before the first is disposed, and
      // both reach for this controller: "Draggable scrollable controller is
      // already attached to a sheet". The guarantee that keeps this safe is
      // that collapsedFor cannot change, not a key that recreates the sheet
      // when it does.
      controller: _controller,
      initialChildSize: collapsed,
      minChildSize: collapsed,
      maxChildSize: 0.9,
      snap: true,
      // Ascending, as snapSizes requires. collapsedFor clamps at 0.5, so the
      // resting height can never overtake the middle stop.
      snapSizes: [collapsed, 0.55, 0.9],
      builder: (context, scrollController) {
        return NotificationListener<ScrollEndNotification>(
          onNotification: _onScrollEnd,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 22,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            // The ListView owns the controller, which is what makes the whole
            // sheet draggable: without a scrollable attached to it the sheet
            // can only be moved by its handle.
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.zero,
              children: [
                const _Grabber(),
                _Header(
                  count: widget.places.length,
                  summary: widget.filters.summary,
                  loading: widget.loading,
                ),
                if (widget.places.isEmpty && !widget.loading)
                  const _Empty()
                else if (_asList)
                  for (final place in widget.places)
                    _ResultRow(
                      place: place,
                      selected: place.id == widget.selected?.id,
                      onTap: () => widget.onTap(place),
                      onOpen: () => widget.onOpen(place),
                    )
                else
                  _CardStrip(
                    places: widget.places,
                    selected: widget.selected,
                    onTap: widget.onTap,
                    onOpen: widget.onOpen,
                  ),
                // Clears the floating bottom bar, which the shell draws
                // over this sheet rather than above it. viewPadding for the
                // same reason collapsedFor uses it: this has to agree with the
                // height that was reserved, keyboard or no keyboard.
                SizedBox(
                  height:
                      MediaQuery.viewPaddingOf(context).bottom +
                      DiscoverResultsSheet.footerClearance,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFD9D9D9),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  final String summary;
  final bool loading;

  const _Header({
    required this.count,
    required this.summary,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loading ? 'Searching…' : '$count nearby',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF8A8A8E),
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Center(
        child: Text(
          'Nothing in range.\nTry widening the radius.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: Color(0xFF8A8A8E)),
        ),
      ),
    );
  }
}

/// The collapsed view: results side by side, flicked through horizontally.
class _CardStrip extends StatelessWidget {
  final List<DiscoverPlace> places;
  final DiscoverPlace? selected;
  final ValueChanged<DiscoverPlace> onTap;
  final ValueChanged<DiscoverPlace> onOpen;

  const _CardStrip({
    required this.places,
    required this.selected,
    required this.onTap,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: places.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final place = places[i];
          return _Card(
            place: place,
            selected: place.id == selected?.id,
            onTap: () => onTap(place),
            onOpen: () => onOpen(place),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final DiscoverPlace place;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  const _Card({
    required this.place,
    required this.selected,
    required this.onTap,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // One tap moves the map to it; two opens it. Opening on the first tap
      // would make browsing the strip impossible without leaving the map.
      onTap: onTap,
      onDoubleTap: onOpen,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 244,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? place.kind.colour : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            _Thumb(place: place, size: 72),
            const SizedBox(width: 10),
            Expanded(child: _Summary(place: place)),
          ],
        ),
      ),
    );
  }
}

/// The expanded view: one result per row.
class _ResultRow extends StatelessWidget {
  final DiscoverPlace place;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  const _ResultRow({
    required this.place,
    required this.selected,
    required this.onTap,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // In the list there is no map to keep an eye on, so a tap opens.
      onTap: onOpen,
      onLongPress: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: selected ? const Color(0xFFF2F2F2) : Colors.transparent,
        child: Row(
          children: [
            _Thumb(place: place, size: 58),
            const SizedBox(width: 12),
            Expanded(child: _Summary(place: place)),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFFC4C4C6),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final DiscoverPlace place;
  final double size;

  const _Thumb({required this.place, required this.size});

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: place.kind.colour.withValues(alpha: 0.12),
      child: Center(
        child: Icon(
          place.kind.icon,
          size: size * 0.34,
          color: place.kind.colour,
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: place.thumbnail == null
            ? placeholder
            : CachedNetworkImage(
                imageUrl: place.thumbnail!,
                fit: BoxFit.cover,
                // Capped at the size it is actually drawn at. Uncapped, a
                // 2000px cover photo decodes to ~16MB in memory for a 72px
                // square, and a strip of twenty of them is how a map screen
                // runs a phone out of RAM.
                memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final DiscoverPlace place;

  const _Summary({required this.place});

  @override
  Widget build(BuildContext context) {
    final distance = place.distance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: place.kind.colour,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              place.kind.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: place.kind.colour,
              ),
            ),
            if (distance != null) ...[
              const Text(
                '  ·  ',
                style: TextStyle(fontSize: 11, color: Color(0xFFC4C4C6)),
              ),
              Text(
                '${distance.toStringAsFixed(distance < 10 ? 1 : 0)} mi',
                style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8E)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          place.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1C1C1E),
          ),
        ),
        if (place.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            place.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8E)),
          ),
        ],
      ],
    );
  }
}

/// Where a callout goes, worked out from where its pin is.
@immutable
class CalloutPlacement {
  final double left;
  final double top;

  /// True when the card sits above its pin, so the tail points down at it.
  final bool pointsDown;

  const CalloutPlacement({
    required this.left,
    required this.top,
    required this.pointsDown,
  });

  @override
  bool operator ==(Object other) =>
      other is CalloutPlacement &&
      other.left == left &&
      other.top == top &&
      other.pointsDown == pointsDown;

  @override
  int get hashCode => Object.hash(left, top, pointsDown);

  @override
  String toString() =>
      'CalloutPlacement(left: $left, top: $top, pointsDown: $pointsDown)';
}

/// The card for the pin the user just tapped, anchored to that pin.
///
/// Fixed size on purpose. The map screen projects the pin's coordinate to a
/// screen point and places this relative to it, which means it has to know how
/// big this is before it is laid out — a card that measured itself could only
/// be positioned a frame late, and would visibly jump.
class DiscoverCallout extends StatelessWidget {
  static const double width = 272;
  static const double height = 78;

  /// The gap between the pin and the card, and the height of the tail that
  /// crosses it.
  static const double tail = 8;

  /// How far the pin's art rises above the coordinate it marks. Its anchor is
  /// its point, so the card has to clear the pin, not the coordinate.
  static const double pinHeight = 44;

  /// Keeps the card off the very edge of the screen.
  static const double margin = 12;

  /// Where to put the card for a pin at [pin] on a [screen]-sized display.
  ///
  /// Above the pin by preference and below it when there is no room above —
  /// what every map app does, and what decides which way the tail points.
  /// [chrome] is the height taken by the search bar and chips, which the card
  /// must not slide under.
  ///
  /// Null when the pin is off screen. The alternative is a card pinned to the
  /// edge pointing at something that is not there.
  static CalloutPlacement? placeFor({
    required Offset pin,
    required Size screen,
    required double chrome,
  }) {
    if (pin.dx < -margin ||
        pin.dx > screen.width + margin ||
        pin.dy < -margin ||
        pin.dy > screen.height + margin) {
      return null;
    }

    final above = pin.dy - pinHeight - height - tail;
    final pointsDown = above >= chrome;

    // Centred on the pin, then pulled back inside the screen. A pin near the
    // edge still gets its whole card; only the tail stops lining up with the
    // middle of it, which is much the lesser problem.
    final rightmost = screen.width - width - margin;

    return CalloutPlacement(
      left: rightmost <= margin
          ? margin
          : (pin.dx - width / 2).clamp(margin, rightmost),
      top: pointsDown ? above : pin.dy + tail,
      pointsDown: pointsDown,
    );
  }

  final DiscoverPlace place;

  /// True when the card sits above the pin, which points the tail downwards.
  final bool pointsDown;

  final VoidCallback onClose;
  final VoidCallback onOpen;

  const DiscoverCallout({
    super.key,
    required this.place,
    required this.pointsDown,
    required this.onClose,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final card = Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _Thumb(place: place, size: 58),
                const SizedBox(width: 10),
                Expanded(child: _Summary(place: place)),
                GestureDetector(
                  onTap: onClose,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: Color(0xFF8A8A8E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // The tail is what makes this read as belonging to one pin rather than
    // floating over the map near several of them.
    final spike = CustomPaint(
      size: Size(16, tail),
      painter: _TailPainter(pointsDown: pointsDown),
    );

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: pointsDown ? [card, spike] : [spike, card],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  final bool pointsDown;

  const _TailPainter({required this.pointsDown});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointsDown) {
      path
        ..moveTo(size.width / 2 - 8, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width / 2 + 8, 0);
    } else {
      path
        ..moveTo(size.width / 2 - 8, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width / 2 + 8, size.height);
    }
    path.close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.3), 3, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.pointsDown != pointsDown;
}
