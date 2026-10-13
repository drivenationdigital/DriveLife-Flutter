import 'dart:async';
import 'dart:convert';

import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/api/places_api.dart';
import 'package:drivelife/config/mapbox_config.dart';
import 'package:drivelife/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import 'discover_filters.dart';
import 'discover_place.dart';
import 'discover_pins.dart';
import 'discover_sheet.dart';
import 'discover_tips.dart';

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
/// **The results and the pins are one list.** `discoverVisible` produces it
/// once, and it is both the sheet's contents and the map source's features.
///
/// It has to be the source, not a filter on the pin layer: clustering is
/// computed on the source before any layer filter runs, so a filtered layer
/// over a full source gives cluster badges that count results the map is not
/// drawing. That is exactly what happened — picking "Events" left the venues
/// inside each cluster in its total.
/// Why the map cannot show where you are.
///
/// Three separate states rather than one "no access" flag, because the way
/// out of each is different: turning the device's location services back on,
/// granting a permission that can still be asked for, or opening the system
/// settings for one that cannot. A single flag would offer the wrong button
/// two times out of three.
enum DiscoverAccess {
  /// The first check has not finished. Distinct from denied so the screen
  /// does not flash a permission prompt before it knows one is needed.
  checking,

  granted,

  /// Location is switched off for the whole device.
  servicesOff,

  /// Refused, but can be asked again.
  denied,

  /// Refused permanently. Only the system settings can undo this; asking
  /// again returns immediately without showing anything, which looks to the
  /// user like a dead button.
  deniedForever,
}

class DiscoverMapScreen extends StatefulWidget {
  const DiscoverMapScreen({super.key});

  @override
  State<DiscoverMapScreen> createState() => _DiscoverMapScreenState();
}

class _DiscoverMapScreenState extends State<DiscoverMapScreen>
    with WidgetsBindingObserver {
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

  /// Where the selected pin currently is on screen, in logical pixels.
  ///
  /// The callout is positioned from this rather than parked at a fixed
  /// height, so it stays attached to its pin while the map moves. Null when
  /// nothing is selected, or while the projection has not been taken yet.
  ///
  /// A ValueNotifier rather than a field behind setState, because this
  /// changes on every frame of a pan. setState would rebuild the whole
  /// screen at that rate — the chrome, the map widget and, worst of all, the
  /// results sheet, whose children being rebuilt mid-gesture is what made it
  /// impossible to drag open in the first place. Only the callout needs to
  /// move, so only the callout rebuilds.
  final ValueNotifier<Offset?> _pinAt = ValueNotifier<Offset?>(null);

  /// True while a projection is in flight.
  ///
  /// pixelForCoordinate is a call across the platform channel and the camera
  /// reports a change every frame of a pan. Queuing one per frame would build
  /// a backlog that arrives after the gesture has finished, so a frame that
  /// finds one already running simply skips: the next camera change takes a
  /// fresh reading, and the only cost of dropping one is a callout a frame
  /// behind the map.
  bool _projecting = false;

  bool _loading = false;
  String _query = '';

  DiscoverAccess _access = DiscoverAccess.checking;

  /// Whether the tour has been considered this session. The style can load
  /// more than once — it reloads with the style, and on some devices again
  /// after a backgrounding — and the tour should not reappear each time.
  bool _tipsOffered = false;

  /// Whether the camera has been put over the user yet.
  ///
  /// The fix and the map's style arrive in whichever order they please, and
  /// the camera can only be moved once both have. Whichever lands second does
  /// the centring; this stops the first one being undone, and stops a later
  /// reload dragging the camera back after the user has panned away.
  bool _centred = false;

  double? _lat;
  double? _lng;
  String _locationLabel = 'Near me';

  /// Whether [_lat]/[_lng] came from the device or from a place the user
  /// searched for. A searched centre must survive a refetch, so "my location"
  /// only re-reads the GPS when this is true.
  bool _followingDevice = true;

  DiscoverFilters _filters = DiscoverFilters.initial;

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
    // The token is read and applied once in main(), before runApp.
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Granting the permission happens in the system settings, in another app.
    // Without re-checking on the way back, the user returns to the same
    // "enable location" screen they just satisfied and concludes it is broken.
    if (state == AppLifecycleState.resumed &&
        _access != DiscoverAccess.granted) {
      _checkAccess(request: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _pinAt.dispose();
    super.dispose();
  }

  // ── may we know where we are ──────────────────────────────────────────

  /// Works out whether a position can be had, and asks for it if so.
  ///
  /// [request] is false when returning from the system settings: the OS
  /// prompt can only be raised from a user action, and firing it on every
  /// resume would pop a dialog at someone who has just dismissed one.
  Future<void> _checkAccess({bool request = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) setState(() => _access = DiscoverAccess.servicesOff);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && request) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return;

    final access = switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => DiscoverAccess.granted,
      LocationPermission.deniedForever => DiscoverAccess.deniedForever,
      // unableToDetermine behaves like a refusal that can be retried, which
      // is the only useful thing to offer for it.
      _ => DiscoverAccess.denied,
    };

    final wasGranted = _access == DiscoverAccess.granted;
    setState(() => _access = access);

    // Only on the transition into granted. Re-running on every resume would
    // refetch and yank the camera back every time the app is foregrounded.
    if (access == DiscoverAccess.granted && !wasGranted) await _locate();
  }

  /// Offers the tour, the first time someone gets this far.
  ///
  /// After the style has loaded rather than in initState, so the tips appear
  /// over a drawn map instead of a grey rectangle — and so someone who never
  /// gets past the location gate is not shown a tour of a page they cannot
  /// use yet.
  Future<void> _maybeShowTips() async {
    if (_tipsOffered || !mounted) return;
    _tipsOffered = true;

    if (!await DiscoverTips.shouldShow()) return;
    if (!mounted) return;

    await showDiscoverTips(context);
  }

  /// Opens the right system screen for the current obstacle.
  Future<void> _resolveAccess() async {
    switch (_access) {
      case DiscoverAccess.servicesOff:
        await Geolocator.openLocationSettings();
      case DiscoverAccess.deniedForever:
        await Geolocator.openAppSettings();
      case DiscoverAccess.denied:
        // Still askable, so ask rather than sending them to settings.
        await _checkAccess();
      case DiscoverAccess.checking:
      case DiscoverAccess.granted:
        break;
    }
  }

  // ── where we are ──────────────────────────────────────────────────────

  /// Finds the device, moves the map onto it, and loads what is around it.
  ///
  /// Always centres. It used to take a `recentre` flag that the opening call
  /// left false, so the only thing that moved the camera on launch was the
  /// style-loaded handler — and that only fired the move if the fix had
  /// already arrived. A fix takes longer than a style load, so on a cold open
  /// neither ran and the map sat on Mapbox's default world view until the
  /// user centred it by hand.
  Future<void> _locate() async {
    _followingDevice = true;

    // Whatever was selected belongs to wherever the map used to be. Flying
    // somewhere else leaves its card on screen describing a pin that is no
    // longer under it, and — if the pin lands off screen — with its close
    // button out of reach too. The search-a-location path already did this;
    // going back to the device did not.
    _clearSelection();

    final coords = await LocationService.getCoordinates();
    if (!mounted) return;

    if (coords == null) {
      // Permission is granted but no fix came back - indoors, or the first
      // read after a cold boot. Load something rather than nothing, and say
      // in the chip that this is not "near me".
      setState(() => _locationLabel = 'United Kingdom');
      await _load();
      return;
    }

    final lat = coords['latitude']!;
    final lng = coords['longitude']!;

    setState(() {
      _lat = lat;
      _lng = lng;
    });

    unawaited(_describe(lat, lng));
    await _centreOnUser();
    await _load();
  }

  /// Puts the camera over the device, once there is both a fix and a map.
  ///
  /// Called from whichever of those two arrives second. Guarded by [_centred]
  /// so a later reload cannot drag the camera back after the user has panned
  /// somewhere else.
  Future<void> _centreOnUser() async {
    if (_centred || _map == null || _lat == null || _lng == null) return;
    _centred = true;
    await _flyTo(_lat!, _lng!);
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

    // 'custom' rather than 'near-me', whenever a centre is known.
    //
    // This is not a preference, it is the only way the coordinates are read.
    // On 'near-me' the server ignores the latitude and longitude in the
    // request entirely and uses the last_location stored on the user's
    // profile - so searching for a town moved the camera and changed nothing
    // else. 'custom' is the one branch that honours what is sent.
    //
    // It also means the search follows the map: whatever the user is looking
    // at is what gets searched, rather than where their profile says they
    // live.
    final centred = _lat != null && _lng != null;
    final where = centred ? 'custom' : 'near-me';

    // Both at once. They hit different post types and neither depends on the
    // other, so waiting for one before starting the other would double the
    // time the map sits empty.
    final responses = await Future.wait([
      EventsAPI.getEvents(
        page: 1,
        limit: 100,
        location: where,
        dateFilter: _filters.date,
        customDateFrom: _filters.range?.start,
        customDateTo: _filters.range?.end,
        latitude: _lat,
        longitude: _lng,
        customLocation: centred ? _locationLabel : null,
        customLat: _lat,
        customLng: _lng,
        // The server otherwise pins 'custom' to 15 miles for events and 50
        // for venues, whatever the distance filter says.
        radiusMiles: _filters.radius,
      ),
      VenueApiService.getTrendingVenues(
        page: 1,
        limit: 100,
        location: where,
        latitude: _lat,
        longitude: _lng,
        customLocation: centred ? _locationLabel : null,
        customLat: _lat,
        customLng: _lng,
        radiusMiles: _filters.radius,
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
        filter: _pinFilter,
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

    // Press and hold anywhere to search there.
    //
    // The same path as picking a place in the location sheet — it sets the
    // centre and refetches — so there is nothing special about the results,
    // only about how the point was chosen. Useful for the places that have
    // no name worth typing: a stretch of coast, a junction, a meet spot.
    map.addInteraction(
      mb.LongTapInteraction.onMap((context) => _searchAt(context.point)),
    );

    // Tapping the map itself clears the selection, so the callout can be
    // dismissed without hunting for a close button. Pin and cluster taps
    // stop propagating, so this only fires on a tap that hit neither.
    map.addInteraction(
      mb.TapInteraction.onMap((_) => _clearSelection(), stopPropagation: false),
    );

    _styleReady = true;
    await _push();
    unawaited(_maybeShowTips());
    // If the fix got here first, this is the half that centres the map.
    await _centreOnUser();
  }

  /// Which pins the map draws: the ones that are not clusters.
  ///
  /// Categories are not filtered here. They decide what goes into the source
  /// instead — see [_geojson] — so that the clusters agree with the pins.
  static const List<Object> _pinFilter = <Object>[
    '!',
    ['has', 'point_count'],
  ];

  /// The visible results as GeoJSON.
  ///
  /// [_visible], not [_places]: the source has to hold the filtered set
  /// rather than everything, because clustering is computed on the source
  /// before any layer filter runs. Filtering the pins in the layer and
  /// leaving the source full meant a cluster's point_count counted results
  /// that were not being drawn — pick "Events" and the badge still included
  /// the venues inside it — and the search box, which never had a layer
  /// filter at all, narrowed the list while the map carried on showing
  /// everything.
  String _geojson() => jsonEncode({
    'type': 'FeatureCollection',
    'features': [for (final p in _visible) p.toFeature()],
  });

  /// Hands the source its new contents.
  ///
  /// Setting the `data` property re-reads the whole collection, which is the
  /// supported way to update a GeoJSON source and is cheap at these counts.
  Future<void> _push() async {
    if (!_styleReady) return;
    await _map?.setStyleSourceProperty(_sourceId, 'data', _geojson());
  }

  /// Re-renders the map for a change that did not need the server.
  ///
  /// A category chip, a filter-sheet change or a search term all alter which
  /// results are on offer, and all three go through here so the pins, the
  /// clusters and the list cannot disagree. Re-encoding a few hundred
  /// features and letting Mapbox re-cluster them is cheap, and much easier to
  /// reason about than keeping a layer filter and the cluster maths in step.
  Future<void> _refreshMap() => _push();

  Future<void> _flyTo(
    double lat,
    double lng, {
    double? zoom,
    mb.MbxEdgeInsets? padding,
  }) async {
    await _map?.flyTo(
      mb.CameraOptions(
        center: mb.Point(coordinates: mb.Position(lng, lat)),
        zoom: zoom ?? 10.5,
        padding: padding,
      ),
      mb.MapAnimationOptions(duration: 900),
    );
    // The camera stops reporting changes once it arrives, so take a final
    // reading: without it the callout is left where the animation last
    // reported, a frame short of where the pin ended up.
    await _trackPin();
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

  /// Re-reads where the selected pin sits on screen.
  Future<void> _trackPin() async {
    final map = _map;
    final place = _selected;

    if (map == null || place == null) {
      _pinAt.value = null;
      return;
    }
    if (_projecting) return;

    _projecting = true;
    try {
      final at = await map.pixelForCoordinate(
        mb.Point(coordinates: mb.Position(place.longitude, place.latitude)),
      );
      // The selection can change, or the screen can go, while this is in the
      // air. Writing the answer then would put the callout on the wrong pin.
      if (!mounted || !identical(_selected, place)) return;

      // ValueNotifier already drops a write that equals the current value,
      // so a still camera costs nothing.
      _pinAt.value = Offset(at.x, at.y);
    } catch (_) {
      // Projection fails if it is asked before the camera settles. The
      // callout keeps its last position until the next camera change, which
      // is a frame away.
    } finally {
      _projecting = false;
    }
  }

  /// Puts the map back to having nothing selected.
  void _clearSelection() {
    _pinAt.value = null;
    if (_selected != null && mounted) setState(() => _selected = null);
  }

  void _select(DiscoverPlace place) {
    // Dropped, not kept. The old position belongs to the previous pin, and
    // showing the new card there for a frame makes it visibly jump.
    _pinAt.value = null;
    setState(() => _selected = place);

    // Centred within the part of the map that is actually visible, rather
    // than within the window - camera padding does this honestly, where the
    // old trick of flying to a slightly different latitude guessed at it and
    // guessed differently at every zoom level.
    _flyTo(
      place.latitude,
      place.longitude,
      zoom: 12.5,
      padding: mb.MbxEdgeInsets(
        // Clear of the search bar and chips above...
        top: MediaQuery.paddingOf(context).top + 120,
        left: 0,
        // ...and of the results sheet below.
        bottom:
            MediaQuery.sizeOf(context).height *
            DiscoverResultsSheet.collapsedFor(context),
        right: 0,
      ),
    );
  }

  /// Everything the filter sheet and the search box allow, before the chip
  /// row narrows it to one category.
  ///
  /// This is what the chip counts are drawn from. Counting [_visible]
  /// instead would make every number on the row describe the category
  /// already selected - tap "Events" and "All" would start reporting the
  /// number of events.
  List<DiscoverPlace> get _matching =>
      discoverVisible(_places, kinds: _filters.kinds, query: _query);

  /// The results the user is actually being shown: [_matching], narrowed to
  /// the focused category. The single source for the map's GeoJSON, the
  /// sheet and the "N nearby" heading.
  List<DiscoverPlace> get _visible => discoverVisible(
    _places,
    kinds: _filters.kinds,
    category: _category,
    query: _query,
  );

  // ── chrome ────────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    // Filtering is local, so this is only to avoid rebuilding the list on
    // every keystroke while a finger is still moving across the keyboard.
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _query = value);
      // The search narrows the pins as well as the list. It used to narrow
      // only the list, so typing left the sheet saying "2 nearby" over a map
      // still showing forty pins.
      _refreshMap();
    });
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<DiscoverFilters>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DiscoverFilterSheet(
        initial: _filters,
        countFor: (kinds) =>
            _places.where((p) => kinds.contains(p.kind)).length,
      ),
    );
    if (result == null || !mounted) return;

    final refetch = result.needsRefetch(_filters);
    setState(() {
      _filters = result;
      // A category the user has just switched off must not stay focused in
      // the chip row, or the map would show nothing with no way back.
      if (_category != null && !result.kinds.contains(_category!)) {
        _category = null;
      }
      if (_selected != null && !result.kinds.contains(_selected!.kind)) {
        _selected = null;
      }
    });

    // Categories are applied client-side, so only a radius or date change
    // costs a round trip.
    if (refetch) {
      await _load();
    } else {
      await _refreshMap();
    }
  }

  /// Searches around a point on the map, from a long press.
  Future<void> _searchAt(mb.Point point) async {
    final lat = point.coordinates.lat.toDouble();
    final lng = point.coordinates.lng.toDouble();

    // Confirms the press landed, before the fetch that follows has anything
    // to show. Without it a long press looks like it did nothing for as long
    // as the request takes.
    HapticFeedback.mediumImpact();

    setState(() {
      _followingDevice = false;
      _lat = lat;
      _lng = lng;
      _locationLabel = 'This area';
      _selected = null;
    });
    _pinAt.value = null;

    // Named afterwards, not before: reverse geocoding is a platform call and
    // waiting for it would hold up the results. The chip reads "This area"
    // until the name arrives, and keeps it if none does.
    unawaited(_describe(lat, lng));
    await _load();
  }

  /// Re-centres the map on a place the user searched for.
  Future<void> _openLocationSearch() async {
    final result = await showModalBottomSheet<DiscoverLocation>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DiscoverLocationSheet(current: _locationLabel),
    );
    if (result == null || !mounted) return;

    if (result.isCurrent) {
      _centred = false;
      await _locate();
      return;
    }

    setState(() {
      _followingDevice = false;
      _lat = result.latitude;
      _lng = result.longitude;
      _locationLabel = result.label;
      _selected = null;
    });

    // Asked for explicitly, so it moves the camera whatever _centred says.
    _centred = true;
    await _flyTo(result.latitude, result.longitude);
    await _load();
  }

  /// The selected pin's card, placed against that pin.
  List<Widget> _buildCallout(DiscoverPlace place, Offset pin) {
    final at = DiscoverCallout.placeFor(
      pin: pin,
      screen: MediaQuery.sizeOf(context),
      // What the chrome occupies: status bar, search bar, category chips.
      chrome: MediaQuery.paddingOf(context).top + 110,
    );
    if (at == null) return const [];

    return [
      Positioned(
        left: at.left,
        top: at.top,
        child: DiscoverCallout(
          place: place,
          pointsDown: at.pointsDown,
          onClose: _clearSelection,
          onOpen: () => openPlace(context, place),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!MapboxConfig.isConfigured) return const _MissingToken();

    // Discover is built entirely around "what is near me", so there is
    // nothing to show without a position: every fetch is a radius around a
    // point, and the categories, counts and distances all describe it.
    if (_access != DiscoverAccess.granted) {
      return DiscoverLocationGate(access: _access, onResolve: _resolveAccess);
    }

    final matching = _matching;
    final visible = _category == null
        ? matching
        : matching.where((p) => p.kind == _category).toList();
    final screenHeight = MediaQuery.sizeOf(context).height;

    // Keeps the floating controls clear of the sheet's resting height.
    final aboveSheet =
        screenHeight * DiscoverResultsSheet.collapsedFor(context) + 12;

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
              // Every pan and zoom moves the selected pin on screen, and the
              // callout is pinned to it, so it has to be re-projected as the
              // camera moves. _trackPin drops frames rather than queue them.
              onCameraChangeListener: (_) => _trackPin(),
            ),
          ),

          _DiscoverChrome(
            controller: _searchController,
            locationLabel: _locationLabel,
            following: _followingDevice,
            category: _category,
            kinds: _filters.kinds,
            // Closed over the list build already computed, and counted the
            // same way the sheet counts - so a chip saying 3 opens a list
            // of 3.
            countOf: (kind) => matching.where((p) => p.kind == kind).length,
            total: matching.length,
            loading: _loading,
            onSearch: _onSearchChanged,
            onLocationTap: _openLocationSearch,
            onFilters: _openFilters,
            onCategory: (kind) {
              setState(() {
                _category = kind;
                if (kind != null && _selected?.kind != kind) _selected = null;
              });
              _refreshMap();
            },
          ),

          Positioned(
            right: 16,
            bottom: aboveSheet,
            child: _MapButtons(
              onLocate: () {
                // An explicit request to go back to the device, so the
                // one-shot centring guard is lifted for it.
                _centred = false;
                _locate();
              },
              onFirst: visible.isEmpty ? null : () => _select(visible.first),
            ),
          ),

          // Fills the stack so the callout can be positioned anywhere in
          // it, but paints nothing of its own — an empty Stack does not
          // absorb hits, so map gestures pass straight through.
          if (_selected != null)
            Positioned.fill(
              child: ValueListenableBuilder<Offset?>(
                valueListenable: _pinAt,
                builder: (context, pin, _) {
                  final selected = _selected;
                  if (pin == null || selected == null) {
                    return const SizedBox.shrink();
                  }
                  return Stack(children: _buildCallout(selected, pin));
                },
              ),
            ),

          DiscoverResultsSheet(
            places: visible,
            loading: _loading,
            filters: _filters,
            selected: _selected,
            onTap: _select,
            onOpen: (p) => openPlace(context, p),
            onHelp: () => showDiscoverTips(context),
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

    // Nothing can produce one of these yet, so nothing can tap one. Listed
    // rather than defaulted: when a post type does appear, the compiler asks
    // for its route here instead of silently doing nothing.
    case DiscoverKind.business:
    case DiscoverKind.location:
      break;
  }
}

/// The search bar, location button, filter button and category row.
///
/// The bar is split in two with a divider down the middle, and the halves do
/// different jobs: the left filters the loaded results by title, the right
/// opens a location search that moves the map. One field doing both was the
/// ambiguity worth removing - typing "Croft" could mean the circuit or the
/// village, and only the user knows which.
class _DiscoverChrome extends StatelessWidget {
  final TextEditingController controller;
  final String locationLabel;
  final bool following;
  final DiscoverKind? category;
  final Set<DiscoverKind> kinds;
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
    required this.following,
    required this.category,
    required this.kinds,
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
    // top: true, and nothing above it. The shell gives this destination the
    // whole screen - no status-bar spacer, no app header - so this SafeArea
    // is the only thing holding the bar clear of the clock. While the shell
    // was also inserting a spacer the two stacked, which is what pushed the
    // bar down the screen.
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                              hintText: 'Search events, venues...',
                              hintStyle: TextStyle(
                                fontSize: 15,
                                color: Color(0xFF8A8A8E),
                              ),
                            ),
                          ),
                        ),
                        // The seam. Without it the two halves read as one
                        // field with a decoration stuck on the end, and the
                        // right half does not look tappable.
                        Container(
                          width: 1,
                          height: 24,
                          color: const Color(0xFFE6E6E6),
                        ),
                        _LocationButton(
                          label: locationLabel,
                          loading: loading,
                          following: following,
                          onTap: onLocationTap,
                        ),
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
                    tooltip: 'Filters',
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
                // Only the categories the filter sheet has switched on. A
                // chip for something the sheet is hiding would offer a count
                // the map does not draw.
                for (final kind in DiscoverKind.values)
                  if (kinds.contains(kind))
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

/// The right-hand half of the search bar: where the map is centred, and the
/// way to change it.
class _LocationButton extends StatelessWidget {
  final String label;
  final bool loading;
  final bool following;
  final VoidCallback onTap;

  const _LocationButton({
    required this.label,
    required this.loading,
    required this.following,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 8, 15, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            else
              Icon(
                // A crosshair while the map is following the device, a pin
                // once a place has been searched for - so it is clear at a
                // glance whether "nearby" still means near you.
                following ? Icons.my_location_rounded : Icons.place_rounded,
                size: 15,
                color: const Color(0xFFB08E4F),
              ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
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

/// Shown in place of the map until location is available.
///
/// A whole-page gate rather than a banner because there is no usable half of
/// this screen without a position: every result is a radius around one.
class DiscoverLocationGate extends StatelessWidget {
  final DiscoverAccess access;
  final Future<void> Function() onResolve;

  const DiscoverLocationGate({
    super.key,
    required this.access,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    if (access == DiscoverAccess.checking) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    // Each obstacle gets the words and the button that actually clear it.
    // "Open settings" for something still askable sends people on a detour,
    // and "Allow" for a permanently refused permission is a button that
    // visibly does nothing.
    final (String body, String action) = switch (access) {
      DiscoverAccess.servicesOff => (
        'Location is switched off on this device. Turn it on to see what is '
            'happening near you.',
        'Open location settings',
      ),
      DiscoverAccess.deniedForever => (
        'DriveLife does not have permission to use your location. You can '
            'turn it on in Settings.',
        'Open settings',
      ),
      _ => (
        'Discover shows events, venues and businesses around you. Allow '
            'location access to see what is nearby.',
        'Allow location',
      ),
    };

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F4F4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    size: 34,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Turn on location',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: Color(0xFF8A8A8E),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1C1C1E),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: onResolve,
                    child: Text(
                      action,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The screen unlocks itself when you come back.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: Color(0xFFB0B0B4)),
                ),
              ],
            ),
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
              const Icon(
                Icons.map_outlined,
                size: 48,
                color: Color(0xFF9A9A9A),
              ),
              const SizedBox(height: 16),
              const Text(
                'Map unavailable',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'No Mapbox access token was found.\n'
                'Add one to assets/config/mapbox.json as\n'
                '{"accessToken": "pk...."}',
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
