import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drivelife/api/cloudflare_images.dart';
import 'package:drivelife/api/roads_api.dart';
import 'package:drivelife/config/mapbox_config.dart';
import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/models/road_polyline.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/media_picker/media_picker_screen.dart';
import 'package:drivelife/screens/roads/road_map_icons.dart';
import 'package:drivelife/screens/roads/road_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
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

  /// Which half of the flow is showing: 1 the map, 2 the name.
  ///
  /// ── WHY THE STATE NEEDS NO STORE ────────────────────────────────
  ///
  /// The points, the two controllers and the chosen photograph are all
  /// fields on this State, and both steps are built by the same build
  /// method. So moving between them changes what is drawn and nothing
  /// else: going back to the map and returning finds the name still
  /// typed and the photograph still chosen.
  int _step = 1;

  /// The map, with everything else out of the way.
  bool _fullScreen = false;

  /// The cover photograph, before it has been uploaded.
  ///
  /// Uploaded at Save rather than at pick, deliberately. The scan in
  /// Add Vehicle taught this one: uploading early leaves an orphaned
  /// image behind every time somebody changes their mind, and nothing
  /// ever deletes it.
  File? _cover;

  /// Shown while the cover is on its way to Cloudflare, which is the
  /// slow half of saving a road.
  bool _uploading = false;

  /// One redraw at a time. The same guard the detail screen needs, for
  /// the same reason: each pass removes its layers before adding them,
  /// so two passes overlapping delete each other's work.
  bool _drawing = false;
  bool _drawAgain = false;

  @override
  void initState() {
    super.initState();

    // After the first frame, so the card lands over a map rather than
    // over the white rectangle that precedes one. Not awaited by
    // anything: a tour that delays the screen is worse than no tour.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showRoadTips(context));
    });
  }

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

  // ── the cover photograph ──────────────────────────────────────────

  Future<void> _pickCover() async {
    final picked = await MediaPickerScreen.open(
      context,
      maxSelection: 1,
      confirmLabel: 'Use photo',
      title: 'Cover photo',
      // A road's cover is a photograph. There is nowhere for a clip to
      // play in a list row, and the upload path writes Cloudflare
      // Images.
      allowVideo: false,
    );

    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() => _cover = picked.first.file);
  }

  /// The cover, as a Cloudflare id, or null.
  ///
  /// A failure here does NOT stop the road being saved. The photograph
  /// is the nicest part of a road and the line is the point of it, and
  /// losing somebody's work because an upload timed out would be the
  /// wrong trade.
  Future<String> _uploadCover() async {
    final file = _cover;

    if (file == null) return '';

    setState(() => _uploading = true);

    try {
      // Shrunk first. A road cover is shown at list-row size and as a
      // banner, and a modern phone's original is several megabytes of
      // upload for a picture nothing will ever draw that large.
      final small = await FlutterImageCompress.compressWithFile(
        file.path,
        minWidth: 1600,
        minHeight: 1600,
        quality: 85,
      );

      final id = await CloudflareImages.uploadAndGetId(
        bytes: small ?? await file.readAsBytes(),
        fileName: 'road_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );

      return id ?? '';
    } catch (e) {
      debugPrint('[AddRoad] cover upload failed: $e');
      return '';
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

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

    final cover = await _uploadCover();

    if (!mounted) return;

    // Said, and then carried on. See _uploadCover: a road without its
    // photograph is still a road.
    if (_cover != null && cover.isEmpty) {
      _say('The photo could not be uploaded, so the road was saved without it.');
    }

    final id = await RoadsAPI.create(
      title: title,
      points: _points,
      summary: _summaryCtrl.text.trim(),
      coverImage: cover,
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

  /// How long the drawn line is, following it point to point.
  ///
  /// The straight distance between the ends would be the wrong number
  /// on any road worth adding, which is the whole premise of the
  /// feature.
  double get _miles {
    var total = 0.0;

    for (var i = 1; i < _points.length; i++) {
      total += _points[i - 1].milesTo(_points[i]);
    }

    return total;
  }

  bool get _canContinue => _points.length >= 2;

  // ── the screen ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    // The form panel takes the whole screen while a keyboard is up.
    // See the note on the panel below: a map strip is worth having
    // right up until somebody is typing, and then it is worth nothing
    // at all.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      // Back has three meanings here and only the last of them leaves.
      canPop: !_fullScreen && _step == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        if (_fullScreen) {
          setState(() => _fullScreen = false);
        } else if (_step == 2) {
          setState(() => _step = 1);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F6F6),
        appBar: _fullScreen ? null : _bar(theme),
        body: Stack(
          children: [
            // ── ALWAYS FIRST, ALWAYS PRESENT ──────────────────────
            //
            // The map stays at the same place in the tree in every
            // state this screen has. Moving it, or building it only
            // on step one, would dispose the platform view and take
            // the drawn line and the camera with it — so going back a
            // step, or leaving full screen, would hand somebody an
            // empty map and no way to get their road back.
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

            if (_fullScreen) ..._fullScreenChrome(theme),

            if (!_fullScreen && _step == 1) ..._drawChrome(theme),

            if (!_fullScreen && _step == 2)
              Positioned(
                // A strip of the road stays visible while naming it,
                // because "what am I naming" is a fair question — and
                // it goes the moment a keyboard needs the room.
                top: typing ? 0 : 150,
                left: 0,
                right: 0,
                bottom: 0,
                child: _detailsPanel(theme, typing),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _bar(ThemeProvider theme) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
        onPressed: () {
          if (_step == 2) {
            setState(() => _step = 1);
            return;
          }

          Navigator.pop(context);
        },
      ),
      centerTitle: true,
      title: Text(
        _step == 1 ? 'Draw the road' : 'Name it',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        if (_step == 1)
          IconButton(
            tooltip: 'Tips',
            icon: const Icon(Icons.help_outline_rounded, color: Colors.black),
            onPressed: () => showRoadTips(context, force: true),
          )
        else if (_saving)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              children: [
                if (_uploading) ...[
                  const Text(
                    'Uploading photo',
                    style: TextStyle(
                      color: Color(0xFF6B6B6B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFAE9159),
                  ),
                ),
              ],
            ),
          )
        else
          TextButton(
            onPressed: _save,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: Row(
          children: [
            Expanded(child: Container(height: 3, color: theme.primaryColor)),
            Expanded(
              child: Container(
                height: 3,
                color: _step == 2
                    ? theme.primaryColor
                    : const Color(0xFFE2E2E2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Step one: the map, and the three things that can be done to it.
  List<Widget> _drawChrome(ThemeProvider theme) {
    return [
      Positioned(
        left: 12,
        right: 12,
        top: 12,
        child: _Hint(count: _points.length),
      ),

      Positioned(
        right: 12,
        top: 64,
        child: _MapButton(
          icon: Icons.open_in_full_rounded,
          label: 'Full screen',
          onTap: () => setState(() => _fullScreen = true),
        ),
      ),

      if (_points.isNotEmpty)
        Positioned(
          right: 12,
          bottom: 104,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_points.length >= 2) ...[
                _MapButton(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Reverse',
                  onTap: _reverse,
                ),
                const SizedBox(height: 8),
              ],
              _MapButton(
                icon: Icons.undo_rounded,
                label: 'Undo',
                onTap: _undo,
              ),
              const SizedBox(height: 8),
              _MapButton(
                icon: Icons.clear_rounded,
                label: 'Clear',
                onTap: _clear,
              ),
            ],
          ),
        ),

      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: _BottomBar(
          accent: theme.primaryColor,
          points: _points.length,
          miles: _miles,
          enabled: _canContinue,
          onNext: () {
            FocusScope.of(context).unfocus();
            setState(() => _step = 2);
          },
        ),
      ),
    ];
  }

  /// Nothing but the map and a way back out of it.
  List<Widget> _fullScreenChrome(ThemeProvider theme) {
    return [
      Positioned(
        left: 12,
        right: 12,
        top: MediaQuery.paddingOf(context).top + 10,
        child: Row(
          children: [
            Expanded(child: _Hint(count: _points.length)),
            const SizedBox(width: 8),
            _MapButton(
              icon: Icons.close_fullscreen_rounded,
              label: 'Done',
              onTap: () => setState(() => _fullScreen = false),
            ),
          ],
        ),
      ),

      if (_points.isNotEmpty)
        Positioned(
          right: 12,
          bottom: MediaQuery.paddingOf(context).bottom + 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_points.length >= 2) ...[
                _MapButton(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Reverse',
                  onTap: _reverse,
                ),
                const SizedBox(height: 8),
              ],
              _MapButton(
                icon: Icons.undo_rounded,
                label: 'Undo',
                onTap: _undo,
              ),
              const SizedBox(height: 8),
              _MapButton(
                icon: Icons.clear_rounded,
                label: 'Clear',
                onTap: _clear,
              ),
            ],
          ),
        ),
    ];
  }

  /// Step two: the whole screen, for the two fields and the photograph.
  ///
  /// ── WHY THEY GET A STEP OF THEIR OWN ──────────────────────────────
  ///
  /// They were under the map, in whatever was left of the screen after
  /// a 44% map and a keyboard. The name of the road is the single most
  /// important thing anybody types here and it was the least visible
  /// thing on the page.
  ///
  /// Nothing is stored anywhere special to survive the move between
  /// steps: the controllers, the points and the chosen photograph are
  /// all fields on this one State, so going back to the map and
  /// returning finds everything exactly as it was left. The only thing
  /// that would lose it is leaving the screen.
  Widget _detailsPanel(ThemeProvider theme, bool typing) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: typing
            ? null
            : const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 18, spreadRadius: 2),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          // What they are naming, in one line. The map behind this
          // panel answers "where"; this answers "how much".
          Row(
            children: [
              Icon(Icons.route_rounded, size: 18, color: theme.primaryColor),
              const SizedBox(width: 8),
              Text(
                _miles >= 10
                    ? '${_miles.round()} miles drawn'
                    : '${_miles.toStringAsFixed(1)} miles drawn',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0B0B0B),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_points.length} points',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8A8A8A),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _step = 1),
                child: Text(
                  'Edit route',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: theme.primaryColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          TextField(
            controller: _titleCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
            decoration: _decoration(
              'Name',
              'Cat and Fiddle, Snake Pass…',
              theme,
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _summaryCtrl,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration(
              'What makes it worth driving?',
              'Optional. The bends, the view, the pub at the end.',
              theme,
            ),
          ),

          const SizedBox(height: 18),

          _CoverPicker(
            file: _cover,
            accent: theme.primaryColor,
            onPick: _pickCover,
            onClear: () => setState(() => _cover = null),
          ),

          const SizedBox(height: 18),

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
                    'Your taps are a sketch. We follow the road between '
                    'them, so the saved line will bend where the road '
                    'bends.',
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

/// The strip across the foot of step one.
class _BottomBar extends StatelessWidget {
  final Color accent;
  final int points;
  final double miles;
  final bool enabled;
  final VoidCallback onNext;

  const _BottomBar({
    required this.accent,
    required this.points,
    required this.miles,
    required this.enabled,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x14000000), blurRadius: 16, spreadRadius: 2),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  points == 0
                      ? 'Nothing drawn yet'
                      : (miles >= 10
                            ? '${miles.round()} miles'
                            : '${miles.toStringAsFixed(1)} miles'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B0B0B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  points == 1
                      ? '1 point — tap the other end'
                      : '$points points',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF8A8A8A),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: enabled ? onNext : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                disabledBackgroundColor: const Color(0xFFD9D9D9),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 26),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Next',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The cover photograph, or an invitation to add one.
class _CoverPicker extends StatelessWidget {
  final File? file;
  final Color accent;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _CoverPicker({
    required this.file,
    required this.accent,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 84,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE2E2E2)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.add_photo_alternate_outlined, size: 24, color: accent),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Add a cover photo',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B0B0B),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Optional. It is what the road looks like in a list.',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8A8A)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          // 16:9, which is the shape a list row and a banner both
          // crop to — so what is framed here is what gets shown.
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.file(
              file!,
              fit: BoxFit.cover,
              // A file that was readable a moment ago, so this is
              // close to impossible — and a crash on a form would
              // lose the road behind it.
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFFEDEDED)),
            ),
          ),

          Positioned(
            right: 8,
            top: 8,
            child: Row(
              children: [
                _CoverButton(
                  icon: Icons.swap_horiz_rounded,
                  onTap: onPick,
                ),
                const SizedBox(width: 8),
                _CoverButton(icon: Icons.close_rounded, onTap: onClear),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CoverButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 17, color: Colors.white),
        ),
      ),
    );
  }
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
