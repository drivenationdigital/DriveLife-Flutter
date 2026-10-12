import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'discover_place.dart';

/// The radius and date the map is searching with.
@immutable
class DiscoverFilters {
  final int radius;
  final String date;

  const DiscoverFilters({required this.radius, required this.date});

  /// How the sheet's subtitle reads: "Within 25 mi · This weekend".
  String get summary => 'Within $radius mi · ${dateLabels[date] ?? 'Any time'}';

  /// The date windows the events endpoint understands, keyed by the value it
  /// expects. Venues have no dates and ignore this entirely.
  static const Map<String, String> dateLabels = {
    'anytime': 'Any time',
    'today': 'Today',
    'tomorrow': 'Tomorrow',
    'this-week': 'This week',
    'this-weekend': 'This weekend',
    'this-month': 'This month',
  };

  static const List<int> radii = [10, 25, 50, 100];
}

/// The results, as a sheet that can be dragged up over the map.
///
/// Collapsed it is a count and a row of cards you can flick through without
/// losing sight of the map; dragged up it becomes an ordinary list. Both show
/// the same [places], so the count in the header is always the number of
/// things you can actually reach.
class DiscoverResultsSheet extends StatefulWidget {
  /// Resting height, as a fraction of the screen. Also used by the map screen
  /// to keep its floating buttons clear of it, so it lives here rather than
  /// being written down in two places.
  static const double collapsed = 0.24;

  final List<DiscoverPlace> places;
  final bool loading;
  final int radius;
  final String dateFilter;
  final DiscoverPlace? selected;
  final ValueChanged<DiscoverPlace> onTap;
  final ValueChanged<DiscoverPlace> onOpen;

  const DiscoverResultsSheet({
    super.key,
    required this.places,
    required this.loading,
    required this.radius,
    required this.dateFilter,
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
  void initState() {
    super.initState();
    _controller.addListener(_onExtentChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onExtentChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onExtentChanged() {
    if (!_controller.isAttached) return;
    final asList = _controller.size >= _listAbove;
    if (asList != _asList) setState(() => _asList = asList);
  }

  @override
  Widget build(BuildContext context) {
    final filters = DiscoverFilters(
      radius: widget.radius,
      date: widget.dateFilter,
    );

    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: DiscoverResultsSheet.collapsed,
      minChildSize: DiscoverResultsSheet.collapsed,
      maxChildSize: 0.9,
      snap: true,
      snapSizes: const [DiscoverResultsSheet.collapsed, 0.55, 0.9],
      builder: (context, scrollController) {
        return DecoratedBox(
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
                summary: filters.summary,
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
              SizedBox(height: MediaQuery.paddingOf(context).bottom + 12),
            ],
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
        child: Icon(place.kind.icon, size: size * 0.34, color: place.kind.colour),
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
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8A8A8E),
                ),
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

/// The card for the pin the user just tapped.
///
/// Floats above the sheet rather than being anchored to the pin itself.
/// Anchoring would mean projecting the coordinate to a screen point on every
/// camera frame — jittery during a fling, and a bubble that small is an
/// awkward tap target. Maps and Apple Maps both do it this way.
class DiscoverCallout extends StatelessWidget {
  final DiscoverPlace place;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  const DiscoverCallout({
    super.key,
    required this.place,
    required this.onClose,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _Thumb(place: place, size: 56),
              const SizedBox(width: 12),
              Expanded(child: _Summary(place: place)),
              IconButton(
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFF8A8A8E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Radius and date, as a modal sheet.
///
/// Returns null when dismissed without applying, so the caller can tell
/// "cancelled" from "applied the same values".
class DiscoverFilterSheet extends StatefulWidget {
  final DiscoverFilters initial;

  const DiscoverFilterSheet({super.key, required this.initial});

  @override
  State<DiscoverFilterSheet> createState() => _DiscoverFilterSheetState();
}

class _DiscoverFilterSheetState extends State<DiscoverFilterSheet> {
  late int _radius = widget.initial.radius;
  late String _date = widget.initial.date;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _Grabber()),
          const SizedBox(height: 4),
          const Text(
            'Distance',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final r in DiscoverFilters.radii)
                _Choice(
                  label: '$r mi',
                  selected: r == _radius,
                  onTap: () => setState(() => _radius = r),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'When',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Applies to events. Venues are always shown.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF8A8A8E)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in DiscoverFilters.dateLabels.entries)
                _Choice(
                  label: entry.value,
                  selected: entry.key == _date,
                  onTap: () => setState(() => _date = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1C1C1E),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.pop(
                context,
                DiscoverFilters(radius: _radius, date: _date),
              ),
              child: const Text('Show results'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF1C1C1E),
          ),
        ),
      ),
    );
  }
}
