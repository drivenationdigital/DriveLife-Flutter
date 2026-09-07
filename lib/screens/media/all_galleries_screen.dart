import 'dart:async';

import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/screens/media/gallery_view_screen.dart';
import 'package:drivelife/widgets/media/gallery_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// What a gallery is linked to, as a filter.
enum GalleryFilter { all, event, venue, location, none }

extension on GalleryFilter {
  /// Wire value for `link_type`. Null for [GalleryFilter.all], which sends no
  /// filter at all rather than a value meaning "everything".
  String? get wire => switch (this) {
    GalleryFilter.all => null,
    GalleryFilter.event => 'event',
    GalleryFilter.venue => 'venue',
    GalleryFilter.location => 'location',
    GalleryFilter.none => 'none',
  };

  String get label => switch (this) {
    GalleryFilter.all => 'All',
    GalleryFilter.event => 'Events',
    GalleryFilter.venue => 'Venues',
    GalleryFilter.location => 'Locations',
    GalleryFilter.none => 'Standalone',
  };
}

/// Every gallery on the site, newest first, with filters.
///
/// Reached from "See all" on the media tab, which used to jump to the Events
/// tab — a different thing entirely, and no way to browse galleries at all.
///
/// Ordering is by upload date rather than by the event's date: a gallery from
/// last year's meet uploaded today is new to everyone looking at this list.
class AllGalleriesScreen extends StatefulWidget {
  const AllGalleriesScreen({super.key});

  @override
  State<AllGalleriesScreen> createState() => _AllGalleriesScreenState();
}

class _AllGalleriesScreenState extends State<AllGalleriesScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFAE9159);

  static const int _perPage = 20;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  final List<Map<String, dynamic>> _galleries = [];

  GalleryFilter _filter = GalleryFilter.all;
  DateTimeRange? _dates;

  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  /// Debounces the search box.
  Timer? _debounce;

  /// Guards against a slow response for an old query landing after a newer one.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) _loadMore();
  }

  Future<void> _load() async {
    final id = ++_requestId;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final galleries = await _fetch(page: 1);
      if (!mounted || id != _requestId) return;

      setState(() {
        _galleries
          ..clear()
          ..addAll(galleries);
        _page = 1;
        _hasMore = galleries.length >= _perPage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;

    final id = _requestId;
    setState(() => _loadingMore = true);

    try {
      final next = _page + 1;
      final galleries = await _fetch(page: next);

      // A filter changed while this was in flight — its result belongs to a
      // list that no longer exists.
      if (!mounted || id != _requestId) return;

      setState(() {
        _galleries.addAll(galleries);
        _page = next;
        _hasMore = galleries.length >= _perPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      // Silent: the list already on screen is still valid, and scrolling will
      // try again.
      setState(() => _loadingMore = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetch({required int page}) {
    return EventsAPI.fetchGalleries(
      scope: 'all',
      linkType: _filter.wire,
      search: _searchController.text,
      from: _dates?.start,
      to: _dates?.end,
      page: page,
      perPage: _perPage,
    );
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  void _setFilter(GalleryFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    _load();
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();

    final picked = await showDateRangePicker(
      context: context,
      // Galleries cannot predate the app; the upper bound is today because
      // this filters upload dates, which cannot be in the future.
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dates,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: _gold, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    setState(() => _dates = picked);
    _load();
  }

  void _clearDates() {
    setState(() => _dates = null);
    _load();
  }

  Future<void> _open(Map<String, dynamic> gallery) async {
    final title = '${gallery['title'] ?? ''}';
    var changed = false;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryViewScreen(
          galleryId: int.tryParse('${gallery['gallery_id']}'),
          entityTitle: title,
          galleryName: title,
          onChanged: () => changed = true,
        ),
      ),
    );

    if (changed && mounted) await _load();
  }

  String get _dateLabel {
    final dates = _dates;
    if (dates == null) return 'Any date';

    final format = DateFormat('d MMM');
    final sameYear = dates.start.year == dates.end.year;
    final year = sameYear ? '' : ' ${dates.end.year}';

    return '${format.format(dates.start)} – ${format.format(dates.end)}$year';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: _ink, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Galleries',
          style: TextStyle(
            color: _ink,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: Column(
        children: [
          _buildFilters(),
          Container(height: 1, color: Colors.grey.shade200),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Search galleries and places',
              hintStyle: const TextStyle(color: _muted, fontSize: 15),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _load();
                      },
                    ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _gold, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Horizontal, not wrapped: five chips plus a date would take two
          // rows on a narrow phone and push the galleries off screen.
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: _dateLabel,
                  icon: Icons.calendar_today_outlined,
                  selected: _dates != null,
                  onTap: _pickDates,
                  onClear: _dates == null ? null : _clearDates,
                ),
                const SizedBox(width: 8),
                for (final filter in GalleryFilter.values) ...[
                  _FilterChip(
                    label: filter.label,
                    selected: _filter == filter,
                    onTap: () => _setFilter(filter),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 34, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_galleries.isEmpty) {
      final filtered =
          _filter != GalleryFilter.all ||
          _dates != null ||
          _searchController.text.trim().isNotEmpty;

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 36,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                // Says which of the two it is, so an over-narrow filter does
                // not read as "there are no galleries".
                filtered ? 'No galleries match' : 'No galleries yet',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (filtered) ...[
                const SizedBox(height: 6),
                const Text(
                  'Try a different filter.',
                  style: TextStyle(fontSize: 13.5, color: _muted),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _gold,
      onRefresh: _load,
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.86,
        ),
        // One extra cell carries the paging spinner, so it does not need a
        // separate sliver under a grid.
        itemCount: _galleries.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _galleries.length) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          final gallery = _galleries[index];
          final count = int.tryParse('${gallery['photo_count']}') ?? 0;
          final owner = gallery['owner'];
          final ownerName = owner is Map ? '${owner['name'] ?? ''}' : '';

          return GalleryCard(
            title: '${gallery['title'] ?? ''}',
            coverUrl: '${gallery['cover_thumb'] ?? gallery['cover'] ?? ''}',
            subtitle: [
              if (ownerName.isNotEmpty) ownerName,
              if (count > 0) '$count photo${count == 1 ? '' : 's'}',
            ].join(' · '),
            onTap: () => _open(gallery),
          );
        },
      ),
    );
  }
}

/// A filter pill. Carries an optional clear control, for the date range.
class _FilterChip extends StatelessWidget {
  static const Color _gold = Color(0xFFAE9159);
  static const Color _muted = Color(0xFF8A8A8A);

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.only(left: 14, right: onClear == null ? 14 : 6),
        decoration: BoxDecoration(
          color: selected ? _gold : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? _gold : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : _muted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : _muted,
              ),
            ),
            if (onClear != null)
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 15,
                  color: selected ? Colors.white : _muted,
                ),
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
          ],
        ),
      ),
    );
  }
}
