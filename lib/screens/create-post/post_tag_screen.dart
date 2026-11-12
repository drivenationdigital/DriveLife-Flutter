import 'package:drivelife/api/garage_api.dart';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/models/tag_suggestion.dart';
import 'package:drivelife/models/tagged_entity.dart';
import 'package:drivelife/screens/create-post/post_photo_tagging_screen.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// What the user settled on, handed back to the composer.
///
/// Returned rather than written here: the post does not exist yet, and
/// publishing stays in one place — the composer — so there is a single
/// answer to "what starts an upload".
class PostTagResult {
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final List<TaggedEntity> events;
  final List<TaggedEntity> vehicles;

  const PostTagResult({
    this.locationName,
    this.latitude,
    this.longitude,
    this.events = const [],
    this.vehicles = const [],
  });
}

/// Step three of posting — where it was, what was on, and which car.
///
/// ── THE POST IS ALREADY LIVE ────────────────────────────────────────
///
/// Reached once the upload has finished, so nothing here is holding the
/// post up. Share writes the tags and leaves.
///
/// ── TWO SOURCES, TWO SPEEDS ─────────────────────────────────────────
///
/// Locations and events come from the photos' own coordinates, which
/// the server already has and can answer in one query — so they are on
/// screen almost immediately.
///
/// Vehicles come from reading the images, which is several seconds per
/// photo. Waiting for that before showing anything would make this
/// screen feel broken, so it fills in underneath while the rest is
/// already usable.
///
/// ── WHY IT GUESSES ──────────────────────────────────────────────────
///
/// The nearest place and the event running there that day are applied
/// without being asked. Nobody tags a location if it costs three taps,
/// so the default has to be the answer — but an automatic claim about
/// where somebody was has to be visible and removable, which is what
/// the small auto mark on a guessed chip is for.
class PostTagScreen extends StatefulWidget {
  /// The post, already created and live.
  final int postId;

  /// True when reached from an existing post rather than from posting.
  ///
  /// Changes two things. The tags already on the post are loaded first,
  /// so they show as chips instead of the screen looking empty — and
  /// Share removes anything taken off, which the posting path never has
  /// to do because there is nothing there yet.
  final bool editing;

  const PostTagScreen({super.key, required this.postId, this.editing = false});

  @override
  State<PostTagScreen> createState() => _PostTagScreenState();
}

class _PostTagScreenState extends State<PostTagScreen> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFAE9159);
  static const Color _goldSoft = Color(0xFFF5EFE3);
  static const Color _line = Color(0xFFEDEDED);

  /// How close an event has to be to be applied without being asked.
  ///
  /// Covers a showground and its overflow parking, and not the next
  /// town. See where it is used.
  static const double _autoApplyMiles = 3;

  bool _checking = true;
  bool _saving = false;

  /// The vehicle scan, which runs behind the rest of the screen.
  bool _scanning = false;
  bool _scanDone = false;

  TagSuggestions _suggestions = TagSuggestions.empty;

  TagSuggestion? _location;

  /// Held as TaggedEntity rather than as suggestions, so a tag the
  /// composer already made passes through untouched.
  ///
  /// TagEntitiesScreen tags a car at a POSITION on a particular photo —
  /// x, y and mediaId. Rebuilding those from a label would throw all
  /// three away, so anything that arrives here leaves here as the same
  /// object it came in as.
  final List<TaggedEntity> _events = [];
  final List<TaggedEntity> _vehicles = [];

  /// People tagged on the post.
  ///
  /// Not something this screen can add — a person is tagged at a
  /// POSITION on a particular photo, which is what PostPhotoTaggingScreen
  /// is for. Listed here so the screen shows everything that is on the
  /// post rather than three of its four kinds of tag.
  final List<TaggedEntity> _people = [];

  /// Which ids this screen applied on its own, for the auto mark.
  final Set<String> _guessedIds = {};

  List<_GarageVehicle> _garage = const [];
  bool _garageLoaded = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Stops the scan loop if the screen goes away mid-run.
  bool _disposed = false;

  /// Asks the server what the post's photos were near.
  ///
  /// One call for the whole post: the coordinates went up with it, and
  /// the server merges every photo's answer nearest-first — so the top
  /// of each list is where the photographer most likely actually was,
  /// whichever photo saw it best.
  ///
  /// That call is also what erases the stored coordinates, which is why
  /// it happens whether or not anything is found.
  Future<void> _check() async {
    if (widget.editing) await _loadExisting();

    final found = await PostsAPI.postTagSuggestions(widget.postId);

    if (!mounted) return;

    if (found.why.isNotEmpty) {
      // The server's account of why there is nothing to show. Logged
      // rather than displayed: it names tables and deploy state, which
      // is for us, not for whoever just posted a photo.
      debugPrint('[PostTag] no suggestions — ${found.why.join('; ')}');
    }

    setState(() {
      _suggestions = found;
      _checking = false;

      // The guesses: nearest of each.
      if (_location == null && found.locations.isNotEmpty) {
        _location = found.locations.first.asGuess();
      }

      // ── ONLY A CLOSE EVENT IS APPLIED WITHOUT ASKING ──────────────
      //
      // The event search runs out to 25 miles, because the date carries
      // most of the weight. That is the right net to CAST, and the wrong
      // one to act on blind: a photo taken at home on a Sunday when a
      // show is twenty miles away would otherwise be tagged as being at
      // the show.
      //
      // So the far ones are offered in the list and the near ones are
      // applied. Anything beyond this is a suggestion, not a conclusion.
      if (_events.isEmpty && found.events.isNotEmpty) {
        final guess = found.events.first;
        final miles = guess.distanceMiles;

        if (miles != null && miles <= _autoApplyMiles) {
          _events.add(_asTag(guess, 'event'));
          _guessedIds.add(guess.id);
        }
      }
    });

    _loadGarage();
    _runScan();
  }

  /// What is already tagged on this post.
  ///
  /// Only for the editing path. Each tag keeps the row id it was loaded
  /// with, because removing one is a delete by id — a label is not
  /// enough to say which row to take off.
  Future<void> _loadExisting() async {
    try {
      final tags = await PostsAPI.fetchPostTags(postId: widget.postId);

      if (!mounted) return;

      setState(() {
        _events.clear();
        _vehicles.clear();
        _people.clear();
        _tagIds.clear();

        for (final raw in tags) {
          final tagId = int.tryParse('${raw['tag_id']}') ?? 0;
          final type = '${raw['type']}';

          if (tagId <= 0) continue;

          // The name, picture and plate live in a nested `entity`, not
          // at the top level — which is why reading them from the row
          // itself produced chips with no label at all.
          final entity = raw['entity'];
          final map = entity is Map
              ? Map<String, dynamic>.from(entity)
              : <String, dynamic>{};

          final registration = '${map['registration'] ?? ''}'.trim();
          final name = '${map['name'] ?? ''}'.trim();

          final held = TaggedEntity(
            index: 0,
            id: '${raw['entity_id'] ?? ''}',
            type: type.contains('car') ? 'car' : type,
            // A plate reads better than a make and model for a car,
            // and is all there is for one nobody has claimed.
            label: type.contains('car')
                ? (registration.isNotEmpty ? registration : name)
                : name,
            imageUrl: '${map['image'] ?? ''}',
            registration: registration,
          );

          if (held.label.isEmpty && held.registration.isEmpty) continue;

          if (type == 'event') {
            _events.add(held);
            _tagIds['event:${held.id}'] = tagId;
            continue;
          }

          if (type == 'user') {
            _people.add(held);
            _tagIds['user:${held.id}'] = tagId;
            continue;
          }

          if (type.contains('car')) {
            _vehicles.add(held);
            _tagIds['car:${held.id}'] = tagId;
          }
        }
      });
    } catch (e) {
      debugPrint('[PostTag] could not load existing tags: $e');
    }
  }

  /// Row ids for tags that were already on the post, so Share can remove
  /// the ones taken off. Keyed 'type:entityId'.
  final Map<String, int> _tagIds = {};

  /// Reads the photos for vehicles, behind the rest of the screen.
  ///
  /// Polled rather than awaited up front: each image is a model round
  /// trip of several seconds, and the endpoint does a few per call. The
  /// Garage Vehicles card says so while this runs.
  Future<void> _runScan() async {
    setState(() => _scanning = true);

    try {
      var done = false;

      // Bounded so a server that never reports done cannot spin forever.
      for (var pass = 0; pass < 100 && !done; pass++) {
        final result = await PostsAPI.scanPost(postId: widget.postId);

        if (_disposed || !mounted) return;

        if (result['available'] == false) {
          setState(() => _scanning = false);
          return;
        }

        done = result['done'] == true;

        final found = (result['suggestions'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        setState(() {
          _scanDone = done;

          for (final suggestion in found) {
            final id = '${suggestion['entity_id'] ?? ''}';
            final plate = '${suggestion['registration'] ?? ''}';

            if (id.isEmpty && plate.isEmpty) continue;

            // The scan returns everything found so far on every pass,
            // so without this each pass would add the same cars again.
            if (_vehicles.any((v) => v.id == id && id.isNotEmpty)) continue;
            if (_vehicles.any(
              (v) => v.registration == plate && plate.isNotEmpty,
            )) {
              continue;
            }

            _vehicles.add(
              TaggedEntity(
                index: int.tryParse('${suggestion['index']}') ?? 0,
                id: id,
                type: 'car',
                label: plate.isNotEmpty
                    ? plate
                    : '${suggestion['subtitle'] ?? ''}',
                imageUrl: '${suggestion['image'] ?? ''}',
                registration: plate,
              ),
            );

            _guessedIds.add(id.isNotEmpty ? id : plate);
          }
        });
      }
    } catch (e) {
      // A failed scan is not a failed post — it is already published —
      // so this is reported in the card rather than over the top of it.
      debugPrint('[PostTag] scan failed: $e');
    } finally {
      if (!_disposed && mounted) {
        setState(() {
          _scanning = false;
          _scanDone = true;
        });
      }
    }
  }

  /// The user's own cars, for the manual picker.
  ///
  /// Not awaited by [_check]: the suggestion lookup is what the spinner
  /// is waiting on, and a slow garage should not hold the screen shut.
  int _userId(BuildContext context) =>
      int.tryParse('${context.read<UserProvider>().user?.id}') ?? 0;

  Future<void> _loadGarage() async {
    if (!mounted) return;

    try {
      final rows = await GarageAPI.getUserGarage(_userId(context));

      if (!mounted) return;

      setState(() {
        _garage = (rows ?? const [])
            .whereType<Map>()
            .map((r) => _GarageVehicle.fromMap(Map<String, dynamic>.from(r)))
            .where((v) => v.id.isNotEmpty)
            .toList();
        _garageLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _garageLoaded = true);
    }
  }

  /// A suggestion as a tag. index 0 because a suggestion is about the
  /// post, not about a position on one photo — unlike the composer's
  /// per-photo tagging, which is why those are never rebuilt this way.
  TaggedEntity _asTag(TagSuggestion s, String type) => TaggedEntity(
    index: 0,
    id: s.id,
    type: type,
    label: s.title,
    imageUrl: s.imageUrl,
  );

  /// Writes the tags and leaves.
  ///
  /// The post is already live, so a failure here loses the tags, not the
  /// post — reported in place rather than trapping anybody on a screen
  /// whose work is already published.
  Future<void> _share() async {
    if (_saving) return;

    setState(() => _saving = true);

    final userId = _userId(context);

    try {
      await _persist(userId);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your post is live, but the tags did not save. '
            '${'$e'.replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;

    // Editing came from a post, so it goes back to THAT — popping to the
    // root would throw somebody out of the venue tab they were reading.
    //
    // Posting came through the whole create flow, which there is nothing
    // to return to: the composer is gone and the post is already live.
    if (widget.editing) {
      Navigator.of(context).pop(true);
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to go back TO — the post is already live, and leaving
    // mid-save would abandon tags that are halfway written.
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: const Border(bottom: BorderSide(color: _line)),
          leading: TextButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left, color: _ink, size: 24),
            label: const Text(
              'Back',
              style: TextStyle(color: _ink, fontSize: 16),
            ),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
          leadingWidth: 96,
          centerTitle: true,
          title: Text(
            widget.editing ? 'Edit tags' : 'Tag your post',
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
              child: FilledButton(
                // Live even while checking: somebody who does not want any
                // of this should not have to wait for a lookup to finish
                // before they can post.
                onPressed: _saving ? null : _share,
                style: FilledButton.styleFrom(
                  backgroundColor: (_checking || _saving)
                      ? _gold.withValues(alpha: 0.55)
                      : _gold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  shape: const StadiumBorder(),
                ),
                // Saving a handful of tags is two round trips, which is
                // long enough to look like nothing happened — and the
                // screen closes itself when it finishes, so without this
                // the only feedback is the app appearing to freeze and
                // then vanish.
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Text(
                        widget.editing ? 'Save' : 'Share',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
        body: _checking ? _checkingBody() : _tagsBody(),
      ),
    );
  }

  Widget _checkingBody() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 140,
                  height: 140,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(_gold),
                    backgroundColor: Color(0xFFF0E9DC),
                  ),
                ),
                Container(
                  width: 108,
                  height: 108,
                  decoration: const BoxDecoration(
                    color: _ink,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    color: _gold,
                    size: 40,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 34),
          const Text(
            'CHECKING FOR TAGS',
            style: TextStyle(
              color: _ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Looking for locations, events and garage vehicles in your '
              'photos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 15, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagsBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        const Text(
          'TAG YOUR POST',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ink,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Add locations, events and garage vehicles so people can find it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 15, height: 1.35),
          ),
        ),
        const SizedBox(height: 22),

        _card(
          icon: Icons.location_on_outlined,
          title: 'Locations',
          count: _location == null ? 'Add a location' : '1 tagged',
          onAdd: _pickLocation,
          chips: [
            if (_location != null)
              _chip(
                label: _location!.title,
                guessed: _location!.guessed,
                onRemove: () => setState(() => _location = null),
              ),
          ],
        ),

        const SizedBox(height: 12),

        _card(
          icon: Icons.calendar_today_outlined,
          title: 'Events',
          count: _events.isEmpty ? 'Link an event' : '${_events.length} tagged',
          onAdd: _pickEvents,
          chips: _events
              .map(
                (e) => _chip(
                  label: e.label,
                  guessed: _guessedIds.contains(e.id),
                  imageUrl: e.imageUrl,
                  onRemove: () => setState(() => _events.remove(e)),
                ),
              )
              .toList(),
        ),

        const SizedBox(height: 12),

        _card(
          icon: Icons.directions_car_outlined,
          title: 'Garage Vehicles',
          count: _scanning
              ? 'Checking your photos for vehicles…'
              : _vehicles.isEmpty
              ? 'Add a vehicle'
              : '${_vehicles.length} tagged',
          // Only while the scan is actually running. A finished scan that
          // found nothing is a result, not a reason to keep spinning.
          busy: _scanning,
          onAdd: _pickVehicles,
          chips: _vehicles
              .map(
                (v) => _chip(
                  label: v.label,
                  guessed: _guessedIds.contains(v.id),
                  imageUrl: v.imageUrl,
                  onRemove: () => setState(() => _vehicles.remove(v)),
                ),
              )
              .toList(),
        ),

        const SizedBox(height: 12),

        // ── PEOPLE, AND PHOTO BY PHOTO ──────────────────────────────
        //
        // The + here opens the per-photo tagger rather than a list,
        // because a person is tagged at a POSITION on a particular
        // photo — which a flat picker cannot express, and which is why
        // everything added from one used to land on the first image.
        //
        // It tags cars that way too, so it is also the way to put a
        // plate on the right photo rather than on the post.
        _card(
          icon: Icons.person_outline,
          title: 'People & photos',
          count: _people.isEmpty
              ? 'Tag people in your photos'
              : '${_people.length} tagged',
          onAdd: _tagPhotos,
          chips: _people
              .map(
                (u) => _chip(
                  label: u.label,
                  imageUrl: u.imageUrl,
                  onRemove: () => setState(() => _people.remove(u)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  /// Writes the tags and the place. Shared by Save and by the per-photo
  /// tagger, which has to flush what is held here before it opens.
  Future<void> _persist(int userId) async {
    final tags = <TaggedEntity>[..._events, ..._vehicles, ..._people];

    // Anything that was on the post and is not in the lists now was
    // taken off, and has to be deleted by row id — adding the survivors
    // back would leave the removed ones exactly where they were.
    final kept = {
      for (final t in _events) 'event:${t.id}',
      for (final t in _vehicles) 'car:${t.id}',
      for (final t in _people) 'user:${t.id}',
    };

    final gone = _tagIds.entries.where((e) => !kept.contains(e.key)).toList();

    for (final entry in gone) {
      await PostsAPI.removePostTag(tagId: entry.value);
      _tagIds.remove(entry.key);
    }

    // Only the ones that are not already rows. Re-sending a tag the
    // post already has is harmless, but re-sending a PERSON tag would
    // move it to the first photo — _tagIds holds the ones loaded from
    // the post, which are the ones already positioned.
    final fresh = tags
        .where((t) => !_tagIds.containsKey('${t.type}:${t.id}'))
        .toList();

    if (fresh.isNotEmpty) {
      await PostsAPI.addTagsForPost(
        userId: userId,
        postId: widget.postId,
        tags: fresh,
      );
    }

    final location = _location;

    if (location != null) {
      await PostsAPI.setPostLocation(
        postId: widget.postId,
        name: location.title,
        latitude: location.latitude,
        longitude: location.longitude,
        // So the post joins to the venue rather than only naming it.
        kind: location.kind,
        placeId: location.id,
      );
    }
  }

  /// Opens the per-photo tagger, then re-reads what came back.
  ///
  /// It writes its own tags directly, so anything held here has to be
  /// saved FIRST or it would be overwritten by the reload — somebody
  /// who picked a venue and then tapped this would otherwise lose it.
  Future<void> _tagPhotos() async {
    final userId = _userId(context);

    setState(() => _saving = true);

    try {
      await _persist(userId);
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;

    setState(() => _saving = false);

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            PostPhotoTaggingScreen(postId: widget.postId, authorId: userId),
      ),
    );

    if (!mounted) return;

    await _loadExisting();
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String count,
    required VoidCallback onAdd,
    required List<Widget> chips,
    bool busy = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _goldSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(_gold),
                        ),
                      )
                    : Icon(icon, color: _gold, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count,
                      style: const TextStyle(color: _muted, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onAdd,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: _ink,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required VoidCallback onRemove,
    String? imageUrl,
    bool guessed = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            ClipOval(
              child: Image.network(
                imageUrl,
                width: 24,
                height: 24,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 7),
          ] else
            const SizedBox(width: 4),
          if (guessed) ...[
            // Says this was applied without being asked. A tag claiming
            // where somebody was should not look like one they chose.
            const Tooltip(
              message: 'Added automatically from your photo',
              child: Icon(Icons.auto_awesome, size: 14, color: _gold),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Color(0xFFD8D8D8),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 13,
                color: Color(0xFF5A5A5A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLocation() async {
    final chosen = await _openPicker<TagSuggestion>(
      title: 'Tag locations',
      hint: 'Search places or venues',
      options: _suggestions.locations,
      selected: {if (_location != null) _location!.id},
      single: true,
      labelOf: (s) => s.title,
      detailOf: (s) => s.detail,
      idOf: (s) => s.id,
      leadingOf: (s) =>
          const Icon(Icons.location_on_outlined, color: _gold, size: 20),
    );

    if (chosen == null || !mounted) return;

    setState(() {
      // Chosen by hand, so no longer a guess.
      _location = chosen.isEmpty ? null : chosen.first.copyWith(guessed: false);
    });
  }

  Future<void> _pickEvents() async {
    final chosen = await _openPicker<TagSuggestion>(
      title: 'Tag events',
      hint: 'Search events',
      // Anything already tagged is added to the list even when it is
      // nowhere near the photos. Without it, a tag the composer made —
      // an event in another county, say — is not an option, so it is
      // not in `chosen` when Done is tapped, and tapping Done would
      // silently delete it.
      options: _withHeld(
        _suggestions.events,
        _events,
        (t) => TagSuggestion(id: t.id, title: t.label, imageUrl: t.imageUrl),
      ),
      selected: _events.map((e) => e.id).toSet(),
      single: false,
      labelOf: (s) => s.title,
      detailOf: (s) => s.detail,
      idOf: (s) => s.id,
      leadingOf: (s) =>
          const Icon(Icons.calendar_today_outlined, color: _gold, size: 18),
    );

    if (chosen == null || !mounted) return;

    setState(() {
      // Chosen by hand, so no longer guesses.
      _guessedIds.removeAll(chosen.map((e) => e.id));

      _events
        ..clear()
        ..addAll(
          chosen.map((e) => _existing(_events, e.id) ?? _asTag(e, 'event')),
        );
    });
  }

  Future<void> _pickVehicles() async {
    final chosen = await _openPicker<_GarageVehicle>(
      title: 'Tag garage vehicles',
      hint: 'Search your garage',
      // Same reason, and it matters more here: TagEntitiesScreen can
      // tag ANY car by registration, including one that is in nobody's
      // garage — so a tagged car is often not in this list at all.
      options: _withHeld(
        _garage,
        _vehicles,
        (t) => _GarageVehicle(
          id: t.id,
          label: t.label,
          registration: t.registration,
          imageUrl: t.imageUrl,
        ),
      ),
      selected: _vehicles.map((v) => v.id).toSet(),
      single: false,
      labelOf: (v) => v.label,
      detailOf: (v) => v.detail,
      idOf: (v) => v.id,
      empty: _garageLoaded
          ? 'Nothing in your garage yet.'
          : 'Loading your garage…',
      leadingOf: (v) =>
          const Icon(Icons.directions_car_outlined, color: _gold, size: 20),
    );

    if (chosen == null || !mounted) return;

    setState(() {
      _vehicles
        ..clear()
        ..addAll(
          chosen.map(
            (v) =>
                _existing(_vehicles, v.id) ??
                TaggedEntity(
                  index: 0,
                  id: v.id,
                  type: 'car',
                  label: v.label,
                  imageUrl: v.imageUrl,
                  registration: v.registration,
                ),
          ),
        );
    });
  }

  /// [options] plus anything already tagged that is missing from them.
  ///
  /// A picker can only return what it was given, so an option that is
  /// not in the list cannot be kept — it would come back deselected and
  /// be dropped.
  List<T> _withHeld<T>(
    List<T> options,
    List<TaggedEntity> held,
    T Function(TaggedEntity) convert,
  ) {
    final ids = options.map(_idOfOption).toSet();

    return [
      ...options,
      for (final tag in held)
        if (!ids.contains(tag.id)) convert(tag),
    ];
  }

  String _idOfOption(dynamic option) {
    if (option is TagSuggestion) return option.id;
    if (option is _GarageVehicle) return option.id;
    return '';
  }

  /// The tag already held for this id, so re-picking it keeps whatever
  /// the composer put on it — a position on a photo, a media id — rather
  /// than replacing it with a flat one.
  TaggedEntity? _existing(List<TaggedEntity> held, String id) {
    for (final tag in held) {
      if (tag.id == id) return tag;
    }
    return null;
  }

  /// The shared bottom sheet. One list, one search box, one Done.
  ///
  /// Returns null when dismissed without Done, which has to mean "leave
  /// it as it was" — a swipe down is not a decision to clear anything.
  Future<List<T>?> _openPicker<T>({
    required String title,
    required String hint,
    required List<T> options,
    required Set<String> selected,
    required bool single,
    required String Function(T) labelOf,
    required String Function(T) detailOf,
    required String Function(T) idOf,
    required Widget Function(T) leadingOf,
    String empty = 'Nothing found near your photos.',
  }) {
    return showModalBottomSheet<List<T>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PickerSheet<T>(
        title: title,
        hint: hint,
        options: options,
        selected: selected,
        single: single,
        labelOf: labelOf,
        detailOf: detailOf,
        idOf: idOf,
        leadingOf: leadingOf,
        empty: empty,
      ),
    );
  }
}

/// One of the user's own cars, for the manual picker.
class _GarageVehicle {
  final String id;
  final String label;
  final String detail;
  final String registration;
  final String? imageUrl;

  const _GarageVehicle({
    required this.id,
    required this.label,
    this.detail = '',
    this.registration = '',
    this.imageUrl,
  });

  factory _GarageVehicle.fromMap(Map<String, dynamic> map) {
    final make = '${map['make'] ?? ''}'.trim();
    final model = '${map['model'] ?? ''}'.trim();
    final plate = '${map['registration'] ?? ''}'.trim();

    final name = [make, model].where((s) => s.isNotEmpty).join(' ');

    return _GarageVehicle(
      id: '${map['id'] ?? ''}',
      // The plate is what the chip shows in the design, falling back to
      // the car's name for one that has never had a registration.
      label: plate.isNotEmpty ? plate : name,
      detail: plate.isNotEmpty ? name : '${map['year'] ?? ''}'.trim(),
      registration: plate,
      imageUrl: (map['cover_photo'] == null || '${map['cover_photo']}'.isEmpty)
          ? null
          : '${map['cover_photo']}',
    );
  }
}

class _PickerSheet<T> extends StatefulWidget {
  final String title;
  final String hint;
  final List<T> options;
  final Set<String> selected;
  final bool single;
  final String Function(T) labelOf;
  final String Function(T) detailOf;
  final String Function(T) idOf;
  final Widget Function(T) leadingOf;
  final String empty;

  const _PickerSheet({
    required this.title,
    required this.hint,
    required this.options,
    required this.selected,
    required this.single,
    required this.labelOf,
    required this.detailOf,
    required this.idOf,
    required this.leadingOf,
    required this.empty,
  });

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFAE9159);

  late final Set<String> _selected = {...widget.selected};
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<T> get _shown {
    final query = _search.text.trim().toLowerCase();

    if (query.isEmpty) return widget.options;

    return widget.options
        .where(
          (o) =>
              widget.labelOf(o).toLowerCase().contains(query) ||
              widget.detailOf(o).toLowerCase().contains(query),
        )
        .toList();
  }

  void _done() {
    Navigator.of(context).pop(
      widget.options.where((o) => _selected.contains(widget.idOf(o))).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _done,
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFF2F2F2),
                      foregroundColor: _ink,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: const TextStyle(color: _muted, fontSize: 15),
                  prefixIcon: const Icon(Icons.search, color: _muted, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF4F4F4),
                  contentPadding: const EdgeInsets.symmetric(vertical: 2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          widget.empty,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted, fontSize: 15),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: controller,
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                        color: Color(0xFFEFEFEF),
                      ),
                      itemBuilder: (context, i) {
                        final option = shown[i];
                        final id = widget.idOf(option);
                        final on = _selected.contains(id);

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F4F4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(child: widget.leadingOf(option)),
                          ),
                          title: Text(
                            widget.labelOf(option),
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: widget.detailOf(option).isEmpty
                              ? null
                              : Text(
                                  widget.detailOf(option),
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 13.5,
                                  ),
                                ),
                          trailing: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: on ? _gold : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: on ? _gold : const Color(0xFFD5D5D5),
                                width: 1.5,
                              ),
                            ),
                            child: on
                                ? const Icon(
                                    Icons.check,
                                    size: 17,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          onTap: () => setState(() {
                            if (on) {
                              _selected.remove(id);
                              return;
                            }

                            // One location, many events and vehicles.
                            if (widget.single) _selected.clear();

                            _selected.add(id);
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
