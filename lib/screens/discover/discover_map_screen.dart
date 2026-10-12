import 'dart:async';
import 'dart:convert';

import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/api/places_api.dart';
import 'package:drivelife/config/mapbox_config.dart';
import 'package:drivelife/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import 'discover_place.dart';
import 'discover_pins.dart';
import 'discover_sheet.dart';

/// Discover: everything nearby, on one map.
///
/// The two things worth knowing about how this is built:
///
/// **Pins are style layers, not annotations.** The AnnotationManager API is
/// easier but puts one platform view's worth of work behind every marker, and
/// a national radius returns hundreds. A GeoJSON source with `cluster: true`
/// gives native clustering, draws entirely on the GPU, and redraws by handing
/// the source a new string.
///
/// **The results and the pins are one list.** [_places] feeds both; the
/// category filter is applied to the map with a style expression and to the
/// sheet with a `where`, from the same enum. There is no way for the sheet to
/// claim a count the map does not show.
class DiscoverMapScreen extends StatefulWidget {
  const DiscoverMapScreen({super.key});

  @override
  State<DiscoverMapScreen> createState() => _DiscoverMapScreenState();
}

class _DiscoverMapScreenState extends State<DiscoverMapScreen> {
  static const String _sourceId = 'dl-discover';
  static const String _clusterLayerId = 'dl-discover-clusters';
  static const String _countLayerId = 'dl-discover-cluster-count';
  static const String _pinLayerId = 'dl-discover-pins';

  /// Where the map opens before a fix arrives. The middle of the UK, zoomed
  /// out far enough to be honest about not knowing yet rather than claiming a
  /// precision it does not have.
  static final mb.Point _fallbackCentre = mb.Point(
    coordinates: mb.Position(-1.5, 53.0),
  );

  mb.MapboxMap? _map;
  bool _styleReady = false;

  List<DiscoverPlace> _places = const [];
  DiscoverKind? _category;
  DiscoverPlace? _selected;

  bool _loading = false;
  String _query = '';

  double? _lat;
  double? _lng;
  String _locationLabel = 'Near me';
  int _radius = 25;
  String _dateFilter = 'anytime';

  /// Guards against an old response overwriting a newer one.
  ///
  /// Changing the radius fires a fresh fetch while the previous one is still
  /// in flight, and the wider search is usually the slower one — so without
  /// this, narrowing from 100 to 25 miles can land the 100-mile results.
  int _fetchId = 0;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    MapboxConfig.ensureInitialised();
    _locate();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── where we are ──────────────────────────────────────────────────────

  Future<void> _locate({bool recentre = false}) async {
    final coords = await LocationService.getCoordinates();
    if (!mounted) return;

    if (coords == null) {
      // No fix: still load something. A national search beats an empty map,
      // and the chip says that "Near me" is not what is being shown.
      setState(() => _locationLabel = 'United Kingdom');
      await _load();
      return;
    }

    setState(() {
      _lat = coords['latitude'];
      _lng = coords['longitude'];
    });

    unawaited(_describe(coords['latitude']!, coords['longitude']!));
    if (recentre) await _flyTo(coords['latitude']!, coords['longitude']!);
    await _load();
  }

  /// Turns the fix into something a human recognises — "Teesside", not
  /// 54.57, -1.23. Best effort: the chip falls back to "Near me" and nothing
  /// else depends on it.
  Future<void> _describe(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (!mounted || marks.isEmpty) return;
      final m = marks.first;
      final name = _firstNonEmpty([
        m.locality,
        m.subAdministrativeArea,
        m.administrativeArea,
      ]);
      if (name != null) setState(() => _locationLabel = name);
    } catch (_) {
      // Geocoding is a nicety. A failure here must not stop the map loading.
    }
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      final t = v?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }

  // ── what is around us ─────────────────────────────────────────────────

  Future<void> _load() async {
    final id = ++_fetchId;
    setState(() => _loading = true);

    // Both at once. They hit different post types and neither depends on the
    // other, so waiting for one before starting the other would double the
    // time the map sits empty.
    final responses = await Future.wait([
      EventsAPI.getEvents(
        page: 1,
        limit: 100,
        location: 'near-me',
        dateFilter: _dateFilter,
        latitude: _lat,
        longitude: _lng,
        radius: _radius,
      ),
      VenueApiService.getTrendingVenues(
        page: 1,
        limit: 100,
        location: 'near-me',
        latitude: _lat,
        longitude: _lng,
        radius: _radius,
      ),
    ]);

    if (!mounted || id != _fetchId) return;

    final places = <DiscoverPlace>[
      ..._read(responses[0], DiscoverPlace.fromEvent),
      ..._read(responses[1], DiscoverPlace.fromVenue),
    ];

    setState(() {
      _places = places;
      _loading = false;
      // A selection from the previous search may no longer be on the map.
      final stillThere = places.any((p) => p.id == _selected?.id);
      if (!stillThere) _selected = null;
    });

    await _push();
  }

  /// Pulls the `data` array out of a response and parses what it can.
  ///
  /// Items without coordinates come back null from the parser and are dropped
  /// here — they cannot be drawn, and listing a result the map does not show
  /// is the disagreement this screen is built to avoid.
  Iterable<DiscoverPlace> _read(
    Map<String, dynamic>? response,
    DiscoverPlace? Function(Map<String, dynamic>) parse,
  ) {
    final data = response?['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => parse(Map<String, dynamic>.from(e)))
        .whereType<DiscoverPlace>();
  }

  // ── the map ───────────────────────────────────────────────────────────

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;
    await map.location.updateSettings(
      mb.LocationComponentSettings(enabled: true, pulsingEnabled: true),
    );
    // The scale bar is noise on a screen this busy.
    await map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));
  }

  Future<void> _onStyleLoaded(mb.StyleLoadedEventData _) async {
    final map = _map;
    if (map == null || !mounted) return;

    // A style reload drops every image, source and layer that was added to
    // it, so all of this has to be redone rather than done once.
    await DiscoverPins.register(map, MediaQuery.devicePixelRatioOf(context));

    await map.addSource(
      mb.GeoJsonSource(
        id: _sourceId,
        data: _geojson(),
        cluster: true,
        // Roughly one pin's width: close enough that overlapping pins merge,
        // far enough that two distinct venues on one street do not.
        clusterRadius: 48,
        // Past this, show the individual pins — by street level a cluster is
        // hiding things the user has already zoomed in to find.
        clusterMaxZoom: 13,
      ),
    );

    await map.addLayer(
      mb.CircleLayer(
        id: _clusterLayerId,
        sourceId: _sourceId,
        filter: const ['has', 'point_count'],
        circleColorExpression: const ['rgba', 28, 28, 30, 1],
        circleStrokeColorExpression: const ['rgba', 255, 255, 255, 1],
        circleStrokeWidth: 2.5,
        // Grows with the count, in steps rather than smoothly: a continuous
        // ramp makes 7 and 9 indistinguishable, which defeats the point.
        circleRadiusExpression: const [
          'step',
          ['get', 'point_count'],
          17,
          10,
          21,
          50,
          26,
        ],
      ),
    );

    await map.addLayer(
      mb.SymbolLayer(
        id: _countLayerId,
        sourceId: _sourceId,
        filter: const ['has', 'point_count'],
        textFieldExpression: const ['get', 'point_count_abbreviated'],
        textSize: 13,
        textColorExpression: const ['rgba', 255, 255, 255, 1],
        textIgnorePlacement: true,
        textAllowOverlap: true,
      ),
    );

    await map.addLayer(
      mb.SymbolLayer(
        id: _pinLayerId,
        sourceId: _sourceId,
        filter: _pinFilter(),
        iconImageExpression: const ['get', 'icon'],
        iconAnchor: mb.IconAnchor.BOTTOM,
        // Pins must not be dropped when they collide. A map that silently
        // hides results is worse than a crowded one, and the clustering
        // already handles density.
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
    );

    // Tapping a pin selects it. Registered against the layer id, so taps on
    // empty map or on Mapbox's own POIs fall through untouched.
    map.addInteraction(
      mb.TapInteraction(
        mb.FeaturesetDescriptor(layerId: _pinLayerId),
        (feature, _) => _selectById(feature.properties['id']?.toString()),
      ),
    );

    // Tapping a cluster zooms into it, which is the only sensible thing a
    // cluster can do.
    map.addInteraction(
      mb.TapInteraction(
        mb.FeaturesetDescriptor(layerId: _clusterLayerId),
        (_, context) => _zoomIn(context.point),
      ),
    );

    // Tapping the map itself clears the selection, so the callout can be
    // dismissed without hunting for a close button. Pin and cluster taps
    // stop propagating, so this only fires on a tap that hit neither.
    map.addInteraction(
      mb.TapInteraction.onMap((_) {
        if (_selected != null) setState(() => _selected = null);
      }, stopPropagation: false),
    );

    _styleReady = true;
    await _push();
    if (_lat != null && _lng != null) await _flyTo(_lat!, _lng!);
  }

  /// Which pins the map draws, as a style expression.
  ///
  /// Clusters are excluded here and drawn by their own layer. The category
  /// filter is applied in the same expression so switching chips is a
  /// property change on an existing layer, not a rebuild of the source.
  List<Object> _pinFilter() {
    const notACluster = <Object>[
      '!',
      ['has', 'point_count'],
    ];
    if (_category == null) return notACluster;
    return <Object>[
      'all',
      notACluster,
      <Object>[
        '==',
        const ['get', 'kind'],
        _category!.name,
      ],
    ];
  }

  String _geojson() => jsonEncode({
    'type': 'FeatureCollection',
    'features': [for (final p in _places) p.toFeature()],
  });

  /// Hands the source its new contents.
  ///
  /// Setting the `data` property re-reads the whole collection, which is the
  /// supported way to update a GeoJSON source and is cheap at these counts.
  Future<void> _push() async {
    if (!_styleReady) return;
    await _map?.setStyleSourceProperty(_sourceId, 'data', _geojson());
  }

  Future<void> _applyCategoryFilter() async {
    if (!_styleReady) return;
    await _map?.setStyleLayerProperty(
      _pinLayerId,
      'filter',
      _pinFilter(),
    );
  }

  Future<void> _flyTo(double lat, double lng, {double? zoom}) async {
    await _map?.flyTo(
      mb.CameraOptions(
        center: mb.Point(coordinates: mb.Position(lng, lat)),
        zoom: zoom ?? 10.5,
      ),
      mb.MapAnimationOptions(duration: 900),
    );
  }

  Future<void> _zoomIn(mb.Point at) async {
    final camera = await _map?.getCameraState();
    await _map?.flyTo(
      mb.CameraOptions(center: at, zoom: (camera?.zoom ?? 10) + 2.2),
      mb.MapAnimationOptions(duration: 600),
    );
  }

  // ── selection ─────────────────────────────────────────────────────────

  void _selectById(String? id) {
    if (id == null) return;
    for (final p in _visible) {
      if (p.id == id) {
        _select(p);
        return;
      }
    }
  }

  void _select(DiscoverPlace place) {
    setState(() => _selected = place);
    // Lift the pin clear of the sheet and the callout. Without the nudge the
    // thing just selected sits underneath the card describing it.
    _flyTo(place.latitude - 0.012, place.longitude, zoom: 12.5);
  }

  /// The results the user is actually being shown, after the category chip
  /// and the search box. The single source for every count on screen.
  List<DiscoverPlace> get _visible {
    final q = _query.trim().toLowerCase();
    return _places.where((p) {
      if (_category != null && p.kind != _category) return false;
      if (q.isEmpty) return true;
      return p.title.toLowerCase().contains(q) ||
          (p.subtitle?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  int _countOf(DiscoverKind kind) =>
      _places.where((p) => p.kind == kind).length;

  // ── chrome ────────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    // Filtering is local, so this is only to avoid rebuilding the list on
    // every keystroke while a finger is still moving across the keyboard.
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = value);
    });
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<DiscoverFilters>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => DiscoverFilterSheet(
        initial: DiscoverFilters(radius: _radius, date: _dateFilter),
      ),
    );
    if (result == null || !mounted) return;
    if (result.radius == _radius && result.date == _dateFilter) return;

    setState(() {
      _radius = result.radius;
      _dateFilter = result.date;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!MapboxConfig.isConfigured) return const _MissingToken();

    final visible = _visible;
    final screenHeight = MediaQuery.sizeOf(context).height;

    // Keeps the floating controls clear of the sheet's resting height.
    final aboveSheet = screenHeight * DiscoverResultsSheet.collapsed + 12;

    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      body: Stack(
        children: [
          Positioned.fill(
            child: mb.MapWidget(
              key: const ValueKey('dl-discover-map'),
              // Hybrid Composition. Marked experimental by the plugin but
              // required, with no non-experimental value to pass; HC is the
              // mode that composites Flutter widgets correctly over a
              // full-screen native map.
              // ignore: experimental_member_use
              androidHostingMode: mb.AndroidPlatformViewHostingMode.HC,
              styleUri: MapboxConfig.styleUri,
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
            ),
          ),

          _DiscoverChrome(
            controller: _searchController,
            locationLabel: _locationLabel,
            category: _category,
            countOf: _countOf,
            total: _places.length,
            loading: _loading,
            onSearch: _onSearchChanged,
            onLocationTap: () => _locate(recentre: true),
            onFilters: _openFilters,
            onCategory: (kind) {
              setState(() {
                _category = kind;
                if (kind != null && _selected?.kind != kind) _selected = null;
              });
              _applyCategoryFilter();
            },
          ),

          Positioned(
            right: 16,
            bottom: aboveSheet,
            child: _MapButtons(
              onLocate: () => _locate(recentre: true),
              onFirst: visible.isEmpty ? null : () => _select(visible.first),
            ),
          ),

          if (_selected != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: aboveSheet + 60,
              child: DiscoverCallout(
                place: _selected!,
                onClose: () => setState(() => _selected = null),
                onOpen: () => openPlace(context, _selected!),
              ),
            ),

          DiscoverResultsSheet(
            places: visible,
            loading: _loading,
            radius: _radius,
            dateFilter: _dateFilter,
            selected: _selected,
            onTap: _select,
            onOpen: (p) => openPlace(context, p),
          ),
        ],
      ),
    );
  }
}

/// Opens the detail screen for whatever was tapped.
///
/// Events are handed their original JSON because that is what the event
/// detail route has always taken from every other list in the app; venues are
/// opened by id, which is what theirs takes.
void openPlace(BuildContext context, DiscoverPlace place) {
  switch (place.kind) {
    case DiscoverKind.event:
      Navigator.pushNamed(
        context,
        '/event-detail',
        arguments: {'event': place.raw},
      );
    case DiscoverKind.venue:
      Navigator.pushNamed(
        context,
        '/venue-details',
        arguments: {'venueId': place.id},
      );
  }
}

/// The search bar, location chip, filter button and category row.
class _DiscoverChrome extends StatelessWidget {
  final TextEditingController controller;
  final String locationLabel;
  final DiscoverKind? category;
  final int Function(DiscoverKind) countOf;
  final int total;
  final bool loading;
  final ValueChanged<String> onSearch;
  final VoidCallback onLocationTap;
  final VoidCallback onFilters;
  final ValueChanged<DiscoverKind?> onCategory;

  const _DiscoverChrome({
    required this.controller,
    required this.locationLabel,
    required this.category,
    required this.countOf,
    required this.total,
    required this.loading,
    required this.onSearch,
    required this.onLocationTap,
    required this.onFilters,
    required this.onCategory,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _Floating(
                    radius: 26,
                    child: Row(
                      children: [
                        const SizedBox(width: 14),
                        const Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: Color(0xFF8A8A8E),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            onChanged: onSearch,
                            textInputAction: TextInputAction.search,
                            style: const TextStyle(fontSize: 15),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Search nearby',
                              hintStyle: TextStyle(
                                fontSize: 15,
                                color: Color(0xFF8A8A8E),
                              ),
                            ),
                          ),
                        ),
                        _LocationChip(
                          label: locationLabel,
                          loading: loading,
                          onTap: onLocationTap,
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _Floating(
                  radius: 26,
                  width: 52,
                  child: IconButton(
                    onPressed: onFilters,
                    icon: const Icon(Icons.tune_rounded, size: 21),
                    color: const Color(0xFF1C1C1E),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _CategoryChip(
                  label: 'All',
                  count: total,
                  selected: category == null,
                  onTap: () => onCategory(null),
                ),
                for (final kind in DiscoverKind.values)
                  _CategoryChip(
                    label: kind.label,
                    count: countOf(kind),
                    dot: kind.colour,
                    selected: category == kind,
                    onTap: () => onCategory(kind),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A white, rounded, shadowed surface — the one used by everything that
/// floats over the map, so they all catch the light the same way.
class _Floating extends StatelessWidget {
  final Widget child;
  final double radius;
  final double? width;

  const _Floating({required this.child, required this.radius, this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LocationChip extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _LocationChip({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            else
              const Icon(
                Icons.place_rounded,
                size: 14,
                color: Color(0xFF1C1C1E),
              ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 86),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C1E),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color? dot;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.dot,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : const Color(0xFF1C1C1E);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(19),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dot,
                    shape: BoxShape.circle,
                    // A black dot on a black selected chip would vanish.
                    border: selected
                        ? Border.all(color: Colors.white54, width: 1)
                        : null,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: foreground.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// My-location and jump-to-first-result, stacked at the right edge.
class _MapButtons extends StatelessWidget {
  final VoidCallback onLocate;
  final VoidCallback? onFirst;

  const _MapButtons({required this.onLocate, required this.onFirst});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _round(Icons.my_location_rounded, onLocate),
        const SizedBox(height: 10),
        _round(Icons.format_list_bulleted_rounded, onFirst),
      ],
    );
  }

  Widget _round(IconData icon, VoidCallback? onTap) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, size: 20, color: const Color(0xFF1C1C1E)),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the map when the build has no Mapbox token.
///
/// Explicit, because the alternative is a blank grey rectangle that looks
/// like a bug in this screen rather than a missing `--dart-define`.
class _MissingToken extends StatelessWidget {
  const _MissingToken();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, size: 48, color: Color(0xFF9A9A9A)),
              const SizedBox(height: 16),
              const Text(
                'Map unavailable',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'This build was compiled without a Mapbox access token.\n'
                'Rebuild with --dart-define=MAPBOX_TOKEN=pk.…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
