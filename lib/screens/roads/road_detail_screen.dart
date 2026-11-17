import 'dart:convert';

import 'package:drivelife/api/roads_api.dart';
import 'package:drivelife/config/mapbox_config.dart';
import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/models/road_polyline.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:provider/provider.dart';

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
  static const String _endsSourceId = 'dl-road-ends';
  static const String _endsId = 'dl-road-ends-dots';

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

    await _draw();
  }

  // ── the map ───────────────────────────────────────────────────────

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;

    await map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));

    await _draw();
  }

  /// Puts the line on the style.
  ///
  /// Called from both the map being created and the shape arriving,
  /// because either can happen first and neither can draw alone. Both
  /// paths are safe to run twice — see the removals below.
  Future<void> _draw() async {
    final map = _map;

    if (map == null || _points.length < 2 || !mounted) return;

    // Read now, used later. Every line below this is an await, and a
    // provider read after one of them is a read against a context that
    // may no longer be in the tree.
    final accent = Provider.of<ThemeProvider>(context, listen: false)
        .primaryColor;

    // StyleLoaded also fires for a style that is ALREADY carrying our
    // source, and adding a source that exists throws. Layers before the
    // source: a source cannot be removed while a layer references it.
    for (final id in const [_casingId, _lineId, _endsId]) {
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

    await map.addLayer(
      mb.CircleLayer(
        id: _endsId,
        sourceId: _endsSourceId,
        circleRadius: 6,
        circleColorExpression: const ['rgba', 255, 255, 255, 1],
        circleStrokeColorExpression: const ['rgba', 11, 11, 11, 1],
        circleStrokeWidth: 3,
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

  String _endsGeoJson() => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final point in [_points.first, _points.last])
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'Point',
            'coordinates': [point.lng, point.lat],
          },
        },
    ],
  });

  // ── the two buttons ───────────────────────────────────────────────

  Future<void> _toggle(String kind) async {
    if (_busy) return;

    setState(() => _busy = true);

    final on = kind == 'drove' ? !_road.iDrove : !_road.iSaved;

    final count = await RoadsAPI.setAction(
      id: _road.id,
      kind: kind,
      on: on,
    );

    if (!mounted) return;

    setState(() {
      _busy = false;

      // The count comes back recalculated from the rows rather than
      // incremented, so it cannot drift. A null means the call failed
      // and nothing moves — the button stays as it was rather than
      // showing a state the server does not agree with.
      if (count == null) return;

      _changed = true;

      _road = kind == 'drove'
          ? _road.copyWith(iDrove: on, droveCount: count)
          : _road.copyWith(iSaved: on, savedCount: count);
    });
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
