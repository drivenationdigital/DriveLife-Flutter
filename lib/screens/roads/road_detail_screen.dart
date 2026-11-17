import 'dart:async';
import 'dart:convert';

import 'package:drivelife/api/garage_api.dart';

import 'package:drivelife/api/roads_api.dart';
import 'package:drivelife/config/mapbox_config.dart';
import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/models/road_navigation.dart';
import 'package:drivelife/models/road_polyline.dart';
import 'package:drivelife/screens/roads/road_drive_sheet.dart';
import 'package:drivelife/screens/roads/road_map_icons.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// One road, drawn.
///
/// ── THE LINE IS A STYLE LAYER, NOT AN ANNOTATION ────────────────────
///
/// Same decision as the Discover map, for the same reason: a GeoJSON
/// source with a LineLayer over it draws on the GPU and is redrawn by
/// handing the source a new string, where the annotation API puts a
/// platform view behind every piece of geometry.
///
/// It matters more here than it looks. A matched road is a point every
/// few metres, so a twelve-mile road is hundreds of coordinates — as
/// one LineString that is nothing, and as annotations it is hundreds of
/// platform objects for a single line.
class RoadDetailScreen extends StatefulWidget {
  /// What the list already knew. Shown immediately so the screen opens
  /// with a title and its numbers rather than a spinner; the detail
  /// call then fills in the shape and the description.
  final DrivingRoad road;

  const RoadDetailScreen({super.key, required this.road});

  @override
  State<RoadDetailScreen> createState() => _RoadDetailScreenState();
}

class _RoadDetailScreenState extends State<RoadDetailScreen> {
  static const String _sourceId = 'dl-road';
  static const String _lineId = 'dl-road-line';
  static const String _casingId = 'dl-road-casing';
  static const String _arrowsId = 'dl-road-arrows';
  static const String _endsSourceId = 'dl-road-ends';
  static const String _endsId = 'dl-road-ends-dots';
  static const String _endLabelsId = 'dl-road-ends-labels';

  /// Hybrid Composition, as the Discover map uses: the mode that
  /// composites Flutter widgets correctly over a full-screen native
  /// map. Marked experimental by the plugin, with no non-experimental
  /// value to pass instead.
  ///
  /// Hoisted to a constant so the ignore sits on the line the analyser
  /// flags — inline at that indentation the value wrapped onto its own
  /// line, leaving the comment one line early and doing nothing.
  // ignore: experimental_member_use
  static const _hosting = mb.AndroidPlatformViewHostingMode.HC;

  late DrivingRoad _road = widget.road;

  mb.MapboxMap? _map;

  bool _loading = true;
  bool _busy = false;

  /// Whether anything was pressed, so the list knows to reload.
  bool _changed = false;

  List<RoadPoint> _points = const [];

  /// The name of the vehicle they recorded, once it has been looked
  /// up. Empty until then, and empty for a vehicle that has since been
  /// deleted — the drive still happened, so the line just loses its
  /// second half rather than the whole thing.
  String _vehicleName = '';

  /// Whether a draw is in flight, and whether another was asked for
  /// while it was.
  ///
  /// ── WHY THIS IS NEEDED ──────────────────────────────────────────
  ///
  /// [_draw] had three callers — the map being created, the style
  /// loading, and the shape arriving — and no guard. Two of them
  /// overlapping is not a wasted redraw, it is a corrupted one: each
  /// pass REMOVES every layer and source before adding them back, so
  /// one pass's removal loop deletes what the other has just added.
  ///
  /// The symptom was specific and was exactly what turned up: the line
  /// drew and the start/end dots did not. The dots are added last, so
  /// they are the layer most likely to be removed by the other pass —
  /// or to be added against a source that pass has already taken away.
  bool _drawing = false;
  bool _drawAgain = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final full = await RoadsAPI.get(widget.road.id);

    if (!mounted) return;

    setState(() {
      if (full != null) _road = full;
      _points = RoadPolyline.decode(_road.polyline);
      _loading = false;
    });

    // Not awaited with the draw: a name under a line is worth a second
    // request, and worth nobody waiting for.
    unawaited(_loadVehicleName());

    await _draw();
  }

  /// Turns the stored garage id into something worth reading.
  ///
  /// The id is what is stored — see sql/roads-drives.sql — because a
  /// vehicle renamed, sold or re-photographed is still the same
  /// vehicle, and a copied string would be wrong the first time
  /// somebody corrected their own car.
  ///
  /// Which means the name has to be fetched. One request, only when
  /// there is an id, and a failure leaves the line reading "You drove
  /// this in August 2019" rather than nothing at all.
  Future<void> _loadVehicleName() async {
    final id = _road.myVehicleId;

    if (id <= 0) {
      if (mounted && _vehicleName.isNotEmpty) {
        setState(() => _vehicleName = '');
      }

      return;
    }

    final vehicle = await GarageAPI.getGarageById('$id');

    if (!mounted || vehicle == null) return;

    final name = [
      '${vehicle['make'] ?? ''}'.trim(),
      '${vehicle['model'] ?? ''}'.trim(),
    ].where((p) => p.isNotEmpty).join(' ');

    setState(() => _vehicleName = name);
  }

  // ── the map ───────────────────────────────────────────────────────

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;

    await map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));

    // No draw here. A map that has just been created has no style yet,
    // so everything below would be added to nothing — and then the
    // style load would run it all again, which is one of the two
    // overlapping passes that lost the dots. onStyleLoadedListener
    // always fires, so there is nothing to catch here.
  }

  /// Puts the line on the style, one pass at a time.
  ///
  /// Called when the style loads and when the shape arrives, in either
  /// order. Overlapping passes are what [_drawing] exists to stop; a
  /// request that arrives mid-pass is remembered and run afterwards, so
  /// the last word still wins.
  Future<void> _draw() async {
    if (_drawing) {
      _drawAgain = true;
      return;
    }

    _drawing = true;

    try {
      do {
        _drawAgain = false;
        await _drawOnce();
      } while (_drawAgain && mounted);
    } finally {
      _drawing = false;
    }
  }

  Future<void> _drawOnce() async {
    final map = _map;

    if (map == null || _points.length < 2 || !mounted) return;

    // Read here, before anything is awaited, and passed down. _install
    // is a dozen platform calls deep by the time it needs either of
    // these, and a context read after an await is a read against a
    // widget that may already have gone.
    final accent = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).primaryColor;

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    try {
      await _install(map, accent, pixelRatio);
    } catch (e) {
      // Said rather than swallowed. A half-drawn map is the symptom
      // this whole guard exists for, and silence is what made the
      // missing dots take a screenshot to find.
      debugPrint('[Road] could not draw ${_road.id}: $e');
    }
  }

  Future<void> _install(
    mb.MapboxMap map,
    Color accent,
    double pixelRatio,
  ) async {
    // On every style load, not once. A style reload takes its image
    // table with it, and a layer asking for an image that is no longer
    // there draws nothing — which looks exactly like the layer having
    // failed to be added.
    await RoadMapIcons.register(map, pixelRatio);

    // StyleLoaded also fires for a style that is ALREADY carrying our
    // source, and adding a source that exists throws. Layers before the
    // source: a source cannot be removed while a layer references it.
    for (final id in const [
      _casingId,
      _lineId,
      _arrowsId,
      _endsId,
      _endLabelsId,
    ]) {
      if (await map.styleLayerExists(id)) await map.removeStyleLayer(id);
    }

    for (final id in const [_sourceId, _endsSourceId]) {
      if (await map.styleSourceExists(id)) await map.removeStyleSource(id);
    }

    await map.addSource(
      mb.GeoJsonSource(id: _sourceId, data: _lineGeoJson()),
    );

    await map.addSource(
      mb.GeoJsonSource(id: _endsSourceId, data: _endsGeoJson()),
    );

    // Two layers for one line. The casing is a wider, darker line drawn
    // underneath, which is what keeps the road readable over both a
    // pale field and a dark wood — a single stroke disappears into one
    // or the other somewhere along any road worth driving.
    await map.addLayer(
      mb.LineLayer(
        id: _casingId,
        sourceId: _sourceId,
        lineColorExpression: const ['rgba', 11, 11, 11, 0.85],
        lineWidth: 9,
        lineCap: mb.LineCap.ROUND,
        lineJoin: mb.LineJoin.ROUND,
      ),
    );

    await map.addLayer(
      mb.LineLayer(
        id: _lineId,
        sourceId: _sourceId,
        lineColorExpression: [
          'rgba',
          (accent.r * 255).round(),
          (accent.g * 255).round(),
          (accent.b * 255).round(),
          1,
        ],
        lineWidth: 5,
        lineCap: mb.LineCap.ROUND,
        lineJoin: mb.LineJoin.ROUND,
      ),
    );

    // ── WHICH WAY THE ROAD RUNS ───────────────────────────────────
    //
    // Arrowheads along the line, and they need nothing to know about
    // the bends: `symbolPlacement: line` rotates each icon to the
    // direction of travel along the geometry, so they turn where the
    // road turns.
    //
    // The direction itself comes from the order the coordinates are
    // stored in, which is the order they were drawn or routed in. That
    // is what makes "it starts at this end" a fact about the data
    // rather than a label somebody chose.
    await map.addLayer(
      mb.SymbolLayer(
        id: _arrowsId,
        sourceId: _sourceId,
        symbolPlacement: mb.SymbolPlacement.LINE,
        // Far enough apart to read as punctuation rather than as a
        // dashed line, close enough that a bend has one on it.
        symbolSpacing: 62,
        iconImage: RoadMapIcons.arrowId,
        iconSize: 0.95,
        // To the MAP, not the viewport: an arrow that stays upright
        // while the map rotates is pointing at the screen rather than
        // down the road.
        iconRotationAlignment: mb.IconRotationAlignment.MAP,
        // Allowed to thin out. Zoomed right out, arrows every sixty
        // pixels along a winding road overlap into a smear, and fewer
        // of them says the same thing.
        iconAllowOverlap: false,
      ),
    );

    // ── WHERE IT STARTS AND WHERE IT ENDS ─────────────────────────
    //
    // Both ends used to be the same white dot, which said "the road
    // is between these two" and nothing about which was which.
    //
    // Coloured by the `type` on each feature, so the start carries the
    // accent and the end is dark. Last of all, so they sit on top of
    // the line they cap.
    await map.addLayer(
      mb.CircleLayer(
        id: _endsId,
        sourceId: _endsSourceId,
        circleRadius: 7,
        circleColorExpression: [
          'match',
          ['get', 'type'],
          'start',
          [
            'rgba',
            (accent.r * 255).round(),
            (accent.g * 255).round(),
            (accent.b * 255).round(),
            1,
          ],
          // Anything else is the end.
          const ['rgba', 11, 11, 11, 1],
        ],
        circleStrokeColorExpression: const ['rgba', 255, 255, 255, 1],
        circleStrokeWidth: 3,
      ),
    );

    // And said in words as well as in colour. A legend nobody has read
    // is not a legend, and two coloured dots are only meaningful to
    // somebody who already knows the rule.
    await map.addLayer(
      mb.SymbolLayer(
        id: _endLabelsId,
        sourceId: _endsSourceId,
        textFieldExpression: const ['get', 'label'],
        textSize: 10.5,
        textOffset: const [0, -1.7],
        textColorExpression: const ['rgba', 11, 11, 11, 1],
        // A halo rather than a plate behind it: the label has to be
        // readable over a field, a town and a wood without putting a
        // white box on the map at every road end.
        textHaloColorExpression: const ['rgba', 255, 255, 255, 1],
        textHaloWidth: 1.6,
        // Never dropped. These two are the whole point of the layer,
        // and a label that vanishes because a place name was already
        // there is worse than a crowded corner.
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
    );

    await _frame();
  }

  /// Points the camera at the whole road.
  Future<void> _frame() async {
    final bounds = RoadBounds.of(_points);

    if (bounds == null || _map == null || !mounted) return;

    final size = MediaQuery.sizeOf(context);

    // Logical pixels, not physical. The zoom maths is in CSS-pixel
    // terms, which is what the map's own 256-pixel tiles are measured
    // in — passing device pixels would frame a road for a screen four
    // times the size of the one it is on.
    final zoom = bounds.zoomFor(
      widthPx: size.width,
      heightPx: size.height * _mapFraction,
    );

    await _map?.flyTo(
      mb.CameraOptions(
        center: mb.Point(
          coordinates: mb.Position(bounds.centre.lng, bounds.centre.lat),
        ),
        zoom: zoom,
      ),
      mb.MapAnimationOptions(duration: 600),
    );
  }

  /// How much of the screen the map gets.
  static const double _mapFraction = 0.46;

  String _lineGeoJson() => jsonEncode({
    'type': 'Feature',
    'properties': const <String, dynamic>{},
    'geometry': {
      'type': 'LineString',
      // [lng, lat]. Done in exactly one place — see RoadPolyline.
      'coordinates': RoadPolyline.toGeoJson(_points),
    },
  });

  /// The two ends, each saying which it is.
  ///
  /// The properties are what the circle colours and the labels read —
  /// see the layers above. Taken from the first and last coordinates
  /// rather than from the start_lat/end_lat columns, so the dot is
  /// always on the line that is actually drawn.
  String _endsGeoJson() => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final end in [
        (point: _points.first, type: 'start', label: 'START'),
        (point: _points.last, type: 'end', label: 'END'),
      ])
        {
          'type': 'Feature',
          'properties': {'type': end.type, 'label': end.label},
          'geometry': {
            'type': 'Point',
            'coordinates': [end.point.lng, end.point.lat],
          },
        },
    ],
  });

  // ── the two buttons ───────────────────────────────────────────────

  Future<void> _toggle(String kind) async {
    if (_busy) return;

    final on = kind == 'drove' ? !_road.iDrove : !_road.iSaved;

    // Asked on the way IN only. Un-ticking a road is not the moment to
    // ask which car it was not driven in, and somebody correcting a
    // mistap wants it gone, not a form.
    var vehicleId = 0;
    var droveOn = '';

    if (kind == 'drove' && on) {
      final answer = await RoadDriveSheet.show(
        context,
        roadTitle: _road.title,
        vehicleId: _road.myVehicleId,
        droveOn: _road.myDroveOn,
      );

      // Dismissed rather than answered. Nothing is recorded — swiping
      // a sheet away is a change of mind, not an empty answer.
      if (answer == null) return;

      vehicleId = answer.vehicleId;
      droveOn = answer.droveOn;
    }

    if (!mounted) return;

    setState(() => _busy = true);

    final result = await RoadsAPI.setAction(
      id: _road.id,
      kind: kind,
      on: on,
      vehicleId: vehicleId,
      droveOn: droveOn,
    );

    if (!mounted) return;

    setState(() {
      _busy = false;

      // The count comes back recalculated from the rows rather than
      // incremented, so it cannot drift. A null means the call failed
      // and nothing moves — the button stays as it was rather than
      // showing a state the server does not agree with.
      if (result == null) return;

      _changed = true;

      // The car and date are read back off the server rather than
      // echoed from what was sent: a server without roads-drives.sql
      // returns them empty, and showing a car it never stored would be
      // a lie that survives until the next reload.
      _road = kind == 'drove'
          ? _road.copyWith(
              iDrove: on,
              droveCount: result.count,
              myVehicleId: on ? result.vehicleId : 0,
              myDroveOn: on ? result.droveOn : '',
            )
          : _road.copyWith(iSaved: on, savedCount: result.count);
    });

    if (kind == 'drove') unawaited(_loadVehicleName());
  }

  /// Hands the road to whatever gives directions on this phone.
  ///
  /// See [RoadNavigation] for why this is a handoff: the driver
  /// already has an app with their settings, their voice and their
  /// traffic, and it is not this one.
  Future<void> _drive() async {
    final url = RoadNavigation.directionsUrl(_points);

    if (url == null) {
      _say('This road has no route to follow yet.');
      return;
    }

    try {
      final opened = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );

      if (!opened && mounted) _say('Could not open a maps app.');
    } catch (e) {
      debugPrint('[Road] could not open directions: $e');

      if (mounted) _say('Could not open a maps app.');
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final size = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F6F6),
        body: Column(
          children: [
            SizedBox(
              height: size.height * _mapFraction,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MapboxConfig.isConfigured
                        ? mb.MapWidget(
                            key: ValueKey('dl-road-${_road.id}'),
                            androidHostingMode: _hosting,
                            styleUri: MapboxConfig.styleUri,
                            onMapCreated: _onMapCreated,
                            onStyleLoadedListener: (_) => _draw(),
                          )
                        : const _NoMap(),
                  ),

                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 8,
                    left: 12,
                    child: _RoundButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.pop(context, _changed),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.primaryColor,
                      ),
                    )
                  : _details(theme),
            ),
          ],
        ),
      ),
    );
  }

  /// "You drove this in August 2019", with as much of it as was said.
  ///
  /// Built from whichever halves exist rather than from a template with
  /// gaps in it: "You drove this in" with nothing after it is worse
  /// than saying nothing.
  String _myDriveLine() {
    final when = _road.droveOnLabel;
    final car = _vehicleName;

    if (car.isNotEmpty && when.isNotEmpty) return 'You drove this in $when, in your $car';
    if (car.isNotEmpty) return 'You drove this in your $car';
    if (when.isNotEmpty) return 'You drove this in $when';

    return '';
  }


  Widget _details(ThemeProvider theme) {
    final facts = [
      _road.lengthLabel,
      _road.region,
      _road.awayLabel,
    ].where((s) => s.isNotEmpty).join('  ·  ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        DlHeading(
          _road.title,
          fontSize: 30,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF0B0B0B),
          height: 1.05,
        ),

        if (facts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            facts,
            style: const TextStyle(
              fontSize: 14.5,
              color: Color(0xFF6B6B6B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        if (_road.summary.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            _road.summary,
            style: const TextStyle(fontSize: 15.5, height: 1.4),
          ),
        ],

        if (_road.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _road.description,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Color(0xFF3A3A3A),
            ),
          ),
        ],

        const SizedBox(height: 22),

        // First, and the full width of the screen. It is the only
        // button here that does something in the world rather than
        // recording something about it.
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _points.length < 2 ? null : _drive,
            icon: const Icon(Icons.navigation_rounded, size: 20),
            label: const Text(
              'Drive this route',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B0B0B),
              disabledBackgroundColor: const Color(0xFFBDBDBD),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        // Said once, under the button, rather than in a dialog after
        // it. Somebody about to drive a road wants to know where it
        // opens before they commit, not after.
        if (_points.length >= 2) ...[
          const SizedBox(height: 8),
          const Text(
            'Opens in your maps app, routed from where you are to the '
            'start and along the road.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8A8A)),
          ),
        ],

        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: _road.iDrove ? "I've driven this" : 'I drove this',
                count: _road.droveCount,
                on: _road.iDrove,
                icon: Icons.check_circle_rounded,
                accent: theme.primaryColor,
                busy: _busy,
                onTap: () => _toggle('drove'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                label: _road.iSaved ? 'Saved' : 'Save',
                count: _road.savedCount,
                on: _road.iSaved,
                icon: Icons.bookmark_rounded,
                accent: theme.primaryColor,
                busy: _busy,
                onTap: () => _toggle('saved'),
              ),
            ),
          ],
        ),

        // Their own drive, read back. Only when they said something:
        // a tick with no car and no date is a complete answer and does
        // not want a line underneath saying so.
        if (_road.iDrove && _myDriveLine().isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                Icons.directions_car_filled_rounded,
                size: 17,
                color: theme.primaryColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _myDriveLine(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A4A4A),
                  ),
                ),
              ),
            ],
          ),
        ],

        // The line is the road; without it this is a page about a place
        // with no idea where it is, and that is worth saying rather
        // than leaving a grey rectangle to be interpreted.
        if (!_loading && _points.length < 2) ...[
          const SizedBox(height: 18),
          const Text(
            'This road has no route recorded yet.',
            style: TextStyle(fontSize: 14, color: Color(0xFF8A8A8A)),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final int count;
  final bool on;
  final bool busy;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.count,
    required this.on,
    required this.busy,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? accent : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: on ? accent : const Color(0xFFE2E2E2),
              width: 1.4,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: on ? Colors.white : const Color(0xFF6B6B6B),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  // The count only once there is one. "Save 0" reads as
                  // a broken label rather than as nobody having yet.
                  count > 0 ? '$label  $count' : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: on ? Colors.white : const Color(0xFF0B0B0B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the map area shows with no Mapbox token.
///
/// Said out loud rather than left as a grey rectangle: with no token
/// the SDK renders an empty grey box and logs nothing useful, which
/// looks like a broken screen rather than missing configuration.
class _NoMap extends StatelessWidget {
  const _NoMap();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1C1C1E),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Map unavailable — no Mapbox token in this build.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 17, color: const Color(0xFF0B0B0B)),
        ),
      ),
    );
  }
}
