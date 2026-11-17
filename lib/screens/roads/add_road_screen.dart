import 'dart:async';
import 'dart:convert';

import 'package:drivelife/api/roads_api.dart';
import 'package:drivelife/config/mapbox_config.dart';
import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/models/road_polyline.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/roads/road_map_icons.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:provider/provider.dart';

/// Adding a road by tapping where it goes.
///
/// ── WHY TAPPING AND NOT TRACING ─────────────────────────────────────
///
/// A finger cannot trace a road accurately on a phone, and it does not
/// have to. The server routes whatever is sent along the actual tarmac
/// — see dl_roads_route() — so the job here is to say WHICH road, not
/// to draw it.
///
/// Which makes the whole interaction about half a dozen taps: one at
/// the start, one at the end, and a few in between at the junctions
/// where the answer would otherwise be ambiguous. The line drawn on
/// this screen is deliberately shown as the rough thing it is.
///
/// ── AND WHY IT IS DELIBERATELY FEW ──────────────────────────────────
///
/// A routing call takes twenty-five points. Far more importantly, each
/// extra point is a chance to pin the route to the wrong side of a
/// dual carriageway. Two points and a junction beat twelve points
/// placed approximately.
class AddRoadScreen extends StatefulWidget {
  const AddRoadScreen({super.key});

  @override
  State<AddRoadScreen> createState() => _AddRoadScreenState();
}

class _AddRoadScreenState extends State<AddRoadScreen> {
  static const String _sourceId = 'dl-new-road';
  static const String _lineId = 'dl-new-road-line';
  static const String _dotsId = 'dl-new-road-dots';
  static const String _arrowsId = 'dl-new-road-arrows';
  static const String _labelsId = 'dl-new-road-labels';

  /// Hybrid Composition, as the other maps use. Hoisted so the ignore
  /// sits on the line the analyser flags.
  // ignore: experimental_member_use
  static const _hosting = mb.AndroidPlatformViewHostingMode.HC;

  /// The server's limit, and a sensible one on its own: more than this
  /// is tracing rather than pointing.
  static const int _maxPoints = 25;

  mb.MapboxMap? _map;

  final List<RoadPoint> _points = [];

  final _titleCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();

  bool _saving = false;
  bool _styleReady = false;

  /// One redraw at a time. The same guard the detail screen needs, for
  /// the same reason: each pass removes its layers before adding them,
  /// so two passes overlapping delete each other's work.
  bool _drawing = false;
  bool _drawAgain = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  // ── the map ───────────────────────────────────────────────────────

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;

    await map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));

    await map.location.updateSettings(
      mb.LocationComponentSettings(enabled: true),
    );

    // Every tap adds a point. Registered on the map itself rather than
    // on a layer, because there is nothing on the map yet to tap.
    map.addInteraction(
      mb.TapInteraction.onMap((context) => _addPoint(context.point)),
    );

    await _centreOnUser();
  }

  Future<void> _centreOnUser() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final permission = await Geolocator.checkPermission();

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }

      final here = await Geolocator.getLastKnownPosition();

      if (here == null || !mounted) return;

      await _map?.setCamera(
        mb.CameraOptions(
          center: mb.Point(
            coordinates: mb.Position(here.longitude, here.latitude),
          ),
          // Close enough to tell one road from the one beside it.
          // Opening on a county would have somebody tapping a motorway
          // thinking it was a lane.
          zoom: 12,
        ),
      );
    } catch (_) {
      // No location is not an error here: the map opens where Mapbox
      // opens it and somebody pans to the road they mean.
    }
  }

  void _addPoint(mb.Point point) {
    if (_points.length >= _maxPoints) {
      _say('That is as many points as a road takes.');
      return;
    }

    final position = point.coordinates;

    final next = RoadPoint(
      position.lat.toDouble(),
      position.lng.toDouble(),
    );

    if (!next.isReal) return;

    setState(() => _points.add(next));

    unawaited(_draw());
  }

  void _undo() {
    if (_points.isEmpty) return;

    setState(_points.removeLast);

    unawaited(_draw());
  }

  /// Turns the road round.
  ///
  /// ── WHY THIS IS WORTH A BUTTON ──────────────────────────────────
  ///
  /// Now that the order of the taps decides which way the road runs,
  /// tapping the two ends in the wrong order is a real mistake with a
  /// real consequence — and without this the only way out of it is to
  /// clear everything and do the whole road again.
  ///
  /// A road also genuinely has a better direction. The Cat and Fiddle
  /// is a different road westbound, and whoever adds it should be able
  /// to say which one they meant in one tap.
  void _reverse() {
    if (_points.length < 2) return;

    setState(() {
      final flipped = _points.reversed.toList();

      _points
        ..clear()
        ..addAll(flipped);
    });

    unawaited(_draw());
  }

  void _clear() {
    if (_points.isEmpty) return;

    setState(_points.clear);

    unawaited(_draw());
  }

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

    if (map == null || !_styleReady || !mounted) return;

    // Read now, used later. Everything below is an await, and a
    // context read after one of them is a read against a widget that
    // may already have left the tree.
    final accent = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).primaryColor;

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    try {
      await RoadMapIcons.register(map, pixelRatio);

      for (final id in const [_lineId, _arrowsId, _dotsId, _labelsId]) {
        if (await map.styleLayerExists(id)) await map.removeStyleLayer(id);
      }

      if (await map.styleSourceExists(_sourceId)) {
        await map.removeStyleSource(_sourceId);
      }

      if (_points.isEmpty) return;

      await map.addSource(mb.GeoJsonSource(id: _sourceId, data: _geojson()));

      // DASHED, deliberately. This line is not the road — it is the
      // straight-line sketch the server will route along the tarmac,
      // and drawing it solid would promise a shape nobody is going to
      // get.
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
          lineWidth: 4,
          lineDasharray: [2, 1.5],
          lineCap: mb.LineCap.ROUND,
          lineJoin: mb.LineJoin.ROUND,
        ),
      );

      // ── WHICH WAY THIS ROAD WILL BE STORED ──────────────────
      //
      // The order of the taps IS the direction of the road: it is what
      // gets routed, what gets stored, and what the arrows on the
      // detail screen will later show.
      //
      // So it has to be visible while it is still being decided.
      // Without this somebody taps the two ends in whichever order
      // they happen to, saves, and finds the road runs the wrong way
      // with no idea why.
      if (_points.length >= 2) {
        await map.addLayer(
          mb.SymbolLayer(
            id: _arrowsId,
            sourceId: _sourceId,
            // Only the line. This source carries the tapped points as
            // well, and line placement on a point feature is not a
            // thing Mapbox has to guess at.
            filter: const ['==', ['geometry-type'], 'LineString'],
            symbolPlacement: mb.SymbolPlacement.LINE,
            symbolSpacing: 62,
            iconImage: RoadMapIcons.arrowId,
            iconSize: 0.95,
            iconRotationAlignment: mb.IconRotationAlignment.MAP,
            iconAllowOverlap: false,
          ),
        );
      }

      await map.addLayer(
        mb.CircleLayer(
          id: _dotsId,
          sourceId: _sourceId,
          filter: const ['==', ['geometry-type'], 'Point'],
          circleRadius: 7,
          // The first tap in the accent, every other one dark. Same
          // rule as the detail screen, so the two read alike.
          circleColorExpression: [
            'case',
            ['==', ['get', 'index'], 0],
            [
              'rgba',
              (accent.r * 255).round(),
              (accent.g * 255).round(),
              (accent.b * 255).round(),
              1,
            ],
            const ['rgba', 11, 11, 11, 1],
          ],
          circleStrokeColorExpression: const ['rgba', 255, 255, 255, 1],
          circleStrokeWidth: 3,
        ),
      );

      await map.addLayer(
        mb.SymbolLayer(
          id: _labelsId,
          sourceId: _sourceId,
          filter: const ['==', ['geometry-type'], 'Point'],
          textFieldExpression: const ['get', 'label'],
          textSize: 10.5,
          textOffset: const [0, -1.7],
          textColorExpression: const ['rgba', 11, 11, 11, 1],
          textHaloColorExpression: const ['rgba', 255, 255, 255, 1],
          textHaloWidth: 1.6,
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
      );
    } catch (e) {
      debugPrint('[AddRoad] could not draw: $e');
    }
  }

  /// The points as dots, and the line through them when there are two.
  ///
  /// Each point carries its own index and a label, which is what the
  /// layers above colour and name by — so the first tap is visibly the
  /// start and the last is visibly the end, while there is still time
  /// to change either.
  String _geojson() => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (var i = 0; i < _points.length; i++)
        {
          'type': 'Feature',
          'properties': {
            'index': i,
            'label': i == 0
                ? 'START'
                : (i == _points.length - 1 && _points.length > 1 ? 'END' : ''),
          },
          'geometry': {
            'type': 'Point',
            // [lng, lat]. The opposite of everywhere else here.
            'coordinates': [_points[i].lng, _points[i].lat],
          },
        },
      if (_points.length >= 2)
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'LineString',
            'coordinates': RoadPolyline.toGeoJson(_points),
          },
        },
    ],
  });

  // ── saving ────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;

    final title = _titleCtrl.text.trim();

    if (title.isEmpty) {
      _say('Give the road a name.');
      return;
    }

    if (_points.length < 2) {
      _say('Tap the start and the end of the road.');
      return;
    }

    setState(() => _saving = true);

    final id = await RoadsAPI.create(
      title: title,
      points: _points,
      summary: _summaryCtrl.text.trim(),
    );

    if (!mounted) return;

    setState(() => _saving = false);

    if (id == null) {
      _say(
        RoadsAPI.lastError.isNotEmpty
            ? RoadsAPI.lastError
            : 'Could not save that road.',
      );
      return;
    }

    // Said plainly, because a road that does not appear in the list
    // afterwards otherwise reads as a save that failed.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sent for checking'),
        content: Text(
          '$title has been submitted. It will appear once somebody has '
          'looked at it — until then you are the only one who can see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );

    if (mounted) Navigator.pop(context, true);
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

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Add a Road',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFAE9159),
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: size.height * 0.44,
            child: Stack(
              children: [
                Positioned.fill(
                  child: MapboxConfig.isConfigured
                      ? mb.MapWidget(
                          key: const ValueKey('dl-add-road-map'),
                          androidHostingMode: _hosting,
                          styleUri: MapboxConfig.styleUri,
                          onMapCreated: _onMapCreated,
                          onStyleLoadedListener: (_) {
                            _styleReady = true;
                            unawaited(_draw());
                          },
                        )
                      : const _NoMap(),
                ),

                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: _Hint(count: _points.length),
                ),

                if (_points.isNotEmpty)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Row(
                      children: [
                        // Only once there is a direction to reverse.
                        if (_points.length >= 2) ...[
                          _MapButton(
                            icon: Icons.swap_horiz_rounded,
                            label: 'Reverse',
                            onTap: _reverse,
                          ),
                          const SizedBox(width: 8),
                        ],
                        _MapButton(
                          icon: Icons.undo_rounded,
                          label: 'Undo',
                          onTap: _undo,
                        ),
                        const SizedBox(width: 8),
                        _MapButton(
                          icon: Icons.clear_rounded,
                          label: 'Clear',
                          onTap: _clear,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                TextField(
                  controller: _titleCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: _decoration(
                    'Name',
                    'Cat and Fiddle, Snake Pass…',
                    theme,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _summaryCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _decoration(
                    'What makes it worth driving?',
                    'Optional',
                    theme,
                  ),
                ),

                const SizedBox(height: 18),

                // ── WHAT HAPPENS TO THE LINE ──────────────────────
                //
                // Worth saying before Save rather than explaining a
                // changed shape afterwards. The dashed line on the map
                // is not what gets stored, and somebody who does not
                // know that will think the save went wrong.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEDED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_fix_high_rounded,
                        size: 19,
                        color: Color(0xFF6B6B6B),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your taps are a sketch. We follow the road '
                          'between them, so the saved line will bend '
                          'where the road bends.',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF4A4A4A),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(
    String label,
    String hint,
    ThemeProvider theme,
  ) => InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E2E2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E2E2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.primaryColor, width: 1.6),
    ),
  );
}

/// Says what to do, and then what has been done.
class _Hint extends StatelessWidget {
  final int count;

  const _Hint({required this.count});

  @override
  Widget build(BuildContext context) {
    final text = switch (count) {
      0 => 'Tap where the road starts',
      1 => 'Now tap where it ends',
      _ =>
        '$count points, running START to END — '
            'add more at junctions if the route looks wrong',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0B0B0B),
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MapButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 17, color: const Color(0xFF0B0B0B)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0B0B0B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
            'A road is drawn on a map, and this build has no Mapbox '
            'token to draw one with.',
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
