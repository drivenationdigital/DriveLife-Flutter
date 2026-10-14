import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

import 'discover_place.dart';

/// Everything the map is currently narrowing by.
///
/// One immutable value rather than four fields on the screen's State, so the
/// filter sheet can be handed the current settings, edit a copy, and give
/// back a complete new set — there is no window in which half the filters
/// have been applied.
@immutable
class DiscoverFilters {
  /// Which categories may appear at all. Empty is not allowed — the sheet
  /// keeps at least one ticked, because a map filtered to nothing looks
  /// broken rather than filtered.
  final Set<DiscoverKind> kinds;

  final String date;

  /// Set only when [date] is [customDate]. Held separately so switching to
  /// "Any time" and back does not lose the range the user picked.
  final DateTimeRange? range;

  final int radius;

  const DiscoverFilters({
    required this.kinds,
    required this.date,
    required this.radius,
    this.range,
  });

  static const String customDate = 'custom';

  /// Everything, within 25 miles. What the map opens with.
  static DiscoverFilters get initial => DiscoverFilters(
    kinds: DiscoverKind.values.toSet(),
    date: 'anytime',
    radius: 25,
  );

  DiscoverFilters copyWith({
    Set<DiscoverKind>? kinds,
    String? date,
    int? radius,
    DateTimeRange? range,
  }) => DiscoverFilters(
    kinds: kinds ?? this.kinds,
    date: date ?? this.date,
    radius: radius ?? this.radius,
    range: range ?? this.range,
  );

  /// Whether a change from [other] means re-asking the server.
  ///
  /// Categories are applied on the client — everything is fetched once and
  /// hidden or shown — so flipping one must not cost a round trip. Radius and
  /// date are query parameters, so those must.
  bool needsRefetch(DiscoverFilters other) =>
      radius != other.radius ||
      date != other.date ||
      range?.start != other.range?.start ||
      range?.end != other.range?.end;

  /// How the sheet's subtitle reads: "Within 25 mi · This weekend".
  String get summary => radius == national
      ? 'Nationwide · $dateLabel'
      : 'Within $radius mi · $dateLabel';

  String get dateLabel {
    if (date == customDate && range != null) {
      return '${_day(range!.start)} – ${_day(range!.end)}';
    }
    return dateLabels[date] ?? 'Any time';
  }

  static String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// The date windows the events endpoint understands, keyed by the value it
  /// expects. Venues have no dates and ignore this entirely.
  static const Map<String, String> dateLabels = {
    'today': 'Today',
    'this-weekend': 'This weekend',
    'this-month': 'This month',
    'anytime': 'Any time',
  };

  /// "National", as a radius.
  ///
  /// 2000 miles rather than a separate mode, because the server already
  /// treats its own `national` keyword as a 2000-mile radius — so this needs
  /// nothing new behind it and cannot disagree with what the list screens do.
  /// It comfortably covers either country.
  static const int national = 2000;

  static const List<int> radii = [5, 10, 25, 50, national];

  /// What a radius is called on a chip. Only [national] is not a number of
  /// miles, and "2000 mi" would be a strange way to write it.
  static String radiusLabel(int radius) =>
      radius == national ? 'National' : '$radius mi';
}

/// The filter sheet.
///
/// Returns the edited filters, or null if dismissed without applying — so the
/// caller can tell "cancelled" from "applied the same thing".
class DiscoverFilterSheet extends StatefulWidget {
  final DiscoverFilters initial;

  /// How many results the given categories would show, from what is already
  /// loaded. Drives the button's count.
  final int Function(Set<DiscoverKind>) countFor;

  const DiscoverFilterSheet({
    super.key,
    required this.initial,
    required this.countFor,
  });

  @override
  State<DiscoverFilterSheet> createState() => _DiscoverFilterSheetState();
}

class _DiscoverFilterSheetState extends State<DiscoverFilterSheet> {
  late DiscoverFilters _filters = widget.initial;

  void _toggle(DiscoverKind kind) {
    final next = Set<DiscoverKind>.from(_filters.kinds);
    // Never let the last one go. Unticking everything is a map with nothing
    // on it and no indication why, which reads as a failure.
    if (next.contains(kind) && next.length > 1) {
      next.remove(kind);
    } else {
      next.add(kind);
    }
    setState(() => _filters = _filters.copyWith(kinds: next));
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      // A year back covers "what did I miss", three forward covers the
      // season's calendar. Beyond that there is nothing listed.
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      initialDateRange: _filters.range,
      helpText: 'Select dates',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: const Color(0xFF1C1C1E),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;
    setState(() {
      _filters = _filters.copyWith(
        date: DiscoverFilters.customDate,
        range: picked,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.countFor(_filters.kinds);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: _Grabber()),
            const SizedBox(height: 6),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _filters = DiscoverFilters.initial),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB08E4F),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36),
                  ),
                  child: const Text(
                    'Reset',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),

            const _SectionLabel('Show'),
            const SizedBox(height: 10),
            // Two to a row, so all four categories are visible without
            // scrolling and the eye can compare the colour key at a glance.
            for (var i = 0; i < DiscoverKind.values.length; i += 2) ...[
              Row(
                children: [
                  Expanded(
                    child: _KindCard(
                      kind: DiscoverKind.values[i],
                      on: _filters.kinds.contains(DiscoverKind.values[i]),
                      onTap: () => _toggle(DiscoverKind.values[i]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < DiscoverKind.values.length
                        ? _KindCard(
                            kind: DiscoverKind.values[i + 1],
                            on: _filters.kinds.contains(
                              DiscoverKind.values[i + 1],
                            ),
                            onTap: () => _toggle(DiscoverKind.values[i + 1]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            const SizedBox(height: 10),
            const _SectionLabel('When'),
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
                  _Pill(
                    label: entry.value,
                    selected: _filters.date == entry.key,
                    onTap: () => setState(
                      () => _filters = _filters.copyWith(date: entry.key),
                    ),
                  ),
                _Pill(
                  label: _filters.date == DiscoverFilters.customDate
                      ? _filters.dateLabel
                      : 'Custom dates',
                  icon: Icons.date_range_rounded,
                  selected: _filters.date == DiscoverFilters.customDate,
                  onTap: _pickRange,
                ),
              ],
            ),

            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionLabel('Distance'),
                Text(
                  DiscoverFilters.radiusLabel(_filters.radius),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Wrap rather than a Row of Expanded. Five equal fifths of a
            // phone's width is about 60 pixels, and "National" does not fit
            // in that — it would have been squeezed to a sliver or clipped.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in DiscoverFilters.radii)
                  _Pill(
                    label: DiscoverFilters.radiusLabel(r),
                    selected: r == _filters.radius,
                    onTap: () =>
                        setState(() => _filters = _filters.copyWith(radius: r)),
                  ),
              ],
            ),

            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1C1E),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.pop(context, _filters),
                // Counts what is already loaded. A change of radius or date
                // has to go back to the server, so the number settles after
                // the refetch rather than predicting it here.
                child: Text(
                  _filters.needsRefetch(widget.initial)
                      ? 'Apply filters'
                      : 'Show $count ${count == 1 ? 'result' : 'results'}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Color(0xFF9A9A9E),
      ),
    );
  }
}

/// One of the four category toggles.
class _KindCard extends StatelessWidget {
  final DiscoverKind kind;
  final bool on;
  final VoidCallback onTap;

  const _KindCard({required this.kind, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFFBF8F1) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on ? const Color(0xFFE2D2AC) : const Color(0xFFEAEAEA),
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: kind.colour,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                  // Said plainly rather than shown as "0". There is nothing
                  // behind these yet, and a zero would claim we looked.
                  if (!kind.backed)
                    const Text(
                      'Coming soon',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF9A9A9E),
                      ),
                    ),
                ],
              ),
            ),
            if (on)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: Color(0xFF1C1C1E),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFEAEAEA),
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : const Color(0xFF1C1C1E),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF1C1C1E),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the map is centred, as a place rather than a coordinate.
@immutable
class DiscoverLocation {
  final String label;
  final double latitude;
  final double longitude;

  /// True for the device's own position, which is the one case where the
  /// label should follow the user rather than stay where it was set.
  final bool isCurrent;

  const DiscoverLocation({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.isCurrent = false,
  });
}

/// Search for a town, postcode or address to centre the map on.
///
/// Opened by the right-hand half of the search bar. Splitting the bar this
/// way means the text field only ever does one thing — filter by title — so
/// typing "Croft" cannot ambiguously mean a venue or a village.
class DiscoverLocationSheet extends StatefulWidget {
  final String current;

  const DiscoverLocationSheet({super.key, required this.current});

  @override
  State<DiscoverLocationSheet> createState() => _DiscoverLocationSheetState();
}

class _DiscoverLocationSheetState extends State<DiscoverLocationSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  List<DiscoverLocation> _results = const [];
  bool _searching = false;
  String? _error;

  /// Rises with each search so a slow early query cannot overwrite the
  /// results of a later, faster one.
  int _searchId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Geocoding is a platform call with a real cost, so this waits for a
    // pause in typing rather than firing per keystroke.
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String term) async {
    final query = term.trim();
    if (query.length < 3) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }

    final id = ++_searchId;
    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final found = await locationFromAddress(query);
      if (!mounted || id != _searchId) return;

      // locationFromAddress gives coordinates and nothing else, so each one
      // is turned back into a name. Usually one or two results, so the extra
      // calls are cheap — and a list of bare coordinates would be useless.
      final labelled = <DiscoverLocation>[];
      for (final loc in found.take(5)) {
        labelled.add(
          DiscoverLocation(
            label: await _describe(loc.latitude, loc.longitude) ?? query,
            latitude: loc.latitude,
            longitude: loc.longitude,
          ),
        );
      }

      if (!mounted || id != _searchId) return;
      setState(() {
        _results = labelled;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || id != _searchId) return;
      // The platform geocoder throws for "no match" as well as for real
      // failures, and cannot distinguish them. Both mean the same to a user.
      setState(() {
        _results = const [];
        _searching = false;
        _error = 'Nothing found for "$query".';
      });
    }
  }

  Future<String?> _describe(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isEmpty) return null;
      final m = marks.first;
      final parts = <String>[
        for (final p in [m.locality, m.subAdministrativeArea, m.country])
          if (p != null && p.trim().isNotEmpty) p.trim(),
      ];
      // Distinct parts only: "Darlington, Darlington, United Kingdom" is how
      // UK unitary authorities come back, and it reads like a bug.
      final seen = <String>{};
      final unique = parts.where(seen.add).toList();
      return unique.isEmpty ? null : unique.join(', ');
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the sheet above the keyboard, which otherwise covers the
      // results the user is typing to find.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: _Grabber()),
            const SizedBox(height: 6),
            const Text(
              'Search a location',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F4),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    size: 19,
                    color: Color(0xFF8A8A8E),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _onChanged,
                      onSubmitted: _search,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Town, city or postcode',
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (_searching)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.my_location_rounded,
                size: 20,
                color: Color(0xFF1C1C1E),
              ),
              title: const Text(
                'Use my current location',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(
                context,
                const DiscoverLocation(
                  label: 'Near me',
                  latitude: 0,
                  longitude: 0,
                  isCurrent: true,
                ),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8A8A8E),
                  ),
                ),
              ),

            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.34,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final r = _results[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.place_outlined,
                      size: 20,
                      color: Color(0xFF8A8A8E),
                    ),
                    title: Text(
                      r.label,
                      style: const TextStyle(fontSize: 14.5),
                    ),
                    onTap: () => Navigator.pop(context, r),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
