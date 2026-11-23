import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drivelife/api/cloudflare_images.dart';
import 'package:drivelife/api/roads_api.dart';
import 'package:drivelife/config/mapbox_config.dart';
import 'package:drivelife/models/driving_road.dart';
import 'package:drivelife/models/google_maps_link.dart';
import 'package:drivelife/models/road_polyline.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/media_picker/media_picker_screen.dart';
import 'package:drivelife/screens/roads/road_map_icons.dart';
import 'package:drivelife/screens/roads/road_tips.dart';
import 'package:drivelife/services/place_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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
  /// The road being changed, or null to add one.
  ///
  /// ── WHY EDITING IS THIS SCREEN AND NOT ANOTHER ──────────────────
  ///
  /// Everything an edit needs is already here: a map that draws a
  /// line, the controls that change it, the fields, the photograph
  /// and the import. A second screen would be the same eight hundred
  /// lines with a different verb on the button, and the first bug
  /// fixed in one of them would live on in the other.
  ///
  /// What differs is the starting state and where Save sends it.
  final DrivingRoad? road;

  const AddRoadScreen({super.key, this.road});

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

  /// The road, in order, each with whatever we can call it.
  ///
  /// ── WHY NOT JUST A LIST OF COORDINATES ──────────────────────────
  ///
  /// Because the list of them is now on screen, and "54.386688,
  /// -0.953580" is not a thing anybody can check their route against.
  /// A stop picked from the search knows its own name; one tapped on
  /// the map does not, and says so.
  final List<_Stop> _stops = [];

  /// Never reused, so a name that comes back late cannot land on a
  /// stop added after the one it was looked up for.
  int _nextStopKey = 1;

  /// Just the coordinates, which is all the drawing and saving want.
  ///
  /// UNMODIFIABLE on purpose. It used to be the real list, so every
  /// `_points.add(...)` worked; now it is rebuilt on each read, and a
  /// mutation missed in the change above would silently do nothing at
  /// all. Throwing is the only version of that anybody would notice.
  List<RoadPoint> get _points =>
      List.unmodifiable([for (final stop in _stops) stop.point]);

  final _titleCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();

  /// The pasted link.
  ///
  /// ── WHY IT IS A FIELD AND NOT A LOCAL ───────────────────────────
  ///
  /// What is typed in the place search, and what came back.
  ///
  /// A State field for the same reason [_linkCtrl] is one: it outlives
  /// any single build, and a controller disposed while a route is
  /// still animating takes the app with it.
  final TextEditingController _findCtrl = TextEditingController();

  List<PlaceHit> _hits = const [];
  bool _finding = false;

  /// Whether the search box is showing, as opposed to the + that opens
  /// it.
  ///
  /// Open on an empty road, because finding the start is the first
  /// thing anybody does. Closed once there is a road, so the list of
  /// stops gets the room instead — and reopened by the + beside it.
  bool _searchOpen = true;

  final FocusNode _findFocus = FocusNode();

  /// Whether the middle stops are showing.
  ///
  /// Collapsed by default. The ends are what somebody checks; a
  /// twenty-stop road listed in full would be the whole map.
  bool _stopsExpanded = false;

  /// Cancelled and restarted on every keystroke, so typing a town name
  /// is one request rather than eight. See PlaceSearch.debounce.
  Timer? _findDebounce;

  /// It was made inside _importLink() and disposed the moment
  /// showDialog returned, which crashed the app with "a ChangeNotifier
  /// was used after being disposed".
  ///
  /// The dialog's route is still ANIMATING OUT when its future
  /// completes. The TextField is still in the tree for those few
  /// hundred milliseconds, and the exit transition rebuilds it — so it
  /// calls addListener on a controller that has already been thrown
  /// away.
  ///
  /// Owned by the State and disposed with the rest, which is the only
  /// lifetime that outlives the animation.
  final _linkCtrl = TextEditingController();

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

  /// True while a pasted link is being read.
  bool _importing = false;

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

  bool get _isEdit => widget.road != null;

  @override
  void initState() {
    super.initState();

    final road = widget.road;

    if (road != null) {
      _titleCtrl.text = road.title;
      _summaryCtrl.text = road.summary;

      // ── THE DRAWN POINTS, NOT THE LINE ──────────────────────────
      //
      // road.polyline is the SNAPPED line: hundreds of points, far
      // past the twenty-five a routing call takes. Loading that as
      // the editable route would make every edit unsendable.
      //
      // waypoints is the handful somebody actually placed. Empty for
      // a road added before they were kept — see canEditRoute, which
      // is what stops this screen pretending otherwise.
      // ── THE NAMES COME BACK WITH THE POINTS ─────────────────
      //
      // The polyline keeps coordinates and nothing else, so this used
      // to reopen every road as a list of dropped pins however
      // carefully it had been drawn. waypoint_names is the column that
      // fixes that — padded server-side to the points it was stored
      // with, so entry 3 is point 3 whatever either end does.
      //
      // Empty for a road saved before the column existed, which reads
      // exactly as it did then.
      final drawn = RoadPolyline.decode(road.waypoints);
      final names = road.waypointNames(drawn.length);

      for (var i = 0; i < drawn.length; i++) {
        final full = i < names.length ? names[i] : '';
        final comma = full.indexOf(', ');

        _stops.add(
          _Stop(
            drawn[i],
            key: _nextStopKey++,
            // Stored as one string and shown as two lines, split the
            // same way PlaceHit splits it.
            name: comma > 0 ? full.substring(0, comma) : full,
            detail: comma > 0 ? full.substring(comma + 2) : '',
          ),
        );
      }

      // Straight to the details for a road whose route cannot be
      // edited. The map step would be a screen with nothing to do on
      // it.
      if (!road.canEditRoute) _step = 2;
    }

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
    _linkCtrl.dispose();

    // The timer goes first. It calls setState on a State that is about
    // to stop existing, and a controller disposed out from under a
    // pending search is the same crash by a different route.
    _findDebounce?.cancel();
    _findCtrl.dispose();
    _findFocus.dispose();

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
    final position = point.coordinates;

    _addStop(
      _Stop(RoadPoint(position.lat.toDouble(), position.lng.toDouble())),
    );
  }

  /// Puts a stop on the end of the road, from wherever it came.
  ///
  /// One door for the map and the search, so the cap, the sanity check
  /// and the redraw cannot drift apart between the two.
  void _addStop(_Stop stop) {
    if (_stops.length >= _maxPoints) {
      _say('That is as many points as a road takes.');
      return;
    }

    if (!stop.point.isReal) return;

    final keyed = _Stop(
      stop.point,
      key: _nextStopKey++,
      name: stop.name,
      detail: stop.detail,
    );

    setState(() => _stops.add(keyed));

    unawaited(_draw());

    // Only for a point nobody has named. A search result arrives
    // already knowing what it is, and asking again would be a request
    // to replace a good answer with a near-identical one.
    if (stop.name.trim().isEmpty) unawaited(_nameStop(keyed));
  }

  /// Asks what is at a tapped point, and fills the name in when it
  /// lands.
  ///
  /// Nothing waits on this. The point is already on the map and in the
  /// list reading "Dropped pin"; a name arriving a moment later
  /// improves the row, and a name that never arrives leaves it exactly
  /// as it was.
  Future<void> _nameStop(_Stop stop) async {
    final country = mounted
        ? Provider.of<UserProvider>(
            context,
            listen: false,
          ).user?.lastLocation?.country
        : null;

    final hit = await PlaceSearch.describe(stop.point, country: country);

    if (hit == null || !mounted) return;

    // By key. See _Stop.key: the list may have been reversed, cleared
    // or had something removed from the middle while this was out.
    final index = _stops.indexWhere((s) => s.key == stop.key);

    if (index < 0) return;

    // And it may have been named by something else in the meantime —
    // an import, or a save and reopen. Last writer does not win here;
    // the one that was sure of itself does.
    if (_stops[index].name.trim().isNotEmpty) return;

    setState(() {
      _stops[index] = _stops[index].named(hit.name, hit.detail);
    });
  }

  void _undo() {
    if (_stops.isEmpty) return;

    setState(() {
      _stops.removeLast();
      _settleFold();
    });

    unawaited(_draw());
  }

  /// Takes one stop out of the middle.
  ///
  /// By index rather than by value: two taps on the same spot are two
  /// stops, and removing "the one equal to this" would take the first
  /// of them whichever was tapped.
  void _removeStop(int index) {
    if (index < 0 || index >= _stops.length) return;

    setState(() {
      _stops.removeAt(index);
      _settleFold();
    });

    unawaited(_draw());
  }

  /// Keeps the fold honest about what is left.
  ///
  /// Expanded is a state about stops that may no longer be there. A
  /// road cut back to two would otherwise come back expanded the next
  /// time it grew past three, showing a list somebody had not asked to
  /// see again.
  void _settleFold() {
    if (_stops.length <= 3) _stopsExpanded = false;
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
    if (_stops.length < 2) return;

    setState(() {
      final flipped = _stops.reversed.toList();

      _stops
        ..clear()
        ..addAll(flipped);
    });

    unawaited(_draw());
  }

  void _clear() {
    if (_stops.isEmpty) return;

    setState(() {
      _stops.clear();
      _settleFold();

      // Nothing left to list, so the box that fills the list comes
      // back rather than leaving a + over an empty map.
      _searchOpen = true;
    });

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

  // ── finding the place first ───────────────────────────────────────

  /// Looks for a place, a third of a second after the typing stops.
  void _onFindChanged(String value) {
    _findDebounce?.cancel();

    if (value.trim().length < 3) {
      setState(() {
        _hits = const [];
        _finding = false;
      });

      return;
    }

    setState(() => _finding = true);

    _findDebounce = Timer(PlaceSearch.debounce, () => _find(value));
  }

  Future<void> _find(String value) async {
    // Biased towards where the map is looking, so "Newport" finds the
    // one up the road before the one in Rhode Island.
    final camera = await _map?.getCameraState();

    final near = camera == null
        ? null
        : RoadPoint(
            camera.center.coordinates.lat.toDouble(),
            camera.center.coordinates.lng.toDouble(),
          );

    // Held to the country the app last placed this person in. See
    // PlaceSearch.find: an unknown country searches the world rather
    // than nothing.
    final country = mounted
        ? Provider.of<UserProvider>(
            context,
            listen: false,
          ).user?.lastLocation?.country
        : null;

    final hits = await PlaceSearch.find(value, near: near, country: country);

    // Typed on while this was in flight. The later request owns the
    // list, and showing these would overwrite it with older answers.
    if (!mounted || _findCtrl.text.trim() != value.trim()) return;

    setState(() {
      _hits = hits;
      _finding = false;
    });
  }

  /// Adds a result to the road, and moves the map to it.
  ///
  /// ── WHY IT PLACES A POINT AND NOT JUST THE CAMERA ───────────────
  ///
  /// Because searching for somewhere and then having to find it again
  /// on the map to tap it is the same work twice. A geocoded point is
  /// the middle of a town rather than the exact kerb — so it is a
  /// STOP, not a promise, and the list below says what it is and lets
  /// it be removed.
  ///
  /// Still flies there, because the next point is usually near this
  /// one and because a point added off-screen is a point nobody can
  /// check.
  Future<void> _addHit(PlaceHit hit) async {
    FocusScope.of(context).unfocus();

    _addStop(_Stop(hit.point, name: hit.name, detail: hit.detail));

    setState(() {
      _hits = const [];
      _findCtrl.clear();

      // Closed again, so the list it just added to is what is on
      // screen rather than the box that added to it.
      _searchOpen = false;
    });

    await _map?.flyTo(
      mb.CameraOptions(
        center: mb.Point(
          coordinates: mb.Position(hit.point.lng, hit.point.lat),
        ),
        // The same zoom the map opens at on a known location: close
        // enough to tell one road from the one beside it.
        zoom: 12,
      ),
      mb.MapAnimationOptions(duration: 700),
    );
  }

  void _clearFind() {
    _findDebounce?.cancel();

    setState(() {
      _findCtrl.clear();
      _hits = const [];
      _finding = false;

      // The box closes with the text when there is a road to show
      // instead. On an empty one it stays, because there is nothing
      // else for that space to hold.
      _searchOpen = _stops.isEmpty;
    });
  }

  void _openFind() {
    setState(() => _searchOpen = true);

    // After the frame that builds the field, or there is nothing yet
    // to give the focus to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocus.requestFocus();
    });
  }

  // ── importing a route somebody already has ────────────────────────

  /// Asks for a Google Maps link and turns it into points.
  ///
  /// ── WHY THIS IS WORTH HAVING ────────────────────────────────────
  ///
  /// Somebody who already planned the road in Google Maps has done
  /// this work once. Asking them to tap it out again on a phone-sized
  /// map is asking them to do it worse — a finger is less precise than
  /// the thing that produced the link.
  Future<void> _importLink() async {
    // Cleared rather than recreated. See [_linkCtrl] for why it
    // outlives this method.
    _linkCtrl.clear();

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Paste a Google Maps link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Open your route in Google Maps, Share, copy the link, and '
              'paste it here.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _linkCtrl,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'https://maps.app.goo.gl/…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _linkCtrl.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (url == null || url.trim().isEmpty || !mounted) return;

    setState(() => _importing = true);

    final read = await _pointsFromLink(url.trim());
    final points = read.points;

    if (!mounted) return;

    setState(() => _importing = false);

    if (points.length < 2) {
      _say(
        GoogleMapsLink.looksLikeMaps(url)
            ? 'That link has no route in it — share directions rather than '
                  'a place.'
            : 'That does not look like a Google Maps link.',
      );

      return;
    }

    // Replaces rather than appends. An import is "this is the road",
    // not "add these to what I was drawing", and silently mixing the
    // two would produce a line through both.
    setState(() {
      _stops
        ..clear()
        ..addAll(
          points
              .take(_maxPoints)
              .map((point) => _Stop(point, key: _nextStopKey++)),
        );
    });

    unawaited(_draw());
    await _frameDrawn();

    if (!mounted) return;

    // A stop the link wrote as a name and gave no coordinate for is
    // simply absent from the list — which is how a route came back
    // missing both of its ends and looked, on the map, like a route.
    // Say the number out loud so it is noticed here rather than after
    // the road is published.
    final missed = read.stops - points.length;

    _say(
      switch (0) {
        _ when points.length > _maxPoints =>
          'Imported the first $_maxPoints points of ${points.length}.',
        _ when missed > 0 =>
          'Imported ${points.length} of ${read.stops} stops. '
              '${missed == 1 ? 'One was a named place' : '$missed were '
                  'named places'} with no coordinates in the link — '
              'tap to add ${missed == 1 ? 'it' : 'them'}.',
        _ =>
          'Imported ${points.length} points. Check the route and adjust '
              'if you need to.',
      },
    );
  }

  /// The points in a link, following it first if it is a short one.
  ///
  /// A maps.app.goo.gl link carries nothing until it has been
  /// resolved — it is an identifier, not a route. Following it is one
  /// request and the only way to read it.
  Future<({List<RoadPoint> points, int stops})> _pointsFromLink(
    String url,
  ) async {
    if (!GoogleMapsLink.looksShortened(url)) {
      return GoogleMapsLink.read(url);
    }

    try {
      // Redirects are NOT followed automatically here on purpose: the
      // whole point is to read the Location header rather than the
      // page it leads to.
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false;

      final response = await http.Client()
          .send(request)
          .timeout(const Duration(seconds: 12));

      final location = response.headers['location'] ?? '';

      return location.isEmpty
          ? (points: const <RoadPoint>[], stops: 0)
          : GoogleMapsLink.read(location);
    } catch (e) {
      debugPrint('[AddRoad] could not follow $url: $e');
      return (points: const <RoadPoint>[], stops: 0);
    }
  }

  /// Waits for the line to be on screen before framing it.
  Future<void> _frameDrawn() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));

    if (!mounted || _points.length < 2) return;

    final bounds = RoadBounds.of(_points);

    if (bounds == null) return;

    final size = MediaQuery.sizeOf(context);

    await _map?.flyTo(
      mb.CameraOptions(
        center: mb.Point(
          coordinates: mb.Position(bounds.centre.lng, bounds.centre.lat),
        ),
        zoom: bounds.zoomFor(widthPx: size.width, heightPx: size.height),
      ),
      mb.MapAnimationOptions(duration: 600),
    );
  }

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

    if (_isEdit) {
      await _saveEdit(title, cover);
      return;
    }

    final id = await RoadsAPI.create(
      title: title,
      points: _points,
      pointNames: _pointNames,
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

  /// Sends the changes, and says what the server made of them.
  Future<void> _saveEdit(String title, String cover) async {
    final road = widget.road!;

    final updated = await RoadsAPI.update(
      id: road.id,
      title: title,
      summary: _summaryCtrl.text.trim(),
      // Only when it is a photograph they just chose. An empty string
      // would CLEAR the one already on the road, and somebody editing
      // a title did not ask for that.
      coverImage: cover.isEmpty ? null : cover,
      // Likewise: sending points re-routes the whole geometry, so a
      // road whose route cannot be edited must not send any.
      points: road.canEditRoute ? _points : null,
      // Only alongside the points, for the same reason: the names mean
      // nothing against a route they did not come with.
      pointNames: road.canEditRoute ? _pointNames : null,
    );

    if (!mounted) return;

    setState(() => _saving = false);

    if (updated == null) {
      _say(
        RoadsAPI.lastError.isNotEmpty
            ? RoadsAPI.lastError
            : 'Could not save those changes.',
      );

      return;
    }

    // Only worth a dialog when something happened that is not
    // obvious. A saved edit that stays live needs no ceremony.
    if (updated.isPending && road.isPublished) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Back for checking'),
          content: Text(
            '${updated.title} has changed enough to be looked at again. '
            'It stays visible to you until then.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } else {
      _say('Saved.');
    }

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

  /// One name per point, in the same order, for saving.
  ///
  /// The two halves joined back into the one string the column holds —
  /// "Helmsley, North Yorkshire" — because that is how it was read out
  /// of the geocoder and splitting it again on the way back in is the
  /// job of whoever draws the row.
  ///
  /// An unnamed point is an empty string rather than a gap, so entry 3
  /// is point 3 however many of them have no name.
  List<String> get _pointNames => [
    for (final stop in _stops)
      stop.name.trim().isEmpty
          ? ''
          : (stop.detail.trim().isEmpty
                ? stop.name.trim()
                : '${stop.name.trim()}, ${stop.detail.trim()}'),
  ];

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
        _step == 1
            ? (_isEdit ? 'Edit the route' : 'Draw the road')
            : (_isEdit ? 'Edit details' : 'Name it'),
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
      // ── THE TOP, AND WHY IT NO LONGER GROWS ─────────────────────
      //
      // It used to be hint + buttons, and the hint got longer with
      // every point: at five it was three lines of prose, which pushed
      // everything under it down the map and left the row beside it
      // ragged.
      //
      // The list of stops replaces it. That is the same information
      // said once, in a shape that does not grow — the two ends are
      // always shown and everything between them is one collapsed row
      // until somebody asks for it.
      Positioned(
        left: 12,
        right: 12,
        top: 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Open on an empty road, because finding the start is the
            // first thing anybody does. A + afterwards, so the list
            // gets the room instead.
            if (_searchOpen) _findBox(theme) else _addPointButton(theme),

            // The results hang under it, over the map. Nothing when
            // there is nothing to show.
            if (_hits.isNotEmpty) ...[
              const SizedBox(height: 6),
              _findResults(theme),
            ],

            const SizedBox(height: 8),

            // One or the other, never both: an empty road has nothing
            // to list, and a road with stops does not need telling
            // what tapping does.
            if (_stops.isEmpty)
              _Hint(count: 0)
            else
              _stopList(theme),

            const SizedBox(height: 8),

            _MapButton(
              icon: _importing
                  ? Icons.hourglass_top_rounded
                  : Icons.link_rounded,
              label: _importing ? 'Reading…' : 'Import Google Maps link',
              fill: true,
              onTap: _importing ? () {} : _importLink,
            ),
          ],
        ),
      ),

      // ── THE MAP'S OWN CONTROLS, ALL IN ONE PLACE ────────────────
      //
      // Full screen moved down here from the top. It belongs with
      // Reverse, Undo and Clear — all four act on the map rather than
      // on the road's details — and the top had run out of room for
      // it once the list of stops arrived.
      //
      // Always drawn, unlike the other three: there is nothing to
      // reverse or undo on an empty road, but looking at more of the
      // map is exactly what somebody with an empty road wants.
      Positioned(
        right: 12,
        bottom: 104,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _MapButton(
              icon: Icons.open_in_full_rounded,
              label: 'Full screen',
              onTap: () => setState(() => _fullScreen = true),
            ),
            if (_stops.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (_stops.length >= 2) ...[
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

  /// Where to look. Moves the map; places nothing.
  Widget _findBox(ThemeProvider theme) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 6),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 18,
              color: const Color(0xFF0B0B0B).withValues(alpha: 0.55),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _findCtrl,
                focusNode: _findFocus,
                onChanged: _onFindChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  _findDebounce?.cancel();
                  _find(value);
                },
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0B0B0B),
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: _stops.isEmpty
                      ? 'Find where the road starts'
                      : 'Add another point',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF0B0B0B).withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
            if (_finding)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFAE9159),
                  ),
                ),
              )
            else if (_findCtrl.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: const Color(0xFF0B0B0B),
                visualDensity: VisualDensity.compact,
                onPressed: _clearFind,
              ),
          ],
        ),
      ),
    );
  }

  /// The + that brings the search box back.
  ///
  /// Takes the search box's place rather than sitting beside it: two
  /// ways to start the same search, on one line, is one too many.
  Widget _addPointButton(ThemeProvider theme) {
    return _MapButton(
      icon: Icons.add_rounded,
      label: 'Add a point',
      fill: true,
      onTap: _openFind,
    );
  }

  /// The road so far, as a list of places.
  ///
  /// ── WHY THE MIDDLE IS FOLDED AWAY ───────────────────────────────
  ///
  /// Because this sits over the map, and the map is the thing being
  /// worked on. The two ends are what somebody checks — did it start
  /// where I meant, does it finish where I meant — and a twenty-stop
  /// road listed in full would cover the road itself.
  ///
  /// One row says how many are hidden and opens them. Nothing is
  /// hidden below four stops, because folding one row away to save one
  /// row's height is a tap for nothing.
  Widget _stopList(ThemeProvider theme) {
    final last = _stops.length - 1;

    // Three or fewer fit without folding: first, middle, last is the
    // same height as first, "1 more", last.
    final folded = _stops.length > 3 && !_stopsExpanded;

    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stopRow(theme, 0),

          if (folded)
            _moreRow(theme, _stops.length - 2, open: true)
          else ...[
            for (var i = 1; i < last; i++) ...[
              const Divider(height: 1, indent: 36, color: Color(0xFFEDEDED)),
              _stopRow(theme, i),
            ],

            // The way back. Without it, expanding is one-way and the
            // list somebody opened stays open over the map for the
            // rest of the road.
            if (_stops.length > 3) _moreRow(theme, 0, open: false),
          ],

          if (last > 0) ...[
            const Divider(height: 1, indent: 36, color: Color(0xFFEDEDED)),
            _stopRow(theme, last),
          ],
        ],
      ),
    );
  }

  /// "3 more points" and the tap that shows them, or the way back.
  Widget _moreRow(ThemeProvider theme, int hidden, {required bool open}) {
    return InkWell(
      onTap: () => setState(() => _stopsExpanded = open),
      child: Container(
        color: const Color(0xFFF4F4F4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Icon(
              open
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 18,
              color: theme.primaryColor,
            ),
            const SizedBox(width: 6),
            Text(
              !open
                  ? 'Show less'
                  : hidden == 1
                  ? '1 more point'
                  : '$hidden more points',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: theme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One stop: where it is in the road, what it is called, and the way
  /// to take it off.
  Widget _stopRow(ThemeProvider theme, int index) {
    final stop = _stops[index];
    final isStart = index == 0;
    final isEnd = index == _stops.length - 1 && _stops.length > 1;

    final marker = isStart
        ? 'A'
        : isEnd
        ? 'B'
        : '${index + 1}';

    return InkWell(
      // Tapping a stop shows it, which is the only way to check one
      // that is not at either end without reading its coordinates.
      onTap: () => _lookAt(stop.point),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isStart || isEnd
                    ? theme.primaryColor
                    : const Color(0xFFD8D8D8),
                shape: BoxShape.circle,
              ),
              child: Text(
                marker,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isStart || isEnd
                      ? Colors.white
                      : const Color(0xFF4A4A4A),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stop.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0B0B0B),
                    ),
                  ),
                  if (stop.detail.isNotEmpty)
                    Text(
                      stop.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF6B6B6B),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              color: const Color(0xFF8A8A8A),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 28),
              padding: EdgeInsets.zero,
              tooltip: 'Remove',
              onPressed: () => _removeStop(index),
            ),
          ],
        ),
      ),
    );
  }

  /// Moves the map to a stop without changing the road.
  Future<void> _lookAt(RoadPoint point) async {
    await _map?.flyTo(
      mb.CameraOptions(
        center: mb.Point(coordinates: mb.Position(point.lng, point.lat)),
      ),
      mb.MapAnimationOptions(duration: 500),
    );
  }

  /// What the search found, over the map.
  ///
  /// Capped by the request rather than here — see PlaceSearch, which
  /// asks for five. A list long enough to scroll would be covering the
  /// thing somebody is trying to look at.
  Widget _findResults(ThemeProvider theme) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _hits.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 12, color: Color(0xFFEDEDED)),
            InkWell(
              onTap: () => _addHit(_hits[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: theme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _hits[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0B0B0B),
                            ),
                          ),
                          if (_hits[i].detail.isNotEmpty)
                            Text(
                              _hits[i].detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B6B6B),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
    final canEditRoute = !_isEdit || widget.road!.canEditRoute;

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
              if (canEditRoute)
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  canEditRoute
                      ? Icons.auto_fix_high_rounded
                      : Icons.lock_outline_rounded,
                  size: 19,
                  color: const Color(0xFF6B6B6B),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    // Said plainly rather than offering an edit that
                    // cannot work. A road added before its drawn
                    // points were kept has only the snapped line left,
                    // which is hundreds of points and far too many to
                    // send back.
                    canEditRoute
                        ? 'Your taps are a sketch. We follow the road '
                              'between them, so the saved line will bend '
                              'where the road bends.'
                        : 'This road was added before its drawn points '
                              'were kept, so its route cannot be changed. '
                              'The name, description and photo can.',
                    style: const TextStyle(
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
/// One point on the road, and what to call it.
///
/// The label is empty for a point tapped on the map — a coordinate is
/// not a name, and inventing one from a reverse lookup would be a
/// request per tap for a string nobody asked for. The list shows those
/// as "Dropped pin" and the ones from the search by their own name.
class _Stop {
  /// This stop, as opposed to one that happens to be equal to it.
  ///
  /// ── WHY A KEY AND NOT AN INDEX ──────────────────────────────────
  ///
  /// A name is looked up after the point is placed, and by the time it
  /// comes back the list may have been reversed, cleared, or had
  /// something removed from the middle. An index captured at the start
  /// names whatever has since moved into that slot, which is a wrong
  /// name on a real place — and two taps on the same spot are two
  /// stops, so the coordinates cannot tell them apart either.
  final int key;

  final RoadPoint point;

  /// "Helmsley". Empty until something names it, which for a tapped
  /// point is a lookup that may never come back.
  final String name;

  /// "North Yorkshire, England", or empty.
  final String detail;

  const _Stop(
    this.point, {
    this.key = 0,
    this.name = '',
    this.detail = '',
  });

  _Stop named(String name, String detail) =>
      _Stop(point, key: key, name: name, detail: detail);

  /// What the list calls it.
  ///
  /// A tapped point has no name and is not given one: a reverse lookup
  /// per tap is a request for a string nobody asked for, and "Unnamed
  /// Road, York" is not more useful than knowing you put it there.
  String get title => name.trim().isEmpty ? 'Dropped pin' : name.trim();
}

class _Hint extends StatelessWidget {
  final int count;

  const _Hint({required this.count});

  @override
  Widget build(BuildContext context) {
    // ── ONE LINE, WHATEVER THE COUNT ────────────────────────────────
    //
    // This used to grow: at three points it became three lines of
    // prose about junctions, which pushed everything under it down the
    // map and left the row beside it ragged against a one-line pill.
    //
    // The list of stops says what the long version said, in a shape
    // that does not change height — so this is back to being a prompt,
    // and a prompt is one line.
    final text = switch (count) {
      0 => 'Tap the map, or search for the start',
      1 => 'Now tap where it ends',
      _ => '$count points, START to END',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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

  /// Take the whole width the parent offers, centre the label in it and
  /// let it ellipsise, rather than shrink-wrapping the text.
  ///
  /// For the pair under the hint, which share a row half and half: the
  /// label has to live inside its half instead of setting the width.
  ///
  /// NOT for the free-standing buttons stacked over the map. [Flexible]
  /// needs a bounded width and a column pinned to the edge gives it
  /// none, so turning this on there throws at layout.
  final bool fill;

  const _MapButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0B0B0B),
      ),
    );

    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisAlignment:
                fill ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: const Color(0xFF0B0B0B)),
              const SizedBox(width: 6),
              if (fill) Flexible(child: text) else text,
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
