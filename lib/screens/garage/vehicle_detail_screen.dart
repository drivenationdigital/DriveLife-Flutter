import 'package:drivelife/widgets/media/tagged_photos_grid.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/garage_reminders_service.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/screens/garage/mods/add_mods_screen.dart';
import 'package:drivelife/screens/garage/view_reminders.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/widgets/nav/dl_haptics.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../../api/garage_api.dart';
import '../../widgets/profile/profile_avatar.dart';
import 'package:url_launcher/url_launcher.dart';

class _VehicleCache {
  static final Map<String, Map<String, dynamic>> _cache = {};
  static final List<String> _lruKeys = [];
  static const int _maxSize = 10;

  static Map<String, dynamic>? get(String id) => _cache[id];

  static void put(String id, Map<String, dynamic> data) {
    if (_cache.containsKey(id)) {
      _lruKeys.remove(id);
    } else if (_lruKeys.length >= _maxSize) {
      final oldest = _lruKeys.removeAt(0);
      _cache.remove(oldest);
    }
    _cache[id] = data;
    _lruKeys.add(id);
  }

  static void invalidate(String id) {
    _cache.remove(id);
    _lruKeys.remove(id);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Expanded(
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          // Prevents overflow on small screens
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class VehicleDetailScreen extends StatefulWidget {
  final String garageId;

  const VehicleDetailScreen({super.key, required this.garageId});

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _vehicle;

  /// Whether this person has pressed like, and how many people like it.
  ///
  /// Held rather than read from _vehicle on every build, because the toggle
  /// moves them before the server has answered.
  bool _liked = false;
  int _likes = 0;
  bool _likeBusy = false;
  List<dynamic> _mods = [];
  bool _loading = true;
  bool _isFromCache = false;
  late TabController _tabController;
  int _overdueOrDueCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    attachTabHaptics(_tabController);

    // Try to load from cache first
    final cached = _VehicleCache.get(widget.garageId);
    if (cached != null) {
      setState(() {
        _vehicle = cached;
        _readLikes(cached);
        _loading = false;
        _isFromCache = true;
      });
    }

    _loadVehicle();
    _loadReminderBadge();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Seeds the like state from a loaded vehicle.
  ///
  /// Only while no toggle is in flight: the optimistic flip has already
  /// moved these, and a response arriving from the cache or a refresh in
  /// between would snap the button back under the user's finger.
  void _readLikes(Map<String, dynamic>? vehicle) {
    if (vehicle == null || _likeBusy) return;

    _liked = vehicle['is_liked'] == true;

    final raw = vehicle['likes'];
    _likes = raw is int ? raw : int.tryParse('$raw') ?? 0;
  }

  Future<void> _loadVehicle() async {
    final vehicle = await GarageAPI.getGarageById(widget.garageId);
    final mods = await GarageAPI.getVehicleMods(widget.garageId);
    if (mods != null) {
      _preloadModImages(mods);
    }
    if (!mounted) return;

    if (vehicle != null) {
      _VehicleCache.put(widget.garageId, vehicle);
    }

    setState(() {
      _vehicle = vehicle;
      _mods = mods ?? [];
      _loading = false;
      _isFromCache = false;
      _readLikes(vehicle);
    });
  }

  void _preloadModImages(List<dynamic> mods) {
    for (final mod in mods) {
      if (mod['image'] != null && mod['image'].isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(mod['image']), context);
      }
    }
  }

  Widget _buildSkeleton() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 270,
          pinned: true,
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(color: Colors.grey.shade300),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  height: 30,
                  width: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                    (i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Container(
                        height: 28,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    4,
                    (i) => Column(
                      children: [
                        Container(
                          height: 24,
                          width: 60,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 16,
                          width: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool isVehiclePublisher() {
    final ownerId = _vehicle?['owner_id']?.toString();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUserId = userProvider.user?.id.toString();

    if (currentUserId == null) return false;
    if (ownerId == null || ownerId != currentUserId) {
      return false;
    }

    return true;
  }

  /// Shares this vehicle.
  ///
  /// Same shape as the post, event, venue and gallery links the app already
  /// sends — `/vehicle/:id` — which DeepLinkHandler routes back to this
  /// screen.
  void _shareVehicle() {
    final vehicle = _vehicle;

    final registration = '${vehicle?['registration'] ?? ''}'.trim();
    final make = '${vehicle?['make'] ?? ''}'.trim();
    final model = '${vehicle?['model'] ?? ''}'.trim();

    // The car, not the plate. A registration is what the vehicle is to the
    // DVLA; the make and model is what it is to the person being sent it.
    final name = [make, model].where((s) => s.isNotEmpty).join(' ');
    final title = name.isNotEmpty
        ? name
        : (registration.isNotEmpty ? registration : 'a vehicle');

    final url =
        'https://app.mydrivelife.com/vehicle/${widget.garageId}?ref=share';

    SharePlus.instance.share(
      ShareParams(text: '$title on DriveLife\n$url', subject: title),
    );
  }

  /// Like this vehicle.
  ///
  /// Shown to everyone including the owner: liking your own car is harmless
  /// and hiding the control makes the row jump about depending on whose
  /// page you are on.
  ///
  /// Says what pressing it does, and deliberately carries no count.
  ///
  /// The count is the number of PEOPLE who like this car by any route —
  /// pressing the button, or liking a post of it. So somebody who had
  /// already liked a photo of this car is already counted, and pressing
  /// Like does not move the total by one. It moved, optimistically, and
  /// then snapped back when the server answered with the same number: a
  /// button that visibly undoes itself.
  ///
  /// That is much more likely on somebody else's car than your own, which
  /// is why it looked like a bug that only affected other people's
  /// vehicles. The total is in the stats row instead, where it reads as a
  /// fact about the car rather than a tally of this button.
  Widget _buildLikeButton(ThemeProvider theme) {
    final liked = _liked;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _likeBusy ? null : _toggleLike,
        icon: Icon(
          liked ? Icons.favorite : Icons.favorite_border,
          size: 19,
          color: liked ? theme.primaryColor : theme.textColor,
        ),
        label: Text(
          liked ? 'Liked' : 'Like',
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.textColor,
          side: BorderSide(
            color: liked ? theme.primaryColor : theme.dividerColor,
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Future<void> _toggleLike() async {
    // Optimistic. A like is cheap and reversible, and waiting a round trip
    // to see it register is the difference between a button that feels
    // connected and one that feels broken.
    final wasLiked = _liked;
    final wasLikes = _likes;

    setState(() {
      _liked = !wasLiked;
      _likes = (wasLikes + (wasLiked ? -1 : 1)).clamp(0, 1 << 30);
      _likeBusy = true;
    });

    final result = await GarageAPI.toggleVehicleLike(widget.garageId);

    if (!mounted) return;

    setState(() {
      _likeBusy = false;

      if (result == null) {
        // Put it back. Null is "the call failed", which is not the same as
        // a successful unlike.
        _liked = wasLiked;
        _likes = wasLikes;
      } else {
        _liked = result.liked;
        _likes = result.likes;

        // The cached copy still holds what the server said when the page
        // loaded. Leaving it stale means coming back to this vehicle shows
        // the button un-pressed until the network answers — and tapping it
        // in that window un-likes instead of liking.
        final cached = _VehicleCache.get(widget.garageId);
        if (cached != null) {
          cached['is_liked'] = result.liked;
          cached['likes'] = result.likes;
        }
      }
    });

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save that. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildOwnerActions(ThemeProvider theme) {
    final isOwner = isVehiclePublisher();

    if (!isOwner) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              final associationType = isOwner ? 'garage' : 'car';

              if (_vehicle == null) return;

              // Create the label (registration or make/model)
              String label;
              if (_vehicle?['registration'] != null &&
                  _vehicle?['registration'].isNotEmpty) {
                label = _vehicle?['registration'];
              } else {
                label = '${_vehicle?['make']} ${_vehicle?['model']}';
              }

              // Navigate to create post screen with arguments
              Navigator.pushNamed(
                context,
                '/create-post', // or whatever your route name is
                arguments: {
                  'association_id': _vehicle?['id'], // or garageId
                  'association_type': associationType,
                  'association_label': label,
                },
              );
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              backgroundColor: theme.secondaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              'Add Post',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _ActionButton(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onPressed: () async {
                final result = await NavigationHelper.navigateTo(
                  context,
                  AddVehicleScreen(vehicle: _vehicle),
                );
                if (result != null) {
                  _VehicleCache.invalidate(widget.garageId);
                  if (result == 'deleted') {
                    Navigator.pop(context, 'deleted');
                  } else {
                    _loadVehicle();
                  }
                }
              },
            ),
            const SizedBox(width: 8),
            _ActionButton(
              icon: Icons.build_outlined,
              label: 'Upgrades',
              onPressed: () async {
                final result = await NavigationHelper.navigateTo(
                  context,
                  GarageModsPage(
                    garageId: widget.garageId,
                    mods: _mods,
                    onModsChanged: _loadVehicle,
                    isOwner: isOwner,
                  ),
                );
                if (result != null) _loadVehicle();
              },
            ),
            const SizedBox(width: 8),
            _ActionButton(
              icon: Icons.notifications_outlined,
              label: 'Reminders',
              onPressed: () async {
                final result = await NavigationHelper.navigateTo(
                  context,
                  RemindersScreen(garageId: widget.garageId),
                );
                if (result != null) _loadVehicle();
              },
            ),
          ],
        ),
        const SizedBox(height: 16), // ADD SPACING BEFORE TABS
      ],
    );
  }

  String formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr; // Return original if parsing fails
    }
  }

  // Call this inside _loadVehicle() after loading reminders,
  // OR as a separate lightweight fetch
  Future<void> _loadReminderBadge() async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;

    try {
      final reminders = await ReminderApiService.fetchReminders(
        widget.garageId,
      );

      final today = DateTime.now();

      final count = reminders.where((r) {
        final date = DateTime.tryParse(r['reminder_date'] ?? '');
        if (date == null) return false;
        final daysUntil = date.difference(today).inDays;
        // Badge if overdue OR due within 8 days and notif not yet sent
        return daysUntil <= 8;
      }).length;

      if (!mounted) return;
      setState(() => _overdueOrDueCount = count);
    } catch (_) {
      // Badge is non-critical — fail silently
    }
  }

  /// Opens the profile of whoever owns this vehicle.
  ///
  /// The id comes off the vehicle row, not the owner block: the API builds
  /// that block from name, handle and avatar and never puts an id in it, so
  /// reading one from there would always be null and every tap would open
  /// nothing.
  void _openOwnerProfile() {
    final owner = _vehicle?['owner'];
    if (owner is! Map) return;

    final userId = int.tryParse('${_vehicle?['owner_id'] ?? ''}');
    final username = '${owner['username'] ?? ''}'.trim();

    // The profile screen can find somebody by either, so one is enough.
    if (userId == null && username.isEmpty) return;

    Navigator.pushNamed(
      context,
      AppRoutes.viewProfile,
      arguments: {'userId': userId, 'username': username},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_loading && !_isFromCache) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: Image.asset('assets/logo-dark.png', height: 18),
          actions: [
            if (isVehiclePublisher())
              IconButton(
                icon: Icon(
                  Icons.notifications_outlined,
                  color: theme.primaryColor,
                ),
                onPressed: () async {
                  final result = await Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          RemindersScreen(garageId: widget.garageId),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return SlideTransition(
                              position:
                                  Tween<Offset>(
                                    begin: const Offset(1.0, 0.0),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutCubic,
                                    ),
                                  ),
                              child: child,
                            );
                          },
                      transitionDuration: const Duration(milliseconds: 300),
                    ),
                  );

                  if (result != null) _loadVehicle();
                },
              ),
          ],
        ),
        body: _buildSkeleton(),
      );
    }

    if (_vehicle == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: Image.asset('assets/logo-dark.png', height: 18),
        ),
        body: const Center(child: Text('Vehicle not found')),
      );
    }

    final coverPhoto = _vehicle!['cover_photo'];
    final hasCoverPhoto = coverPhoto != null && coverPhoto.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share, color: Colors.black),
            tooltip: 'Share vehicle',
            onPressed: _shareVehicle,
          ),
          if (isVehiclePublisher())
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: Icon(Icons.notifications_outlined, color: Colors.black),
                  onPressed: () async {
                    final result = await Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            RemindersScreen(garageId: widget.garageId),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              return SlideTransition(
                                position:
                                    Tween<Offset>(
                                      begin: const Offset(1.0, 0.0),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
                                child: child,
                              );
                            },
                        transitionDuration: const Duration(milliseconds: 300),
                      ),
                    );
                    if (result != null) {
                      _loadVehicle();
                      _loadReminderBadge(); // refresh badge after returning
                    }
                  },
                ),
                if (_overdueOrDueCount > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IgnorePointer(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _overdueOrDueCount > 9 ? '9+' : '$_overdueOrDueCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // Cover photo
            SliverAppBar(
              expandedHeight: 270,
              pinned: false,
              automaticallyImplyLeading: false,
              backgroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasCoverPhoto)
                      Image.network(
                        coverPhoto,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: Colors.grey.shade300),
                      )
                    else
                      Container(color: Colors.grey.shade300),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: Material(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _openOwnerProfile,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ProfileAvatar(
                                  imageUrl:
                                      _vehicle!['owner']?['profile_image'],
                                  radius: 12,
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      // Whose car it is, not who typed it in.
                                      'Owned By',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      '@${_vehicle!['owner']?['username'] ?? 'user'}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: Colors.white70,
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
            ),

            // Vehicle info and tabs
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Vehicle name with variant
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '${_vehicle!['make']} ${_vehicle!['model']}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              if (_vehicle!['variant'] != null &&
                                  _vehicle!['variant'].isNotEmpty)
                                TextSpan(
                                  text: ' ${_vehicle!['variant']}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Registration, Colour, Owned Since
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            if (_vehicle!['registration'] != null &&
                                _vehicle!['registration'].isNotEmpty)
                              _buildInfoChip(
                                Icons.pin,
                                _vehicle!['registration'],
                              ),
                            if (_vehicle!['colour'] != null &&
                                _vehicle!['colour'].isNotEmpty)
                              _buildInfoChip(
                                Icons.palette,
                                _vehicle!['colour'],
                              ),
                            if (_vehicle!['owned_since'] != null &&
                                _vehicle!['owned_since'].isNotEmpty)
                              _buildInfoChip(
                                Icons.calendar_today,
                                'Since ${formatDate(_vehicle!['owned_since'])}',
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Description
                        if (_vehicle!['short_description'] != null &&
                            _vehicle!['short_description'].isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _vehicle!['short_description'],
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        // Stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStat(
                              _vehicle!['vehicle_bhp'] != 0
                                  ? _vehicle!['vehicle_bhp'].toString()
                                  : '-',
                              'BHP',
                            ),
                            _buildStat(
                              _vehicle!['vehicle_062'] != 0
                                  ? _vehicle!['vehicle_062'].toString()
                                  : '-',
                              '0-62',
                            ),
                            _buildStat(
                              _vehicle!['vehicle_top_speed'] != 0
                                  ? '${_vehicle!['vehicle_top_speed']}mph'
                                  : '-',
                              'Top Speed',
                            ),
                            _buildStat(_mods.length.toString(), 'Upgrades'),
                            _buildStat('$_likes', 'Likes'),
                          ],
                        ),
                        const SizedBox(height: 20),

                        _buildLikeButton(theme),

                        const SizedBox(height: 20),

                        _buildOwnerActions(theme),
                      ],
                    ),
                  ),

                  // Tabs
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabController,
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: const Color(0xFFD5B56B),
                      tabs: const [
                        Tab(text: 'Posts'),
                        Tab(text: 'Upgrades'),
                        Tab(text: 'Tags'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _GaragePostsGrid(garageId: widget.garageId, tagged: false),
            GarageModsList(
              garageId: widget.garageId,
              mods: _mods,
              onModsChanged: _loadVehicle,
              isOwner: isVehiclePublisher(),
            ),
            _GarageTaggedTab(
              garageId: widget.garageId,
              taggingOff: _vehicle?['allow_tagging']?.toString() == '0',
              isOwner: isVehiclePublisher(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Tagged tab on a vehicle: galleries it appears in, then tagged posts.
///
/// Galleries are a separate fetch because they are a different thing from a
/// post — somebody else's set of photos that happens to contain this car,
/// usually because the scan read its plate.
class _GarageTaggedTab extends StatefulWidget {
  final String garageId;

  /// Whether the owner has turned off tagging for this vehicle.
  ///
  /// This tab is then permanently empty by design, and "No tagged posts" reads
  /// as nobody having photographed the car rather than as a setting doing
  /// exactly what it was asked to.
  final bool taggingOff;

  /// Only the owner is told why. To anybody else the tab is simply empty —
  /// whether a stranger has opted out of tagging is not their business.
  final bool isOwner;

  const _GarageTaggedTab({
    required this.garageId,
    this.taggingOff = false,
    this.isOwner = false,
  });

  @override
  State<_GarageTaggedTab> createState() => _GarageTaggedTabState();
}

class _GarageTaggedTabState extends State<_GarageTaggedTab> {
  List<Map<String, dynamic>> _taggedPhotos = const [];
  List<dynamic> _posts = const [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final garageId = int.tryParse(widget.garageId) ?? 0;

    // Both at once: neither depends on the other, and the tab should not wait
    // for two round trips in series.
    final results = await Future.wait([
      GarageAPI.getPostsForGarage(
        widget.garageId,
        tagged: true,
      ).catchError((_) => <String, dynamic>{}),
      garageId > 0
          ? EventsAPI.fetchTaggedPhotos(
              taggedGarageId: garageId,
            ).catchError((_) => <Map<String, dynamic>>[])
          : Future.value(<Map<String, dynamic>>[]),
    ]);

    if (!mounted) return;

    final postData = results[0] as Map<String, dynamic>?;

    setState(() {
      _posts = (postData?['data'] as List<dynamic>?) ?? const [];
      _taggedPhotos = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    if (_posts.isEmpty && _taggedPhotos.isEmpty) {
      if (widget.taggingOff && widget.isOwner) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 14),
                Text(
                  'Tagging is off for this vehicle',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nobody can tag it, and we will not look for its '
                  'registration in anyone else\'s photos. Turn tagging on in '
                  'Edit vehicle to start being told when it turns up.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Center(
        child: Text(
          'No tagged posts',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return RefreshIndicator(
      color: theme.primaryColor,
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          // One grid for both, and no headings. Being tagged is one idea;
          // two sections made a gallery photo of this car look like a
          // different kind of thing from a post of it, and left a half-empty
          // row between them whenever the first count was not a multiple of
          // three. The small gallery mark on a tile is what tells them apart.
          if (_taggedPhotos.isNotEmpty || _posts.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.all(2),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index < _taggedPhotos.length) {
                    return TaggedPhotoTile(photo: _taggedPhotos[index]);
                  }

                  final post = _posts[index - _taggedPhotos.length];
                  final media = post['media'];
                  String? imageUrl;

                  if (media != null && media is List && media.isNotEmpty) {
                    imageUrl = media[0]['media_url'];
                  }

                  return GestureDetector(
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/post-detail',
                      arguments: {'postId': post['id'].toString()},
                    ),
                    child: Container(
                      color: Colors.grey.shade300,
                      child: imageUrl != null
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.image, color: Colors.grey),
                            )
                          : const Icon(Icons.image, color: Colors.grey),
                    ),
                  );
                }, childCount: _taggedPhotos.length + _posts.length),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _GaragePostsGrid extends StatelessWidget {
  final String garageId;
  final bool tagged;

  const _GaragePostsGrid({required this.garageId, required this.tagged});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return FutureBuilder<Map<String, dynamic>?>(
      future: GarageAPI.getPostsForGarage(garageId, tagged: tagged),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: theme.primaryColor),
          );
        }

        final data = snapshot.data;
        if (data == null ||
            data['data'] == null ||
            (data['data'] as List).isEmpty) {
          return Center(
            child: Text(
              tagged ? 'No tagged posts' : 'No posts',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }

        final posts = data['data'] as List<dynamic>;
        return GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            final media = post['media'];
            String? imageUrl;

            if (media != null && media is List && media.isNotEmpty) {
              imageUrl = media[0]['media_url'];
            }

            return GestureDetector(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/post-detail',
                  arguments: {'postId': post['id'].toString()},
                );
              },
              child: Container(
                color: Colors.grey.shade300,
                child: imageUrl != null
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.image, color: Colors.grey),
                      )
                    : const Icon(Icons.image, color: Colors.grey),
              ),
            );
          },
        );
      },
    );
  }
}

class GarageModsList extends StatefulWidget {
  final String garageId;
  final List<dynamic> mods;
  final VoidCallback onModsChanged;
  final bool isOwner;
  final bool showEditActions;

  const GarageModsList({
    super.key,
    required this.garageId,
    required this.mods,
    required this.onModsChanged,
    required this.isOwner,
    this.showEditActions = false,
  });

  @override
  State<GarageModsList> createState() => _GarageModsListState();
}

class _GarageModsListState extends State<GarageModsList> {
  @override
  Widget build(BuildContext context) {
    if (widget.mods.isEmpty) {
      return Center(
        child: Text(
          'No upgrades added yet',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    // Group mods by type
    final grouped = <String, List<dynamic>>{};
    for (final mod in widget.mods) {
      final type = mod['mod_type'] ?? 'Other';
      grouped.putIfAbsent(type, () => []).add(mod);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final type = grouped.keys.elementAt(index);
        final typeMods = grouped[type]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    type[0].toUpperCase() + type.substring(1),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    '${typeMods.length} upgrade${typeMods.length > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            ...typeMods.map(
              (mod) =>
                  _buildModCard(mod, widget.isOwner && widget.showEditActions),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildModCard(Map<String, dynamic> mod, bool isOwner) {
    final hasImage = mod['image'] != null && mod['image'].isNotEmpty;

    return GestureDetector(
      onTap: () async {
        // IF GARAGE OWNER, ALLOW EDITING
        if (!isOwner) return;

        final result = await NavigationHelper.navigateTo(
          context,
          AddModificationScreen(garageId: widget.garageId, mod: mod),
        );

        if (result != null) {
          widget.onModsChanged();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mod['title'] ?? '',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            if (mod['description'] != null &&
                mod['description'].isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                mod['description'],
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ],
            if (hasImage) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: mod['image'],
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 120,
                    color: Colors.grey.shade100,
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              ),
            ],
            if (mod['product_link'] != null &&
                mod['product_link'].isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final url = Uri.parse(mod['product_link']);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: Row(
                  children: [
                    Icon(Icons.link, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Product Link',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (isOwner && widget.showEditActions) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Tap to edit',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class GarageModsPage extends StatefulWidget {
  final String garageId;
  final List<dynamic> mods;
  final Future<void> Function() onModsChanged;
  final bool isOwner;

  const GarageModsPage({
    super.key,
    required this.garageId,
    required this.mods,
    required this.onModsChanged,
    required this.isOwner,
  });

  @override
  State<GarageModsPage> createState() => _GarageModsPageState();
}

class _GarageModsPageState extends State<GarageModsPage> {
  void _openAddScreen() async {
    final result = await NavigationHelper.navigateTo(
      context,
      AddModificationScreen(garageId: widget.garageId),
    );

    if (result != null) {
      await widget.onModsChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Upgrades',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: Colors.black),
            onPressed: _openAddScreen,
          ),
        ],
      ),
      body: GarageModsList(
        garageId: widget.garageId,
        mods: widget.mods,
        onModsChanged: widget.onModsChanged,
        isOwner: widget.isOwner,
        showEditActions: true, // Hide edit actions in this full-page view
      ),
    );
  }
}
