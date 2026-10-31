import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/models/user_model.dart' show LastLocation;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/api/garage_api.dart';
import 'package:drivelife/api/garage_reminders_service.dart';
import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:drivelife/routes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The "Your week" tab.
///
/// Three things and nothing else, which is the point of it — this is a
/// standing summary, not a feed. Posts live in Latest and Following.
///
///   1. Your current vehicle, the most-liked one
///   2. Its next reminder, if there is one
///   3. The next five events near you
///
/// Built as a sliver because the whole of PostsScreen is one
/// CustomScrollView: the header, the selector and whichever tab is on
/// show are all slivers in the same scroll, which is what stopped the
/// chrome from being rebuilt every time somebody changed tab.
class YourWeekPanel extends StatefulWidget {
  /// The signed-in person, for their garage and their name.
  final int userId;
  final String? firstName;

  /// Takes the user to the Events section of Home.
  final VoidCallback? onSeeAllEvents;

  /// Where the user is, from their profile's last_location.
  ///
  /// Used to work out how far each event is, since the events endpoint
  /// returns coordinates but no distance. Null when the profile has
  /// never recorded a position — the events still list, without the
  /// mileage and in the server's own order.
  final LastLocation? from;

  const YourWeekPanel({
    super.key,
    required this.userId,
    this.firstName,
    this.onSeeAllEvents,
    this.from,
  });

  @override
  State<YourWeekPanel> createState() => YourWeekPanelState();
}

class YourWeekPanelState extends State<YourWeekPanel> {
  static const Color _cardBlack = Color(0xFF111113);
  static const Color _cardInner = Color(0xFF232326);

  Map<String, dynamic>? _vehicle;
  Map<String, dynamic>? _reminder;

  /// Whether [_vehicle] is a dream car rather than one they own.
  bool _isDream = false;
  List<Map<String, dynamic>> _events = const [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reload everything. Called by the screen's pull-to-refresh.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    // Together rather than one after another. The garage and the events
    // have nothing to do with each other, and run in series this panel
    // waits for the sum of two round trips before it draws anything.
    final results = await Future.wait([
      _loadVehicleAndReminder(),
      _loadEvents(),
    ]);

    if (!mounted) return;

    setState(() {
      final garage =
          results[0]
              as ({
                Map<String, dynamic>? vehicle,
                Map<String, dynamic>? reminder,
                bool isDream,
              });

      _vehicle = garage.vehicle;
      _reminder = garage.reminder;
      _isDream = garage.isDream;
      _events = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  /// The vehicle the card is about, and its next reminder.
  ///
  /// One method because the reminder lookup needs the vehicle's id, so
  /// they cannot run in parallel with each other even though they can
  /// run in parallel with the events.
  Future<
    ({
      Map<String, dynamic>? vehicle,
      Map<String, dynamic>? reminder,
      bool isDream,
    })
  >
  _loadVehicleAndReminder() async {
    try {
      final garage = await GarageAPI.getUserGarage(widget.userId) ?? const [];

      final all = garage
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList();

      // Owned first, dreamed of second.
      //
      // A car somebody actually has is the one with reminders against
      // it and the one they came to look at. A dream car is worth
      // showing when there is nothing else — it is still their garage —
      // but it must never displace a real one, and the card has to say
      // which it is or the reminder row would be promising to remind
      // somebody about a car they do not own.
      final current = all.where(_isCurrent).toList();
      final dreams = all.where(_isDreamCar).toList();

      final shelf = current.isNotEmpty ? current : dreams;

      if (shelf.isEmpty) {
        return (vehicle: null, reminder: null, isDream: false);
      }

      // Most liked within whichever shelf won. The shelf narrows it and
      // the likes break the tie, so somebody with four cars gets the one
      // the app has most to say about rather than whichever the
      // database happened to return first.
      shelf.sort((a, b) => _likes(b).compareTo(_likes(a)));
      final vehicle = shelf.first;

      final isDream = current.isEmpty;

      return (
        vehicle: vehicle,
        // A dream car has nothing to remind anybody about. Asking would
        // be a wasted request on every load for the people most likely
        // to have an empty garage.
        reminder: isDream ? null : await _nextReminder(vehicle),
        isDream: isDream,
      );
    } catch (e) {
      debugPrint('[YourWeek] garage failed: $e');
      return (vehicle: null, reminder: null, isDream: false);
    }
  }

  /// A car they want, not one they have. primary_car == '2'.
  static bool _isDreamCar(Map<String, dynamic> vehicle) =>
      vehicle['primary_car']?.toString() == '2';

  /// Currently owned, and not a dream car.
  ///
  /// Mirrors _shelfFor in garage_list_screen.dart: primary_car == '2' is
  /// the dream-car flag and is checked first, because a dream car has no
  /// owned_until and would otherwise read as current.
  static bool _isCurrent(Map<String, dynamic> vehicle) {
    if (vehicle['primary_car']?.toString() == '2') return false;

    final until = vehicle['owned_until']?.toString().trim().toLowerCase();
    return until == null || until.isEmpty || until == 'present';
  }

  static int _likes(Map<String, dynamic> vehicle) {
    final raw = vehicle['likes'];
    return raw is int ? raw : int.tryParse('$raw') ?? 0;
  }

  /// The soonest reminder still in the future.
  ///
  /// Past ones are dropped rather than shown in red: this card is a
  /// glance at what is coming, and "upcoming reminder" followed by a
  /// date from last March is worse than showing nothing.
  Future<Map<String, dynamic>?> _nextReminder(
    Map<String, dynamic> vehicle,
  ) async {
    final id = vehicle['id']?.toString();
    if (id == null || id.isEmpty) return null;

    try {
      final reminders = await ReminderApiService.fetchReminders(id);
      final now = DateTime.now();

      final upcoming =
          reminders
              .map((r) => (reminder: r, due: _dueDate(r)))
              .where((r) => r.due != null && r.due!.isAfter(now))
              .toList()
            ..sort((a, b) => a.due!.compareTo(b.due!));

      return upcoming.isEmpty ? null : upcoming.first.reminder;
    } catch (e) {
      debugPrint('[YourWeek] reminders failed: $e');
      return null;
    }
  }

  static DateTime? _dueDate(Map<String, dynamic> reminder) {
    for (final key in ['due_date', 'date', 'reminder_date', 'next_due']) {
      final raw = reminder[key]?.toString();
      if (raw == null || raw.isEmpty) continue;

      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// The next five events, nearest first.
  ///
  /// getEvents already defaults to the user's country off last_location,
  /// so this asks for 'near-me' and lets the server apply the radius and
  /// the ordering it already has for that case.
  Future<List<Map<String, dynamic>>> _loadEvents() async {
    try {
      final response = await EventsAPI.getEvents(
        page: 1,
        limit: 5,
        location: 'near-me',
        dateFilter: 'upcoming',
      );

      final data = (response?['data'] as List<dynamic>?) ?? const [];

      final events = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // Nearest first, for real now.
      //
      // The server returns no distance on an event, which is why this
      // used to be a sort that could never fire. It DOES return the
      // event's latitude and longitude though, and the user's own
      // position is on their profile — so the distance is something to
      // work out rather than something to wait to be told.
      final from = widget.from;

      if (from != null) {
        for (final event in events) {
          final miles = _milesFrom(from, event);
          if (miles != null) event['distance'] = miles;
        }

        events.sort((a, b) => _distance(a).compareTo(_distance(b)));
      }

      return events.take(5).toList();
    } catch (e) {
      debugPrint('[YourWeek] events failed: $e');
      return const [];
    }
  }

  /// How far an event is, in miles, or null if it has no coordinates.
  ///
  /// Haversine — great-circle distance on a sphere. Flat-earth
  /// Pythagoras on latitude and longitude is a common shortcut and it is
  /// wrong by a factor that grows with latitude, because a degree of
  /// longitude is only as wide as a degree of latitude at the equator.
  /// At UK latitudes it is about 0.6 as wide, so the shortcut overstates
  /// east-west distance by roughly 60%.
  static double? _milesFrom(LastLocation from, Map<String, dynamic> event) {
    final lat = _toDouble(event['latitude']);
    final lng = _toDouble(event['longitude']);

    if (lat == null || lng == null) return null;
    if (lat == 0 && lng == 0) return null; // Null Island, i.e. unset.

    const earthRadiusMiles = 3958.8;

    double radians(double deg) => deg * math.pi / 180;

    final dLat = radians(lat - from.latitude);
    final dLng = radians(lng - from.longitude);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(radians(from.latitude)) *
            math.cos(radians(lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    return earthRadiusMiles * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Test seams for the two pieces of arithmetic on this screen.
  ///
  /// A wrong haversine does not throw — it returns a plausible number
  /// and quietly puts the events in the wrong order, which is the kind
  /// of bug that only shows up when somebody drives to the wrong one.
  @visibleForTesting
  static double? debugMilesFrom(LastLocation from, Map<String, dynamic> e) =>
      _milesFrom(from, e);

  @visibleForTesting
  static String? debugDistanceLabel(Map<String, dynamic> e) =>
      _distanceLabel(e);

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static double _distance(Map<String, dynamic> event) {
    final raw = event['distance'];
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw') ?? double.infinity;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return SliverToBoxAdapter(
      child: Padding(
        // Generous at the bottom, for two reasons that compound.
        //
        // The floating bottom bar sits over this, so the last card ended
        // underneath it. And the other tabs' slivers are offstage while
        // this one shows, which means the whole scroll extent is just
        // the header, the pills and this panel — short content made the
        // page unscrollable altogether, so the floating header had no
        // gesture to respond to either.
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          160 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _greeting(theme),
            const SizedBox(height: 14),

            if (_loading)
              _skeleton()
            else ...[
              if (_vehicle != null) _garageCard(theme) else _emptyGarage(theme),
              const SizedBox(height: 28),
              _eventsSection(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _greeting(ThemeProvider theme) {
    final name = widget.firstName?.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          // Condensed and in capitals. The old -0.6 tracking went with
          // the face change: it was pulling Roboto's wide caps
          // together, and DlType opens caps back up on its own.
          child: DlHeading(
            name == null || name.isEmpty ? 'Hey' : 'Hey, $name',
            fontSize: 28,
            color: theme.textColor,
          ),
        ),
        Text(
          _today(),
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: theme.subtextColor,
          ),
        ),
      ],
    );
  }

  static String _today() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
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

    final now = DateTime.now();
    return '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';
  }

  /// The dark card: vehicle on top, reminder underneath.
  ///
  /// One card rather than two, because the reminder is ABOUT the vehicle
  /// above it. Split into separate cards they read as two unrelated
  /// facts, and the reminder loses the only context that explains which
  /// car it belongs to.
  Widget _garageCard(ThemeProvider theme) {
    final vehicle = _vehicle!;
    final garageId = vehicle['id']?.toString();

    return Material(
      color: _cardBlack,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: garageId == null
                ? null
                : () => Navigator.pushNamed(
                    context,
                    AppRoutes.vehicleDetail,
                    arguments: {'garageId': garageId},
                  ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _vehicleThumb(vehicle),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          // Says which shelf this came from. Without it
                          // the card would present a car somebody only
                          // wishes they owned as the one in their
                          // garage.
                          _isDream ? 'DREAM GARAGE' : 'YOUR GARAGE',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: theme.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // Body face, not the condensed heading one.
                        //
                        // A vehicle name is DATA — "Ford Mustang Mach 1
                        // Auto 5.0L Petrol" — not a title the screen is
                        // announcing. Condensed capitals made it read as
                        // a banner and cost it the mixed case that tells
                        // the trim apart from the model. "YOUR GARAGE"
                        // above it is the heading here; this is what the
                        // heading is about.
                        Text(
                          _vehicleName(vehicle),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            // 15.5 from 17, and w900 from w800.
                            //
                            // The hierarchy in this card is carried by
                            // weight, not size: at 15.5 the name is a
                            // point above the reminder line under it
                            // and three above the YOUR GARAGE label, so
                            // what makes it the thing you read first is
                            // that it is the heaviest, not the biggest.
                            // At 17 it was both, which made the card
                            // feel top-heavy.
                            //
                            // w900 is a real weight in DM Sans, not a
                            // request that falls back — the family ships
                            // 100 through 900. Asking for a weight a
                            // family does not have gets you the nearest
                            // one it does, which here would have been
                            // w700 and LIGHTER than before.
                            fontSize: 15.5,
                            height: 1.25,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.1,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _likesPill(theme, _likes(vehicle)),
                ],
              ),
            ),
          ),

          // Only when there is one. An empty reminder strip would be a
          // row of furniture explaining that nothing is due.
          if (_reminder != null) _reminderStrip(theme, garageId),
        ],
      ),
    );
  }

  /// The card when there is no vehicle at all.
  ///
  /// Not a hidden section. An empty garage is the state the app most
  /// wants to change, and a card that simply is not there says nothing
  /// about what the screen could do once it is filled — so this says
  /// what is missing, what it unlocks, and offers the one tap that
  /// fixes it.
  ///
  /// The points are on the button rather than in the body copy because
  /// that is where somebody decides, and "+500 points" is the reason
  /// that survives being skim-read.
  Widget _emptyGarage(ThemeProvider theme) {
    return Material(
      color: _cardBlack,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'YOUR GARAGE',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: theme.primaryColor,
              ),
            ),
            const SizedBox(height: 6),

            // Condensed capitals here, where the vehicle name is not:
            // this line is the screen announcing something, not a name
            // out of the database.
            const DlHeading(
              'Your garage is empty',
              fontSize: 26,
              color: Colors.white,
            ),
            const SizedBox(height: 8),

            Text(
              "Add the car you drive, or the one you're dreaming of, to "
              'unlock reminders, groups and points.',
              style: TextStyle(
                fontSize: 14.5,
                height: 1.4,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: Material(
                color: _cardInner,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _addVehicle,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF3A3A3E)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Add a vehicle',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '+500 points',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: theme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addVehicle() async {
    final added = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(builder: (_) => const AddVehicleScreen()),
    );

    // Only on a result. AddVehicleScreen returns null when it is backed
    // out of, and reloading then would be a request for nothing.
    if (added != null && mounted) await _load();
  }

  Widget _vehicleThumb(Map<String, dynamic> vehicle) {
    final url = vehicle['cover_photo']?.toString();

    if (url == null || url.isEmpty) {
      return Container(
        width: 86,
        height: 64,
        color: _cardInner,
        child: const Icon(
          Icons.directions_car_outlined,
          color: Colors.white24,
          size: 26,
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      width: 86,
      height: 64,
      fit: BoxFit.cover,
      placeholder: (_, _) =>
          Container(width: 86, height: 64, color: _cardInner),
      errorWidget: (_, _, _) =>
          Container(width: 86, height: 64, color: _cardInner),
    );
  }

  static String _vehicleName(Map<String, dynamic> vehicle) {
    final parts = [
      vehicle['make'],
      vehicle['model'],
      vehicle['variant'],
    ].map((p) => p?.toString().trim()).where((p) => p != null && p.isNotEmpty);

    final name = parts.join(' ');
    return name.isEmpty ? 'Your vehicle' : name;
  }

  Widget _likesPill(ThemeProvider theme, int likes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _cardInner,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite, size: 15, color: theme.primaryColor),
          const SizedBox(width: 6),
          Text(
            _formatCount(likes),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatCount(int n) {
    if (n < 1000) return '$n';

    final s = n.toString();
    final buffer = StringBuffer();

    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }

    return buffer.toString();
  }

  Widget _reminderStrip(ThemeProvider theme, String? garageId) {
    final due = _dueDate(_reminder!);

    return InkWell(
      onTap: garageId == null
          ? null
          : () => Navigator.pushNamed(
              context,
              AppRoutes.vehicleDetail,
              arguments: {'garageId': garageId},
            ),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF2A2A2E))),
        ),
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: [
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  text: 'Upcoming reminder: ',
                  style: TextStyle(fontSize: 14.5, color: theme.subtextColor),
                  children: [
                    TextSpan(
                      text: due == null ? 'soon' : _formatDate(due),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _eventsSection(ThemeProvider theme) {
    if (_events.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DlHeading(
                'Events happening soon',
                fontSize: 22,
                color: theme.textColor,
              ),
            ),
            if (widget.onSeeAllEvents != null)
              GestureDetector(
                onTap: widget.onSeeAllEvents,
                child: Text(
                  'All events',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.primaryColor,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),

        // No fixed height, because every fixed height here was wrong.
        //
        // A horizontal ListView hands each card exactly the height of
        // its parent: too large left dead space inside the card's
        // border, too small overflowed. Computing it from font sizes
        // and a line-height factor got closer and was still out by a
        // few pixels, because the real line height comes from the
        // font's own metrics and is not something to predict from the
        // outside.
        //
        // IntrinsicHeight asks the cards instead. The row becomes as
        // tall as the tallest of them, which is right by construction
        // at any text scale and leaves the cards aligned with each
        // other. It costs an extra layout pass over five items, which
        // is nothing — it would be the wrong trade for a long list, and
        // this list is five.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _events.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  _eventCard(theme, _events[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const double _imageHeight = 140;

  Widget _eventCard(ThemeProvider theme, Map<String, dynamic> event) {
    final start = _parseEventDate(event['start_date']);

    return SizedBox(
      width: 232,
      child: Material(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.eventDetail,
            arguments: {'event': event},
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    _eventImage(event),
                    if (start != null)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _whenLabel(start),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111113),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${event['title'] ?? 'Untitled event'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: theme.textColor,
                        ),
                      ),
                      const SizedBox(height: 3),

                      // The location gets its own line and is allowed to
                      // be cut off. "Caffeine & Machine, Ettington" was
                      // sharing one line with the date and the mileage,
                      // and since it comes first it ate both — the two
                      // facts that decide whether you can go.
                      Text(
                        _location(event),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: theme.subtextColor,
                        ),
                      ),
                      const SizedBox(height: 5),

                      // Date and distance, on a line of their own so
                      // nothing can push them off it.
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 12.5,
                            color: theme.primaryColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            start == null ? 'Date TBA' : _dateLabel(start),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: theme.textColor,
                            ),
                          ),
                          if (_distanceLabel(event) != null) ...[
                            const SizedBox(width: 10),
                            Icon(
                              Icons.place_outlined,
                              size: 13,
                              color: theme.primaryColor,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _distanceLabel(event)!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: theme.textColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _eventImage(Map<String, dynamic> event) {
    final url = event['thumbnail']?.toString();

    if (url == null || url.isEmpty) {
      return Container(height: _imageHeight, width: 232, color: _cardInner);
    }

    return CachedNetworkImage(
      imageUrl: url,
      height: _imageHeight,
      width: 232,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(
        height: _imageHeight,
        width: 232,
        color: const Color(0xFFEDEDED),
      ),
      errorWidget: (_, _, _) => Container(
        height: _imageHeight,
        width: 232,
        color: const Color(0xFFEDEDED),
      ),
    );
  }

  /// "Sat 9am" for this week, a date beyond it.
  ///
  /// A weekday is only useful while it is unambiguous. Past six days
  /// "Sat" could be either of two Saturdays, and the date is the thing
  /// that actually tells somebody when to turn up.
  static String _whenLabel(DateTime start) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final now = DateTime.now();
    final daysAway = start
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;

    final hour = start.hour % 12 == 0 ? 12 : start.hour % 12;
    final suffix = start.hour < 12 ? 'am' : 'pm';
    final time = start.minute == 0
        ? '$hour$suffix'
        : '$hour:${start.minute.toString().padLeft(2, '0')}$suffix';

    if (daysAway < 7) return '${days[start.weekday - 1]} $time';

    return '${start.day}/${start.month} $time';
  }

  /// An event's start, whatever shape the API sent it in.
  ///
  /// NOT DateTime.tryParse, which is what this used and why every card
  /// read "Date TBA". The events endpoint sends "01/26/2026 18:00" —
  /// slash-separated, space before the time, and MONTH FIRST. tryParse
  /// wants ISO-8601 and returns null for all of it.
  ///
  /// Month first is the part worth being careful about: read as
  /// day-first, 01/26 throws (there is no month 26) but 05/06 silently
  /// becomes the wrong day. See DateHelpers.formatEventDate, which is
  /// where this format is already handled for the events screen.
  static DateTime? _parseEventDate(dynamic raw) {
    final text = raw?.toString().trim();
    if (text == null || text.isEmpty) return null;

    // ISO first, so this keeps working if the API is ever fixed.
    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;

    final parts = text.split(' ');
    final date = parts[0].split('/');
    if (date.length != 3) return null;

    final month = int.tryParse(date[0]);
    final day = int.tryParse(date[1]);
    final year = int.tryParse(date[2]);

    if (month == null || day == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    var hour = 0;
    var minute = 0;

    if (parts.length > 1) {
      final time = parts[1].split(':');
      hour = int.tryParse(time[0]) ?? 0;
      if (time.length > 1) minute = int.tryParse(time[1]) ?? 0;
    }

    return DateTime(year, month, day, hour, minute);
  }

  @visibleForTesting
  static DateTime? debugParseEventDate(dynamic raw) => _parseEventDate(raw);

  static String _location(Map<String, dynamic> event) {
    final location = event['location']?.toString().trim();
    return location == null || location.isEmpty ? 'Location TBA' : location;
  }

  /// "Sat 1 Nov", with the year only when it is not this one.
  ///
  /// Separate from the chip over the photograph, which carries the day
  /// and the time. This is the calendar date, which is what somebody
  /// checks against their own week.
  static String _dateLabel(DateTime d) {
    const months = [
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

    final year = d.year == DateTime.now().year ? '' : ' ${d.year}';
    return '${d.day} ${months[d.month - 1]}$year';
  }

  /// "14 mi", or null when there is nothing to say.
  ///
  /// Under ten miles keeps one decimal: the difference between 2 and 7
  /// miles decides whether you go, and both round to "a few". Above
  /// that the rounding stops mattering.
  static String? _distanceLabel(Map<String, dynamic> event) {
    final raw = event['distance'];
    if (raw is! num) return null;

    final miles = raw.toDouble();
    if (miles.isNaN || miles.isInfinite) return null;

    return miles < 10
        ? '${miles.toStringAsFixed(1)} mi'
        : '${miles.round()} mi';
  }

  /// Grey bars in the shape of what is coming.
  ///
  /// The shape matters more than the shimmer: a spinner in the middle of
  /// the page tells you to wait, where blocks the size of the card tell
  /// you what you are waiting for and stop the layout jumping when it
  /// lands.
  Widget _skeleton() {
    Widget bar(double height, double width, [double radius = 10]) => Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar(96, double.infinity, 16),
        const SizedBox(height: 28),
        bar(22, 210),
        const SizedBox(height: 14),
        Row(
          children: [
            bar(200, 232, 14),
            const SizedBox(width: 12),
            Expanded(child: bar(200, double.infinity, 14)),
          ],
        ),
      ],
    );
  }
}
