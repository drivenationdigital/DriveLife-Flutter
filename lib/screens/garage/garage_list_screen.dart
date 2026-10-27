import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/garage_api.dart';
import 'package:drivelife/models/user_model.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/widgets/garage/vehicle_card.dart';
import 'package:drivelife/widgets/nav/chrome_visibility.dart';
import 'package:drivelife/widgets/nav/dl_haptics.dart';
import 'package:drivelife/widgets/nav/floating_chrome_header.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Which set of vehicles is showing.
enum _Shelf { current, past, dream }

extension on _Shelf {
  String get label => switch (this) {
    _Shelf.current => 'Current',
    _Shelf.past => 'Past',
    _Shelf.dream => 'Dream',
  };

  /// What to say when this shelf is empty — each is empty for a different
  /// reason, and "No vehicles" three times over says nothing about any of
  /// them.
  String get emptyLine => switch (this) {
    _Shelf.current => 'Nothing in the garage yet',
    _Shelf.past => 'No past vehicles',
    _Shelf.dream => 'No dream vehicles',
  };

  String get emptyDetail => switch (this) {
    _Shelf.current => 'Add what you drive and it shows up here.',
    _Shelf.past => 'Cars you used to own will collect here.',
    _Shelf.dream => 'The ones you are working towards.',
  };
}

/// The garage: what you drive, what you drove, and what you are after.
///
/// A bottom-bar destination as well as a pushed route. As a destination it
/// carries the shell's header inside its own scroll view, the way Home,
/// Places, Tracks and Groups do — above the scroll view, hiding the header
/// would mean shrinking the box it sits in, which resizes the viewport on
/// every frame of the animation.
class GarageListScreen extends StatefulWidget {
  /// True when this is a bottom-nav destination rather than a pushed screen.
  ///
  /// Embedded it has no app bar of its own: the shell above already supplies
  /// the logo and the actions, and its back arrow would pop the whole shell
  /// rather than this screen — which looks like the app closing.
  final bool embedded;

  /// Told which way the user is scrolling, so the shell can take the bottom
  /// bar away and bring it back.
  final ChromeVisibility? chrome;

  /// The shell's header, drawn inside this screen's scroll view.
  final Widget? header;

  /// How tall [header] is. A sliver header declares its extent up front.
  final double headerHeight;

  const GarageListScreen({
    super.key,
    this.embedded = false,
    this.chrome,
    this.header,
    this.headerHeight = 0,
  });

  @override
  State<GarageListScreen> createState() => _GarageListScreenState();
}

class _GarageListScreenState extends State<GarageListScreen>
    with TickerProviderStateMixin {
  bool _loadingGarage = true;
  bool _garageLoaded = false;
  User? _userProfile;

  final Map<_Shelf, List<dynamic>> _shelves = {
    _Shelf.current: [],
    _Shelf.past: [],
    _Shelf.dream: [],
  };

  _Shelf _shelf = _Shelf.current;

  /// My Garage / Leaderboard.
  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<dynamic> _board = [];
  bool _loadingBoard = false;
  bool _boardLoaded = false;
  String _period = 'all';
  String _region = 'worldwide';

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!mounted) return;
      setState(() {});
      // Loaded when the tab is first opened rather than at startup: most
      // visits to the garage never leave the first tab.
      if (_tabs.index == 1 && !_boardLoaded) _loadBoard();
    });
    attachTabHaptics(_tabs);
    _loadUserProfile().then((_) => _loadGarage(false));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (!mounted) return;
    setState(() => _userProfile = user);
  }

  Future<void> _loadGarage(bool? refresh) async {
    if ((_garageLoaded || _userProfile == null) && refresh != true) return;

    setState(() {
      _loadingGarage = true;
      _garageLoaded = true; // prevents double calls
    });

    final garage = await GarageAPI.getUserGarage(_userProfile!.id);

    if (!mounted) return;

    final sorted = {
      _Shelf.current: <dynamic>[],
      _Shelf.past: <dynamic>[],
      _Shelf.dream: <dynamic>[],
    };

    for (final vehicle in garage ?? const []) {
      sorted[_shelfFor(vehicle)]!.add(vehicle);
    }

    setState(() {
      _shelves
        ..[_Shelf.current] = sorted[_Shelf.current]!
        ..[_Shelf.past] = sorted[_Shelf.past]!
        ..[_Shelf.dream] = sorted[_Shelf.dream]!;
      _loadingGarage = false;
    });
  }

  /// Which shelf a vehicle belongs on.
  ///
  /// primary_car == '2' is the flag for a dream car, which is checked first:
  /// a dream car has no owned_until and would otherwise read as current.
  static _Shelf _shelfFor(dynamic vehicle) {
    if (vehicle['primary_car']?.toString() == '2') return _Shelf.dream;

    final until = vehicle['owned_until']?.toString().trim().toLowerCase();
    if (until == null || until.isEmpty || until == 'present') {
      return _Shelf.current;
    }

    return _Shelf.past;
  }

  // ── layout ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    final scroller = RefreshIndicator(
      onRefresh: () => _tabs.index == 0 ? _loadGarage(true) : _loadBoard(),
      color: theme.primaryColor,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (widget.header != null) _floatingChrome(),
          SliverToBoxAdapter(child: _tabBar(theme)),
          ..._tabs.index == 0
              ? _garageSlivers(theme)
              : _leaderboardSlivers(theme),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.embedded || widget.header != null
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              centerTitle: true,
              title: Image.asset('assets/logo-dark.png', height: 18),
            ),
      // Every scroll reports to the shell through this one listener, which
      // is what takes the bottom bar away and brings it back.
      body: widget.chrome == null
          ? scroller
          : NotificationListener<ScrollNotification>(
              onNotification: widget.chrome!.handle,
              child: scroller,
            ),
    );
  }

  /// The shell's header, floating: gone as you scroll down the garage, back
  /// the moment you scroll up.
  Widget _floatingChrome() {
    return SliverPersistentHeader(
      floating: true,
      delegate: FloatingChromeHeader(
        height: widget.headerHeight,
        vsync: this,
        child: widget.header!,
      ),
    );
  }

  /// My Garage / Leaderboard.
  ///
  /// Scrolls away with the content rather than pinning. Two tabs and a short
  /// list: pinning a row this small would cost more of the screen than it
  /// saves, and the garage is a page you read top to bottom.
  Widget _tabBar(ThemeProvider theme) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDEDED))),
      ),
      child: TabBar(
        controller: _tabs,
        labelColor: const Color(0xFF111111),
        unselectedLabelColor: Colors.grey.shade500,
        indicatorColor: const Color(0xFF111111),
        indicatorWeight: 2.5,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(
            height: 46,
            icon: null,
            child: _TabLabel(
              icon: Icons.directions_car_rounded,
              label: 'My Garage',
            ),
          ),
          Tab(
            height: 46,
            icon: null,
            child: _TabLabel(
              icon: Icons.emoji_events_rounded,
              label: 'Leaderboard',
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _garageSlivers(ThemeProvider theme) {
    if (_loadingGarage) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(color: theme.primaryColor),
          ),
        ),
      ];
    }

    final vehicles = _shelves[_shelf]!;

    return [
      SliverToBoxAdapter(child: _shelfPills(theme)),

      if (vehicles.isEmpty)
        SliverToBoxAdapter(child: _emptyShelf(theme))
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverList.separated(
            itemCount: vehicles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, i) => VehicleCard(
              vehicle: vehicles[i],
              onTap: () => _open(vehicles[i]),
            ),
          ),
        ),

      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: _AddVehicleCard(theme: theme, onTap: _addVehicle),
        ),
      ),
    ];
  }

  /// Current / Past / Dream, each with how many are on it.
  ///
  /// The count is the point: it says what is behind a pill before you tap
  /// it, so an empty shelf is visible rather than something you discover.
  Widget _shelfPills(ThemeProvider theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          for (final shelf in _Shelf.values) ...[
            _ShelfPill(
              label: shelf.label,
              count: _shelves[shelf]!.length,
              selected: shelf == _shelf,
              accent: theme.primaryColor,
              onTap: () {
                if (shelf == _shelf) return;
                DLHaptics.tabChange();
                setState(() => _shelf = shelf);
              },
            ),
            if (shelf != _Shelf.values.last) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _emptyShelf(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 8),
      child: Column(
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 42,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            _shelf.emptyLine,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _shelf.emptyDetail,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  /// The Leaderboard tab.
  ///
  /// Real vehicles, random order. There is no score to rank by yet: nothing
  /// counts likes against a vehicle, so the server shuffles and the rows
  /// show no count. A made-up number here would be the one thing on this
  /// screen nobody could tell was fake, and it would be the thing everybody
  /// looked at.
  List<Widget> _leaderboardSlivers(ThemeProvider theme) {
    return [
      SliverToBoxAdapter(child: _leaderboardFilters()),

      if (_loadingBoard)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(color: theme.primaryColor),
          ),
        )
      else if (_board.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 60),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: 46,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 14),
                Text(
                  'Nothing to rank yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Vehicles with a photo will show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        )
      else
        SliverList.separated(
          itemCount: _board.length,
          separatorBuilder: (_, __) => const Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: Color(0xFFF0F0F0),
          ),
          itemBuilder: (context, i) => _LeaderboardRow(
            rank: i + 1,
            vehicle: _board[i],
            accent: theme.primaryColor,
            onTap: () => _open(_board[i]),
          ),
        ),

      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  /// Period and Region.
  ///
  /// The region options are the four values the registration form writes —
  /// UK, USA, Canada, Other — and not a tidier list of continents, because
  /// that is the only country anybody has actually told us. A dropdown
  /// offering Europe and Australia would return nothing for either.
  Widget _leaderboardFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _FilterDropdown(
              label: 'Period',
              value: _period,
              options: const {
                'week': 'This week',
                'month': 'This month',
                'year': 'This year',
                'all': 'All time',
              },
              onChanged: (v) {
                setState(() => _period = v);
                _loadBoard();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _FilterDropdown(
              label: 'Region',
              value: _region,
              options: const {
                'worldwide': 'Worldwide',
                'UK': 'UK',
                'USA': 'USA',
                'Canada': 'Canada',
                'Other': 'Elsewhere',
              },
              onChanged: (v) {
                setState(() => _region = v);
                _loadBoard();
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadBoard() async {
    setState(() {
      _loadingBoard = true;
      _boardLoaded = true;
    });

    final rows = await GarageAPI.getLeaderboard(
      period: _period,
      region: _region,
    );

    if (!mounted) return;

    setState(() {
      _board = rows;
      _loadingBoard = false;
    });
  }

  Future<void> _open(dynamic vehicle) async {
    final result = await Navigator.pushNamed(
      context,
      '/vehicle-detail',
      arguments: {'garageId': vehicle['id'].toString()},
    );

    // Updated or deleted — either way the list it came from is now wrong.
    if (result != null) _loadGarage(true);
  }

  Future<void> _addVehicle() async {
    final result = await NavigationHelper.navigateTo(
      context,
      const AddVehicleScreen(),
    );

    if (result != null) _loadGarage(true);
  }
}

/// An icon and a label, side by side, for a tab.
class _TabLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TabLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 19), const SizedBox(width: 7), Text(label)],
    );
  }
}

/// Current / Past / Dream, with a count.
class _ShelfPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ShelfPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF111111) : Colors.white,
      shape: StadiumBorder(
        side: selected
            ? BorderSide.none
            : const BorderSide(color: Color(0xFFE2E2E2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 11, 12, 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF111111),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  // Gold on the selected pill, grey on the rest: on black the
                  // grey would vanish, and gold on white would read as a
                  // second selection.
                  color: selected ? accent : const Color(0xFFEFEFEF),
                  // A circle, as drawn. A stadium only looks like one while
                  // the count is a single digit, then quietly stretches.
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  count > 99 ? '99' : '$count',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : Colors.grey.shade600,
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

/// The dashed "Add a vehicle" card at the end of the list.
class _AddVehicleCard extends StatelessWidget {
  final ThemeProvider theme;
  final VoidCallback onTap;

  const _AddVehicleCard({required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: CustomPaint(
        painter: _DashedBorderPainter(color: const Color(0xFFD8D8D8)),
        child: SizedBox(
          height: 160,
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                // 44: the mockup's disc is 78px, which is 43.3pt.
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFF111111),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add, size: 22, color: theme.primaryColor),
              ),
              const SizedBox(height: 12),
              const Text(
                'Add a vehicle',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111111),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed rounded rectangle.
///
/// Painted rather than pulled in from a package: it is one shape used in one
/// place, and Flutter has no dashed border of its own.
class _DashedBorderPainter extends CustomPainter {
  static const double _radius = 16;
  static const double _dash = 6;
  static const double _gap = 5;

  final Color color;

  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(_radius)),
      );

    // Walked rather than drawn in one go: a dash pattern has to follow the
    // rounded corners, and PathMetric is what knows where they are.
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

/// A labelled dropdown: "Period  This month  ⌄".
///
/// A pill rather than a bare DropdownButton so it matches the shelf pills
/// above it on the other tab.
class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(23),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          onChanged: (v) {
            if (v != null && v != value) onChanged(v);
          },
          // The label rides inside the closed pill but not in the open menu,
          // where every row would otherwise read "Period This week".
          selectedItemBuilder: (context) => [
            for (final entry in options.entries)
              Row(
                children: [
                  Text(
                    '$label ',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      entry.value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111111),
                      ),
                    ),
                  ),
                ],
              ),
          ],
          items: [
            for (final entry in options.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value, style: const TextStyle(fontSize: 14)),
              ),
          ],
        ),
      ),
    );
  }
}

/// One ranked vehicle.
class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final dynamic vehicle;
  final Color accent;
  final VoidCallback onTap;

  const _LeaderboardRow({
    required this.rank,
    required this.vehicle,
    required this.accent,
    required this.onTap,
  });

  String get _title {
    final year = (vehicle['year'] ?? '').toString().trim();
    final make = (vehicle['make'] ?? '').toString().trim();
    final model = (vehicle['model'] ?? '').toString().trim();
    final variant = (vehicle['variant'] ?? '').toString().trim();

    final name = [
      year,
      make,
      model,
      variant,
    ].where((p) => p.isNotEmpty).join(' ');

    return name.isEmpty ? 'Vehicle' : name;
  }

  /// "@handle · GB", or just the handle when no country is recorded.
  String get _byline {
    final owner = vehicle['owner'];
    if (owner is! Map) return '';

    final handle = (owner['username'] ?? '').toString().trim();
    final place = (owner['location'] ?? '').toString().trim();

    if (handle.isEmpty) return place;
    if (place.isEmpty) return '@$handle';

    return '@$handle · $place';
  }

  /// The like count, or null while nothing counts them.
  int? get _likes {
    final raw = vehicle['likes'];
    final count = raw is int ? raw : int.tryParse('$raw');

    // Zero means "not counted yet", not "nobody likes it" — the server
    // returns a literal 0 until the scoring query exists. Showing
    // "0 likes" against every car would be worse than showing nothing.
    return (count == null || count == 0) ? null : count;
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}m';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final cover = (vehicle['cover_photo'] ?? '').toString().trim();
    final likes = _likes;
    final byline = _byline;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    // Gold for the podium, grey after: a leaderboard whose
                    // numbers all look the same is a numbered list.
                    color: rank <= 3 ? accent : Colors.grey.shade400,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  // 131x94px on the mockup = 72.8 x 52.2pt.
                  width: 72,
                  height: 52,
                  child: cover.isEmpty
                      ? ColoredBox(
                          color: Colors.grey.shade100,
                          child: Icon(
                            Icons.directions_car_outlined,
                            size: 22,
                            color: Colors.grey.shade400,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          memCacheWidth:
                              (66 * MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                          placeholder: (_, __) =>
                              ColoredBox(color: Colors.grey.shade100),
                          errorWidget: (_, __, ___) => ColoredBox(
                            color: Colors.grey.shade100,
                            child: Icon(
                              Icons.directions_car_outlined,
                              size: 22,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: Color(0xFF111111),
                      ),
                    ),
                    if (byline.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        byline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                    if (likes != null) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(Icons.favorite, size: 14, color: accent),
                          const SizedBox(width: 5),
                          Text(
                            '${_compact(likes)} likes',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111111),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
