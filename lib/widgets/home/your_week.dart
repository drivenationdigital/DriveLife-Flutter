import 'package:drivelife/screens/create-post/create_post_screen.dart';
import 'package:drivelife/api/places_api.dart';
import 'package:drivelife/main.dart' show BottomNavProvider;
import 'package:drivelife/models/venue_model.dart';
import 'package:drivelife/screens/clubs/open_club_creator.dart';
import 'package:drivelife/api/guess_api.dart';
import 'package:drivelife/api/posts_api.dart';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/models/user_model.dart' show LastLocation;
import 'package:drivelife/api/events_api.dart';
import 'package:drivelife/api/garage_api.dart';
import 'package:drivelife/api/garage_reminders_service.dart';
import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/providers/points_provider.dart';
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

/// One spotted car, as the Recent spots list needs it.
///
/// `rarity` is the LEGENDARY / EPIC badge in the design. Spots are to
/// get a status we set, and nothing carries one yet — see
/// docs/spots-backend-notes.md — so it is null today and the badge is
/// simply not drawn.
class RecentSpot {
  final String postId;
  final String vehicle;
  final String spotterName;
  final String? image;
  final String? rarity;

  const RecentSpot({
    required this.postId,
    required this.vehicle,
    required this.spotterName,
    this.image,
    this.rarity,
  });
}

class YourWeekPanelState extends State<YourWeekPanel> {
  static const Color _cardBlack = Color(0xFF111113);
  static const Color _cardInner = Color(0xFF232326);

  Map<String, dynamic>? _vehicle;
  Map<String, dynamic>? _reminder;

  /// Whether [_vehicle] is a dream car rather than one they own.
  bool _isDream = false;
  List<Map<String, dynamic>> _events = const [];

  /// Today's puzzle, or null when none is scheduled.
  GuessGame? _guess;

  /// Recently spotted cars. Empty hides the section — the tile that
  /// invites somebody to log one stays either way, because an empty
  /// list is exactly when the invitation matters most.
  List<RecentSpot> _spots = const [];

  /// Venues, nearest first. Empty hides the section.
  List<Venue> _venues = const [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(YourWeekPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Whose garage this is can change AFTER the first build.
    //
    // The shell builds this panel before the profile has finished
    // loading, so the first build gets whoever was signed in last —
    // which, right after a profile switch, is the previous account.
    // UserProvider lands a moment later and rebuilds us with the right
    // id, but a State keeps its data across a rebuild, so without this
    // the cards went on showing the other account's car until somebody
    // pulled to refresh. Which is exactly what they had to do.
    if (oldWidget.userId != widget.userId) _load();
  }

  /// Reload everything. Called by the screen's pull-to-refresh.
  Future<void> refresh() => _load();

  /// Just the game. Cheaper than _load for the one thing that
  /// changes when somebody comes back from playing it.
  Future<void> _loadGuess() async {
    final game = await GuessAPI.today();
    if (!mounted) return;

    setState(() => _guess = game);
  }

  /// Sections held back for now.
  ///
  /// Hidden rather than removed: each is finished, wired and working,
  /// and the open question is what the home page should LEAD with, not
  /// whether these should exist. Flipping one back to true restores both
  /// its section and the fetch behind it.
  static const bool _showSpots = false;
  static const bool _showVenues = false;

  /// The "Run a club?" invitation at the foot of the page.
  static const bool _showRunAClub = false;

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    // Together rather than one after another. The garage and the events
    // have nothing to do with each other, and run in series this panel
    // waits for the sum of two round trips before it draws anything.
    final results = await Future.wait([
      _loadVehicleAndReminder(),
      _loadEvents(),
      GuessAPI.today(),
      // Skipped while their sections are hidden. These were two of the
      // five round trips this panel waits on before it draws anything,
      // and fetching what nothing renders would make the page slower in
      // order to show less.
      //
      // Still occupying their slots, so the result indexes below do not
      // shift when a section comes back — an empty future is cheaper to
      // read than an index that means something different depending on
      // a flag.
      _showVenues ? _loadVenues() : Future.value(const <Venue>[]),
      _showSpots ? _loadSpots() : Future.value(const <RecentSpot>[]),
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
      _guess = results[2] as GuessGame?;
      _venues = results[3] as List<Venue>;
      _spots = results[4] as List<RecentSpot>;
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

  /// The two things to do today, side by side.
  ///
  /// The game is only there when one is scheduled; logging a spot
  /// always is. So the row is a pair most days and a single full-width
  /// tile on the days it is not, rather than a gap where the game
  /// would have been.
  /// How much taller than wide each tile is.
  ///
  /// The design measures 138 x 150 (1.087); this is a touch taller
  /// again, which reads better with the smaller type inside.
  ///
  /// A ratio rather than a fixed height, because tile WIDTH depends on
  /// the screen — two earlier constants were wrong in opposite
  /// directions, 168 too tall on a small phone and 148 landscape on a
  /// large one.
  static const double _tileAspect = 1.18;

  /// The gap between the two tiles.
  static const double _tileGap = 12.0;

  /// The two things to do today, side by side.
  ///
  /// The height comes from the WIDTH the row is given rather than a
  /// constant, so the tiles keep the design's proportions from a small
  /// phone to a tablet instead of being right on exactly one device.
  Widget _playRow(ThemeProvider theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paired = (constraints.maxWidth - _tileGap) / 2;
        final height = paired * _tileAspect;

        // On a day with no game the invitation takes the full width —
        // but keeps the PAIRED height, because scaling it to a
        // full-width tile would make a banner half the screen tall.
        if (_guess == null) {
          return SizedBox(height: height, child: _logSpotTile(theme));
        }

        return SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(child: _guessCard(theme)),
              const SizedBox(width: _tileGap),
              Expanded(child: _logSpotTile(theme)),
            ],
          ),
        );
      },
    );
  }

  /// An invitation to log a spot.
  ///
  /// A photograph behind it rather than the flat grey it used to be:
  /// the tile is asking for a picture of a car, and showing one says
  /// that faster than the words do.
  ///
  /// Everything on top is white over a scrim, because the artwork is
  /// fixed but not plain — text straight onto it would be legible in
  /// the dark corners and not in the sky.
  Widget _logSpotTile(ThemeProvider theme) {
    return Material(
      color: _cardBlack,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const CreatePostScreen(startAsSpot: true),
            ),
          );
          if (mounted) await _load();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/spot1.jpg',
              fit: BoxFit.cover,
              // A missing or unreadable asset must not take the home
              // page down — the tile still works as a dark card.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),

            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xE6000000), Color(0x40000000)],
                ),
              ),
            ),

            // Bottom-left, exactly like the game card beside it. The
            // camera-in-a-circle that used to sit at the top is gone:
            // the design has no icon, the photograph already says what
            // the tile is about, and the two tiles only read as a pair
            // when they are built the same way.
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DlHeading(
                    'Log a spot',
                    fontSize: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Seen something rare?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade300),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One spotted car.
  Widget _spotRow(ThemeProvider theme, RecentSpot spot) {
    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.postDetail,
        arguments: {'postId': spot.postId},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Container(
                // 56x44, from the design. The old 74x56 made each row
                // tall enough that three spots filled the screen.
                width: 56,
                height: 44,
                color: const Color(0xFFEDEDED),
                child: (spot.image ?? '').isEmpty
                    ? Icon(
                        Icons.directions_car_outlined,
                        size: 22,
                        color: Colors.grey.shade400,
                      )
                    : CachedNetworkImage(
                        imageUrl: spot.image!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
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
                    spot.vehicle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: theme.textColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    spot.spotterName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (spot.rarity != null) ...[
              const SizedBox(width: 10),
              _rarityBadge(theme, spot.rarity!),
            ],
          ],
        ),
      ),
    );
  }

  /// LEGENDARY, EPIC, and whatever else the statuses turn out to be.
  ///
  /// Two styles only: the top status is black, everything else is
  /// gold. Written against the NAME rather than a list of known
  /// values, so a status nobody has told this widget about still draws
  /// as a badge instead of disappearing.
  Widget _rarityBadge(ThemeProvider theme, String rarity) {
    final top = rarity.toUpperCase() == 'LEGENDARY';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: top ? _cardBlack : theme.primaryColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        rarity.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: top ? theme.primaryColor : Colors.white,
        ),
      ),
    );
  }

  /// Venues near this person, as cards.
  ///
  /// This was six group pills. Cards rather than pills because a venue
  /// is somewhere you might actually go and a photo of it is most of
  /// what makes you want to — a group is a name and a number, which is
  /// all a pill can hold, and a venue is not.
  ///
  /// Horizontal rather than wrapped, for the same reason: a card wide
  /// enough to show a photo properly is most of the screen, and six of
  /// them stacked would be the whole page. The next card peeking past
  /// the edge is what says there are more.
  Widget _venuesNearYou(ThemeProvider theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: DlHeading(
                'Venues near you',
                fontSize: 22,
                color: theme.textColor,
              ),
            ),
            TextButton(
              // The Map destination, by name. A bare 2 here is exactly
              // what sent "Find Events" to the map once before — see
              // BottomNavProvider.
              onPressed: () => context.read<BottomNavProvider>().setIndex(
                BottomNavProvider.discover,
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'All venues',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: theme.primaryColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        SizedBox(
          height: _venueCardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // The panel already pads its sides, and a horizontal list
            // inside that padding cannot let a card run to the edge. The
            // padding is cancelled here and re-applied per card instead,
            // so the row scrolls edge to edge and the last card is not
            // stranded in a gutter.
            padding: EdgeInsets.zero,
            clipBehavior: Clip.none,
            itemCount: _venues.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _venueCard(theme, _venues[i]),
          ),
        ),
      ],
    );
  }

  /// Image, name, where it is and how far.
  ///
  /// Height is fixed because a horizontal ListView has no other way to
  /// size itself, so the parts have to add up: 112 of photo, 12 of
  /// padding, the two lines of text, and 12 again underneath.
  static const double _venueCardWidth = 216;
  static const double _venueCardHeight = 180;

  Widget _venueCard(ThemeProvider theme, Venue venue) {
    final place = venue.venueLocation.trim();
    final miles = venue.distance.round();

    // "Sherburn in Elmet · 12 mi", or just one of them when that is all
    // there is. Joined rather than concatenated so a missing place does
    // not leave a leading separator.
    final meta = [
      if (place.isNotEmpty) place,
      if (miles > 0) '$miles mi',
    ].join(' · ');

    return SizedBox(
      width: _venueCardWidth,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.venueDetails,
            arguments: {'venueId': venue.id},
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 112,
                width: double.infinity,
                child: venue.coverImage.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: venue.coverImage,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(color: const Color(0xFFEFEFEF)),
                        errorWidget: (_, _, _) => _venuePlaceholder(),
                      )
                    : _venuePlaceholder(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: Color(0xFF111111),
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF8A8A8A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _venuePlaceholder() {
    return Container(
      color: const Color(0xFFEFEFEF),
      child: Icon(
        Icons.place_outlined,
        size: 26,
        color: Colors.grey.shade400,
      ),
    );
  }

  /// An invitation to start a club, at the foot of the page.
  ///
  /// Last on purpose. It is the one thing here addressed to a minority
  /// — most people are not going to run anything — so it sits below
  /// everything that is for everybody, where it reads as an offer
  /// rather than a demand for attention.
  ///
  /// Quiet by design too: a grey card, not a gold one. The sections
  /// above are about this person's own week, and an advertisement
  /// competing with them would be the loudest thing on a page it has
  /// the least claim to.
  Widget _runAClub(ThemeProvider theme) {
    return Material(
      color: const Color(0xFFF2F2F2),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openClubCreator(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.verified_user_outlined,
                  size: 26,
                  color: Color(0xFF111113),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Not a DlHeading. Headings here are uppercase, and
                    // "RUN A CLUB?" shouts a question nobody asked.
                    const Text(
                      'Run a club?',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111113),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Verified page, RSVP calendar, run routes and '
                      'members-only chat',
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 22, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }

  /// The last few cars anybody spotted.
  ///
  /// THE SWAP POINT. Nothing reads spots back yet: create-post writes
  /// `spotted_vehicle` and no endpoint selects it, so there is no feed
  /// to ask. Returning empty is therefore not a placeholder, it is the
  /// truth — there are no spots to show — and the section correctly
  /// hides itself until a feed exists.
  ///
  /// See docs/spots-backend-notes.md for the endpoint this wants.
  Future<List<RecentSpot>> _loadSpots() async {
    try {
      final spots = await PostsAPI.recentSpots(limit: 3);

      return spots.map((spot) {
        final user = spot['user'];
        final name = user is Map ? (user['short_name'] ?? user['name']) : null;

        return RecentSpot(
          postId: '${spot['post_id']}',
          vehicle: (spot['spotted_vehicle'] ?? '').toString(),
          spotterName: (name ?? '').toString(),
          image: spot['image'] as String?,
          // Null for everything today — nothing stores a rarity yet, and
          // the badge simply is not drawn when it is absent.
          rarity: spot['rarity'] as String?,
        );
      }).toList();
    } catch (e) {
      debugPrint('[YourWeek] spots failed: $e');
      return const [];
    }
  }

  /// Groups near enough to turn up to.
  ///
  /// 'near-me' rather than the whole country, because this section is
  /// the one place on the page about a thing you would physically go
  /// to. The server applies the radius from the user's last location
  /// and orders by engagement, so these are the nearby groups with
  /// something actually happening in them.
  ///
  /// Six, because they are pills on a wrap: more than that is a
  /// paragraph of chips, and the last row ends up a ragged orphan.
  /// How many venues to look at before picking the nearest few.
  ///
  /// Same reasoning as [_eventSearchWindow]: the server does not order by
  /// distance, so the nearest one is not necessarily the first one back.
  static const int _venueSearchWindow = 40;

  /// How many end up on screen.
  static const int _venueCount = 6;

  /// The nearest venues in the user's country.
  ///
  /// Asked for NATIONALLY and then sorted here, rather than asked for
  /// within a radius. [_loadEvents] has the same note and it was learned
  /// the same way: a radius left everybody outside a city looking at an
  /// empty section, which says "there are no venues" when it means
  /// "none within 25 miles". Country-wide always has something in it,
  /// and sorting by distance keeps the section honest about being "near
  /// you".
  ///
  /// 'national' is a 2000-mile radius server-side rather than no radius
  /// at all — see dl_radius_for_location(). That covers the UK many
  /// times over and clips the United States, so a user in Las Vegas
  /// still cannot see the east coast. Fine for the nearest six, and the
  /// same cap this section would hit if it ever wanted the furthest.
  Future<List<Venue>> _loadVenues() async {
    try {
      final result = await VenueApiService.getTrendingVenues(
        page: 1,
        limit: _venueSearchWindow,
        location: 'national',
      );

      if (result == null || result['data'] == null) return const [];

      final venues = VenuesResponse.fromJson(result).data
          // A venue with no distance cannot be placed in a list whose
          // whole claim is proximity, and sorts to the front as 0.
          .where((venue) => venue.distance > 0)
          .toList();

      venues.sort((a, b) => a.distance.compareTo(b.distance));

      return venues.take(_venueCount).toList();
    } catch (e) {
      debugPrint('[YourWeek] venues failed: $e');
      return const [];
    }
  }

  /// How many upcoming events to look at before picking the five.
  ///
  /// The five nearest in the whole country cannot be asked for: the
  /// server orders by date and knows nothing about distance, so the
  /// nearest one might be the fortieth it returns. This is the window
  /// that gets searched — wide enough that the answer is almost always
  /// really the nearest five, small enough to stay one cheap request.
  static const int _eventSearchWindow = 60;

  /// The five nearest events in the user's country, in date order.
  ///
  /// Two different orderings, and they are not in conflict: distance
  /// decides WHICH five (there is no point offering somebody an event
  /// four hundred miles away), and the date decides what order they are
  /// read in, because a list of things to go to that jumps backwards
  /// and forwards through the calendar cannot be planned against.
  ///
  /// Country-wide rather than 'near-me': the radius was leaving people
  /// outside the big cities with an empty section, which says "nothing
  /// is happening" when it means "nothing is happening within 25 miles".
  Future<List<Map<String, dynamic>>> _loadEvents() async {
    try {
      final response = await EventsAPI.getEvents(
        page: 1,
        limit: _eventSearchWindow,
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

      // Whichever five came out of that, read in date order. Without a
      // location to measure from there is no distance pass at all and
      // these are simply the next five, which is already what the
      // server sent.
      final nearest = events.take(5).toList()
        ..sort((a, b) {
          final left = _parseEventDate(a['start_date']);
          final right = _parseEventDate(b['start_date']);

          // An unparseable date sinks rather than scrambling the rest.
          if (left == null) return right == null ? 0 : 1;
          if (right == null) return -1;

          return left.compareTo(right);
        });

      return nearest;
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
        // A plain gap at the foot now, because this panel is no longer
        // the end of anything.
        //
        // It used to carry 160 plus the safe area, for two reasons that
        // both belonged to Your week being a TAB of its own: the
        // floating bottom bar sat over its last card, and with the other
        // tabs offstage this panel WAS the entire scroll extent, so
        // short content left the page unscrollable and the floating
        // header with no gesture to respond to.
        //
        // It is the head of Latest now, with the feed below it. The feed
        // is the scroll extent and the feed's last post is what has to
        // clear the bar — posts_screen pads for that. Keeping 160 here
        // just put a hand's width of white between the Run a club tile
        // and the first post.
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _greeting(theme),
            const SizedBox(height: 14),

            if (_loading)
              _skeleton()
            else ...[
              if (_vehicle != null) _garageCard(theme) else _emptyGarage(theme),

              // Get involved BEFORE the events.
              //
              // It is the part of this page asking to be joined in with,
              // and under a list of dates it was the fourth thing down —
              // read as another section rather than as an invitation.
              // The events are a reference you scan; this is a thing you
              // do.
              //
              // The heading matters for the same reason: it makes the
              // daily game read as something to join in with rather than
              // another card in the same list as the events.
              const SizedBox(height: 28),
              DlHeading('Get involved', fontSize: 22, color: theme.textColor),
              const SizedBox(height: 10),
              _playRow(theme),

              const SizedBox(height: 28),
              _eventsSection(theme),

              if (_showSpots && _spots.isNotEmpty) ...[
                const SizedBox(height: 26),
                DlHeading('Recent spots', fontSize: 22, color: theme.textColor),
                const SizedBox(height: 6),
                for (final spot in _spots) _spotRow(theme, spot),
              ],

              if (_showVenues && _venues.isNotEmpty) ...[
                const SizedBox(height: 28),
                _venuesNearYou(theme),
              ],

              if (_showRunAClub) ...[
                const SizedBox(height: 14),
                _runAClub(theme),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _greeting(ThemeProvider theme) {
    final name = widget.firstName?.trim();

    return Row(
      // Centred, not baseline-aligned. The chip is a 17pt emoji next
      // to a 28pt heading, and aligning their BOTTOMS hung the flag
      // below the cap line where it read as having slipped.
      crossAxisAlignment: CrossAxisAlignment.center,
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
        _locationChip(theme),
      ],
    );
  }

  /// Where they are, as a flag and a short country name.
  ///
  /// Replaces the date, which told somebody something they could read
  /// off the top of their own phone. The country is the thing that
  /// explains the rest of this screen — the events below are the ones
  /// near them, and this says which "near" the app is using.
  ///
  /// Empty when last_location has never been recorded, in which case
  /// the row shows nothing rather than a guess.
  Widget _locationChip(ThemeProvider theme) {
    final code = widget.from?.country.trim().toUpperCase() ?? '';
    if (code.length != 2) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Nudged up a hair. Emoji glyphs carry their own internal
        // padding and sit low in their line box, so optical centring
        // needs a pixel the layout will not give.
        Transform.translate(
          offset: const Offset(0, -1),
          child: Text(_flag(code), style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 6),
        Text(
          _countryName(code),
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: theme.subtextColor,
          ),
        ),
      ],
    );
  }

  /// A two-letter country code as its flag emoji.
  ///
  /// Regional indicator symbols: 'G' + 'B' become the two codepoints
  /// U+1F1EC U+1F1E7, which every platform renders as one flag. Built
  /// arithmetically rather than from a table of 250 emoji — the
  /// alphabet offset is the whole rule.
  ///
  /// Android before 11 has no flag glyphs and will draw the two letters
  /// "GB" instead. That is a reasonable thing to fall back to, which is
  /// why there is no detection here.
  static String _flag(String code) {
    const base = 0x1F1E6; // regional indicator A
    const a = 0x41; // 'A'

    return String.fromCharCodes([
      base + (code.codeUnitAt(0) - a),
      base + (code.codeUnitAt(1) - a),
    ]);
  }

  /// The short name people actually say.
  ///
  /// Only the markets the app is in, falling back to the raw code. A
  /// full ISO table is 250 entries to carry for a label, and "GB" is
  /// not a worse answer than a country name nobody expected to see.
  static String _countryName(String code) {
    const names = {
      'GB': 'UK',
      'US': 'USA',
      'IE': 'Ireland',
      'FR': 'France',
      'DE': 'Germany',
      'ES': 'Spain',
      'IT': 'Italy',
      'NL': 'Netherlands',
      'BE': 'Belgium',
      'PT': 'Portugal',
      'PL': 'Poland',
      'SE': 'Sweden',
      'NO': 'Norway',
      'DK': 'Denmark',
      'CH': 'Switzerland',
      'AT': 'Austria',
      'AU': 'Australia',
      'NZ': 'New Zealand',
      'CA': 'Canada',
      'AE': 'UAE',
      'ZA': 'South Africa',
      'JP': 'Japan',
    };

    return names[code] ?? code;
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
                          // From the server, not written out. This label
                          // and the reward it promises were two separate
                          // numbers, and when the rewards were reduced
                          // this one still said 500.
                          '+${context.watch<PointsProvider>().rules.amountFor('vehicle_added')} points',
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
                'Upcoming events',
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

  /// The daily game, under the events row.
  ///
  /// Nothing at all when no game is scheduled. An empty frame saying
  /// "no game today" is a worse answer than silence — it draws the eye
  /// to an absence the user cannot do anything about.
  Widget _guessCard(ThemeProvider theme) {
    final game = _guess;
    if (game == null) return const SizedBox.shrink();

    return Material(
      color: _cardBlack,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.pushNamed(context, AppRoutes.guess);
          // Coming back from a guess changes what this card says, so
          // it re-reads rather than showing yesterday's state.
          if (mounted) await _loadGuess();
        },
        // No height of its own: the card fills whatever _playRow gives
        // it. It used to carry a second copy of the number, which meant
        // the row and the card could disagree — and only one of them
        // could win.
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Guarded, like the other two images on this panel.
              // CachedNetworkImage treats an empty string as a URL to
              // fetch and throws "No host specified in URI", which
              // takes the whole screen down rather than leaving one
              // grey rectangle.
              if (game.image.trim().isEmpty)
                const ColoredBox(color: _cardInner)
              else
                CachedNetworkImage(
                  imageUrl: game.image,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const ColoredBox(color: _cardInner),
                  errorWidget: (_, _, _) => const ColoredBox(color: _cardInner),
                ),

              // Dark from the bottom up, so the title reads over
              // whatever the photograph happens to be.
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black26, Colors.black87],
                        stops: [0.3, 1],
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'DAILY',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              // What the card is FOR: whether there is anything to do.
              // "Closes 7pm" on a game already guessed would invite a
              // tap that cannot change anything.
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _guessStatus(game),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 20, matching Log a spot. At 24 the two tiles had
                    // different-sized titles, which is the first thing
                    // the eye picks up on a pair.
                    const DlHeading(
                      'Guess the car',
                      fontSize: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // "#214 · 3 guesses" — which game it is and how
                      // many people have played it.
                      //
                      // In place of "+500 points if you get it right",
                      // which said the same thing every single day and
                      // so stopped being read. A guess count changes,
                      // and a number that moves is a reason to look.
                      //
                      // The answer still wins once the game has closed:
                      // at that point the only thing anybody wants from
                      // this card is what the car was.
                      game.isClosed
                          ? 'Answer: ${game.answer ?? 'revealed'}'
                          : _guessSubtitle(game),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "#214 · 3 guesses".
  ///
  /// The number is dropped if the server has not sent one, rather than
  /// printing "#0" — an old build talking to an updated server is the
  /// normal case during a rollout, and so is the reverse.
  ///
  /// "guess" singular at one, because "1 guesses" on the first play of
  /// the day is the sort of thing people screenshot.
  static String _guessSubtitle(GuessGame game) {
    final guesses = game.guessCount == 1
        ? '1 guess'
        : '${game.guessCount} guesses';

    return game.number > 0 ? '#${game.number} · $guesses' : guesses;
  }

  static String _guessStatus(GuessGame game) {
    if (game.isClosed) {
      if (!game.hasPlayed) return 'Missed';
      return game.myCorrect == true ? 'Correct' : 'Wrong';
    }

    if (game.hasPlayed) return 'Guessed';
    if (!game.isOpen) return 'Opens 7am';

    return 'Closes 7pm';
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
