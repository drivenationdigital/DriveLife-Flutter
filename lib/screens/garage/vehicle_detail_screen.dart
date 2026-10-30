import 'package:drivelife/widgets/media/tagged_photos_grid.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/garage_reminders_service.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/screens/garage/mods/add_mods_screen.dart';
import 'package:drivelife/api/cloudflare_images.dart';
import 'package:drivelife/screens/garage/vehicle_gallery.dart';
import 'package:image_picker/image_picker.dart';
import 'package:drivelife/screens/garage/view_reminders.dart';
import 'package:drivelife/widgets/image_viewer_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:drivelife/api/events_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drivelife/widgets/nav/dl_haptics.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../../api/garage_api.dart';
import 'package:url_launcher/url_launcher.dart';

/// The page's black, and the two tones that sit on it.
///
/// Top-level rather than statics on the State, because the chips, the mod
/// cards and the upgrade list are separate classes in this file and all
/// three need the same three values.
///
/// _pageBlack is the HERO's black, not the page's. The page below it is
/// white: an all-black vehicle screen read as a different app from every
/// other one, and the black belongs to the photographs rather than to
/// the screen they are on.
///
/// _panel is the dark fill the buttons under the gallery use — the like
/// pill and the three action chips, which the design draws dark on
/// white.
const Color _pageBlack = Color(0xFF0B0B0B);
const Color _panel = Color(0xFF161618);

/// A light surface for the things further down the white page: the
/// skeleton's bars, the grid's tiles, the mod cards.
const Color _lightPanel = Color(0xFFF4F4F4);
const Color _lightHairline = Color(0xFFE6E6E6);

/// Secondary text on white.
const Color _mutedText = Color(0xFF8A8A8A);

/// Public so AccountManager.switchAccount can empty it. What is cached
/// against a vehicle id is answered for whoever asked — is_liked, and
/// whether the owner-only actions show — so it does not survive a change
/// of who that is.
class VehicleCache {
  static final Map<String, Map<String, dynamic>> _cache = {};
  static final List<String> _lruKeys = [];
  static const int _maxSize = 10;

  static Map<String, dynamic>? get(String id) => _cache[id];

  /// Forget every vehicle.
  ///
  /// For an account switch. A vehicle id is the same for everybody, but
  /// what is cached against it is not: is_liked and the owner-only
  /// actions are answered for whoever asked.
  static void clearAll() {
    _cache.clear();
    _lruKeys.clear();
  }

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
    final cached = VehicleCache.get(widget.garageId);
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
      VehicleCache.put(widget.garageId, vehicle);
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
          // Grey on white. It was black behind grey blocks, which is a
          // loading state that looks like a different screen rather than
          // like the one arriving — the page it stands in for is white.
          backgroundColor: Colors.white,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(color: _lightPanel),
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
                    color: _lightPanel,
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
                          color: _lightPanel,
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
                    color: _lightPanel,
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
                            color: _lightPanel,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 16,
                          width: 40,
                          decoration: BoxDecoration(
                            color: _lightPanel,
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
        // The owner sees it and cannot press it. Visible because the
        // count lives here and the owner is the one person guaranteed
        // to care about it; inert because liking your own vehicle
        // inflates a leaderboard that ranks on a headcount of distinct
        // people. The server refuses it too — see dl_garage_like_toggle.
        onPressed: (_likeBusy || isVehiclePublisher()) ? null : _toggleLike,
        icon: Icon(
          liked ? Icons.favorite : Icons.favorite_border,
          size: 19,
          color: liked ? theme.primaryColor : Colors.white,
        ),
        // The count, which is the point of the button for everybody
        // except the person tapping it. The label used to be just
        // "Like"/"Liked" — so the number a vehicle had lived nowhere on
        // its own page, and the owner, who sees this button and cannot
        // tap it meaningfully, had nothing to read at all.
        label: Text(
          _likes == 0
              ? (liked ? 'Liked' : 'Like')
              : '${_formatLikes(_likes)} '
                    '${_likes == 1 ? 'like' : 'likes'}',
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: _panel,
          // Pinned, so the owner's inert button does not grey itself
          // out. It is not disabled in the "try again later" sense —
          // it is a count that happens not to be tappable, and the
          // default disabled styling makes it look broken.
          disabledForegroundColor: Colors.white,
          disabledBackgroundColor: _panel,
          side: BorderSide(
            // Gold once liked, and otherwise nothing. The pill is a
            // dark fill on a white page — it already has an edge, and
            // a light border around it reads as a ring.
            color: liked ? theme.primaryColor : Colors.transparent,
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  /// "1,284", or "48.2k" once there are enough that the digits stop
  /// being read individually.
  ///
  /// Thousands separated rather than abbreviated up to 10,000: on a
  /// vehicle's own page the exact number is the interesting part, and
  /// "1.3k" throws away the difference between 1,284 and 1,349. The
  /// leaderboard abbreviates earlier because it is comparing rows.
  static String _formatLikes(int n) {
    if (n >= 10000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}k';
    }

    final digits = '$n';
    final out = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }

    return out.toString();
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
        final cached = VehicleCache.get(widget.garageId);
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

  Future<void> _openEditor() async {
    final result = await NavigationHelper.navigateTo(
      context,
      AddVehicleScreen(vehicle: _vehicle),
    );

    if (result == null || !mounted) return;

    VehicleCache.invalidate(widget.garageId);

    if (result == 'deleted') {
      Navigator.pop(context, 'deleted');
    } else {
      _loadVehicle();
    }
  }

  Future<void> _openUpgrades() async {
    final result = await NavigationHelper.navigateTo(
      context,
      GarageModsPage(
        garageId: widget.garageId,
        mods: _mods,
        onModsChanged: _loadVehicle,
        isOwner: isVehiclePublisher(),
      ),
    );

    if (result != null) _loadVehicle();
  }

  Future<void> _openReminders() async {
    final result = await NavigationHelper.navigateTo(
      context,
      RemindersScreen(garageId: widget.garageId),
    );

    if (result != null) _loadVehicle();
  }

  /// Opens the cover photo full screen.
  ///
  /// The app's own ImageViewerScreen — the same black, zoomable page the
  /// gallery, the shop and the profile use — rather than a Dialog of its
  /// own, so pinching and dismissing work the way they do everywhere else.
  /// True while photographs are on their way to Cloudflare.
  bool _uploadingGallery = false;

  /// Add photographs to this vehicle's gallery.
  ///
  /// Uploaded one at a time rather than in parallel. Six at once on a
  /// phone connection is six requests competing for the same uplink,
  /// which is slower overall and gives no honest way to say how far
  /// along it is — and if one fails midway, the ones that landed are
  /// still recorded by the POST below.
  Future<void> _addGalleryPhotos() async {
    final picked = await ImagePicker().pickMultiImage(
      // Larger than the group avatars because these are drawn full
      // width. Cloudflare downscales to the variant either way; this is
      // about what goes up the phone's uplink.
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );

    if (picked.isEmpty || !mounted) return;

    setState(() => _uploadingGallery = true);

    final ids = <String>[];

    for (final file in picked) {
      final id = await CloudflareImages.uploadAndGetId(
        bytes: await file.readAsBytes(),
        fileName:
            'garage_${widget.garageId}_'
            '${DateTime.now().microsecondsSinceEpoch}.jpg',
      );

      if (id != null) ids.add(id);
    }

    if (!mounted) return;

    if (ids.isEmpty) {
      setState(() => _uploadingGallery = false);
      // Specifically the upload, not the recording. The two failed the
      // same way before — a photograph that reached Cloudflare but was
      // never attached looked identical to one that never left.
      _toast('Could not upload to Cloudflare.');
      return;
    }

    final gallery = await GarageAPI.addGalleryImages(
      garageId: widget.garageId,
      imageIds: ids,
    );

    if (!mounted) return;

    setState(() {
      _uploadingGallery = false;
      if (gallery != null) _vehicle?['gallery'] = gallery;
    });

    if (gallery == null) {
      final why = GarageAPI.lastGalleryError;
      _toast(
        why == null
            ? 'Uploaded, but the vehicle would not take them.'
            : 'Uploaded to Cloudflare, but not attached — $why',
      );
      return;
    }

    // Said plainly when some of them did not make it, rather than
    // letting the gallery quietly be shorter than expected.
    if (ids.length < picked.length) {
      _toast('Added ${ids.length} of ${picked.length} photos.');
    }
  }

  /// Take one photograph off the vehicle.
  ///
  /// Works for the cover too. The server decides what removing it
  /// means — clearing a column rather than deleting a row — and
  /// promotes the next photograph into its place, because every list in
  /// the app reads cover_photo and would otherwise draw a placeholder
  /// for a car that still has pictures.
  Future<void> _removeGalleryImage(String image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this photo?'),
        content: const Text('It will be deleted from this vehicle.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final gallery = await GarageAPI.removeGalleryPhoto(
      garageId: widget.garageId,
      image: image,
    );
    if (!mounted) return;

    if (gallery == null) {
      _toast('Could not remove that photo.');
      return;
    }

    setState(() => _vehicle?['gallery'] = gallery);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// The stored value of the photograph at [page].
  ///
  /// This is the token the server matches on, and it works for the
  /// cover as well as for a gallery row — which is the point of
  /// merging them. Page zero is removable now; it was not when the
  /// cover was prepended client-side and had no identity of its own.
  String? _photoTokenAt(int page) {
    final photos = _photos;
    if (page < 0 || page >= photos.length) return null;

    final token = '${photos[page]['image'] ?? ''}'.trim();
    return token.isEmpty ? null : token;
  }

  /// How tall the gallery is, not counting the status bar band above it.
  static const double _galleryHeight = 300;

  /// Every photograph of this vehicle, in order.
  ///
  /// The server merges them now — dl_garage_photos puts the cover first
  /// and flags it — so this no longer prepends anything. It used to,
  /// and doing both would show the cover twice.
  ///
  /// The cover still lives in its own column underneath; `is_cover` on
  /// the first entry is what says so, and what removing it has to
  /// consult.
  List<Map<String, dynamic>> get _photos =>
      ((_vehicle?['gallery'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) => '${row['url'] ?? ''}'.trim().isNotEmpty)
          .toList();

  /// Just the URLs, for the gallery widget.
  ///
  /// Never empty, so it always has one page to draw and the dots take
  /// themselves away at one.
  List<String> _galleryImages(String coverPhoto, bool hasCover) {
    final urls = _photos.map((row) => '${row['url']}'.trim()).toList();

    // Falls back to the cover column for a vehicle whose API response
    // predates the merge — an app that updated before the server did
    // would otherwise show no photograph at all.
    if (urls.isEmpty && hasCover && coverPhoto.trim().isNotEmpty) {
      return [coverPhoto.trim()];
    }

    return urls.isEmpty ? const [''] : urls;
  }

  /// Open the gallery full screen, on the one that was tapped.
  void _openGalleryAt(int index, String coverPhoto, bool hasCover) {
    final images = _galleryImages(
      coverPhoto,
      hasCover,
    ).where((url) => url.isNotEmpty).toList();

    if (images.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewerScreen(
          images: images,
          initialIndex: index.clamp(0, images.length - 1),
        ),
      ),
    );
  }

  /// The black the hero sits on.
  ///
  /// Named because two things have to agree on it exactly: the panel the
  /// name and stats sit on, and the last stop of the gradient over the
  /// photo. When they were two literals one of them was 0xCC and the other
  /// 0xFF, which drew a hard line across the bottom of every cover photo.
  /// Reading the same constant twice is cheaper than remembering to.
  /// The photograph, and the car's name and numbers on black beneath it.
  ///
  /// One widget rather than a SliverAppBar: the dark panel has to be part of
  /// the same block as the image so the gradient runs into it without a
  /// seam, and nothing here needs to collapse.
  Widget _buildHero(ThemeProvider theme, String coverPhoto, bool hasCover) {
    final top = MediaQuery.paddingOf(context).top;

    final make = '${_vehicle?['make'] ?? ''}'.trim();
    final model = '${_vehicle?['model'] ?? ''}'.trim();
    final variant = '${_vehicle?['variant'] ?? ''}'.trim();
    final name = [make, model, variant].where((p) => p.isNotEmpty).join(' ');

    final handle = '${_vehicle?['owner']?['username'] ?? ''}'.trim();
    final owned = _ownedSince;

    return ColoredBox(
      color: _pageBlack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The photographs, swiped. See VehicleGallery for why this
          // does not run under the status bar and why the fade is only
          // at the bottom.
          //
          // Wrapped in a Stack with the buttons so they float over it —
          // the gallery itself knows nothing about them.
          SizedBox(
            height: _galleryHeight + top,
            child: Stack(
              children: [
                VehicleGallery(
                  images: _galleryImages(coverPhoto, hasCover),
                  height: _galleryHeight,
                  fadeInto: _pageBlack,
                  onTap: (i) => _openGalleryAt(i, coverPhoto, hasCover),
                  // Only the owner, and only on a page that came from
                  // the gallery table — the cover is page zero and is
                  // changed by editing the vehicle, not by removing it
                  // here.
                  onLongPress: isVehiclePublisher()
                      ? (i) {
                          final token = _photoTokenAt(i);
                          if (token != null) _removeGalleryImage(token);
                        }
                      : null,
                ),

                // Add photos. Bottom left, under the dots rather than
                // beside them: the dots move as the gallery is swiped
                // and a button that shifts with them is a target that
                // will not hold still.
                if (isVehiclePublisher())
                  Positioned(
                    right: 16,
                    bottom: 56,
                    child: _AddPhotosButton(
                      busy: _uploadingGallery,
                      onTap: _addGalleryPhotos,
                      accent: theme.primaryColor,
                    ),
                  ),

                Positioned(
                  top: top + 8,
                  left: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _HeroButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.pop(context),
                        tooltip: 'Back',
                      ),
                      _HeroButton(
                        icon: Icons.ios_share_rounded,
                        onTap: _shareVehicle,
                        tooltip: 'Share vehicle',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Vehicle' : name,
                  style: const TextStyle(
                    color: Colors.white,
                    // Up, not down: the V of "Vauxhall Insignia" measures a
                    // 25pt cap on the mockup, which is a 35pt face. This is
                    // the one piece of type on these screens the app was
                    // drawing too small.
                    fontSize: 35,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),

                const SizedBox(height: 10),

                // No avatar. The handle is the link; a 24pt face beside it
                // added a second tap target for the same destination.
                Row(
                  children: [
                    if (handle.isNotEmpty)
                      GestureDetector(
                        onTap: _openOwnerProfile,
                        child: Text(
                          '@$handle',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (handle.isNotEmpty && owned != null)
                      Text(
                        '  ·  ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 13.5,
                        ),
                      ),
                    if (owned != null)
                      Text(
                        owned,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13.5,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 18),
                Divider(color: Colors.white.withValues(alpha: 0.14), height: 1),
                const SizedBox(height: 16),

                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _HeroStat(
                          label: 'POWER',
                          value: _statValue(_vehicle?['vehicle_bhp']),
                          unit: 'bhp',
                          accent: theme.primaryColor,
                        ),
                      ),
                      _heroDivider(),
                      Expanded(
                        child: _HeroStat(
                          label: 'TOP SPEED',
                          value: _statValue(_vehicle?['vehicle_top_speed']),
                          unit: 'mph',
                          accent: theme.primaryColor,
                        ),
                      ),
                      _heroDivider(),
                      Expanded(
                        child: _HeroStat(
                          label: 'UPGRADES',
                          value: '${_mods.length}',
                          unit: 'fitted',
                          accent: theme.primaryColor,
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

  Widget _heroDivider() => Container(
    width: 1,
    // 14, not 4. At 4 the rule sat almost against TOP SPEED's T and
    // UPGRADES' U, which read as the label being clipped rather than as
    // a column boundary. The gap has to be wider than the space inside
    // the words or the eye groups the rule with the text beside it.
    margin: const EdgeInsets.symmetric(horizontal: 14),
    color: Colors.white.withValues(alpha: 0.14),
  );

  /// A stat's number, or an em dash. Zero means "not recorded" on every one
  /// of these fields, so printing it would claim a 0bhp car.
  static String _statValue(dynamic raw) {
    final value = raw is num ? raw : num.tryParse('${raw ?? ''}');

    if (value == null || value == 0) return '—';

    return value == value.roundToDouble() ? '${value.round()}' : '$value';
  }

  /// "Owned since 2014", or null when there is no usable date.
  String? get _ownedSince {
    final raw = '${_vehicle?['owned_since'] ?? ''}'.trim();
    if (raw.isEmpty) return null;

    final year =
        DateTime.tryParse(raw)?.year ??
        int.tryParse(RegExp(r'\b(\d{4})\b').firstMatch(raw)?.group(1) ?? '');

    return year == null ? null : 'Owned since $year';
  }

  /// Edit, Upgrades, Reminders — the owner's row.
  ///
  /// Reminders is here because the bell that used to carry it in the header
  /// has gone. Worth knowing: that bell had an overdue badge, and this
  /// button does not. Nothing writes a notification when a reminder falls
  /// due, so until something does, an overdue reminder is only visible to
  /// somebody who opens this screen and taps through.
  Widget _buildVehicleActions(ThemeProvider theme) {
    if (!isVehiclePublisher()) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: _VehicleAction(
            icon: Icons.edit_outlined,
            label: 'Edit',
            accent: theme.primaryColor,
            onTap: _openEditor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _VehicleAction(
            icon: Icons.build_outlined,
            label: 'Upgrades',
            accent: theme.primaryColor,
            onTap: _openUpgrades,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _VehicleAction(
            icon: Icons.notifications_none_rounded,
            label: 'Reminders',
            accent: theme.primaryColor,
            onTap: _openReminders,
            // A dot, not the number the old bell carried.
            //
            // Kept deliberately against the design, because removing the
            // bell removed the ONLY warning anybody gets that a reminder is
            // due: nothing writes a notification when one falls due, so
            // without this an overdue MOT is visible only to somebody who
            // opens this screen and taps through on a hunch.
            //
            // Delete this line the day reminders reach the notification
            // feed — that is where it belongs, and the design is right that
            // a button should not be a status light.
            alert: _overdueOrDueCount > 0,
          ),
        ),
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
    // The page is black from the status bar down, so the clock and the
    // signal bars have to be drawn light or they vanish into it.
    //
    // AnnotatedRegion rather than setting it imperatively: it is scoped to
    // this route and puts the previous style back on the way out, so the
    // white screens behind this one do not inherit a white clock.
    //
    // Both platforms, opposite senses. iOS asks what the BACKGROUND is
    // (dark), Android asks what the ICONS should be (light); setting one
    // and not the other is the usual way this ends up right on one
    // platform and invisible on the other.
    // The loaded page puts a black hero under the clock and wants light
    // icons. The loading and not-found states are white and want dark
    // ones — annotating light for all three left the clock invisible
    // for as long as the vehicle took to arrive.
    final heroOnScreen = !(_loading && !_isFromCache) && _vehicle != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: heroOnScreen
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: heroOnScreen ? Brightness.dark : Brightness.light,
      ),
      child: _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_loading && !_isFromCache) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF111111)),
            onPressed: () => Navigator.pop(context),
          ),
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
            icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF111111)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text('Vehicle not found', style: TextStyle(color: _mutedText)),
        ),
      );
    }

    final coverPhoto = _vehicle!['cover_photo'];
    final hasCoverPhoto = coverPhoto != null && coverPhoto.isNotEmpty;

    return Scaffold(
      // White below the hero. The all-black read as a different app
      // from every other screen; the black is the hero's, not the
      // page's.
      backgroundColor: Colors.white,
      // No app bar. The photograph is the page's identity, and a white bar
      // with a logo on it above a full-bleed cover is two headers arguing.
      // Back and share float on the image instead.
      //
      // The reminders bell that used to live up here has gone: reminders
      // are one of the three buttons below now. Its overdue badge was the
      // only warning anybody got, so see the note on _buildVehicleActions.
      extendBodyBehindAppBar: true,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: _buildHero(theme, coverPhoto, hasCoverPhoto),
            ),

            SliverToBoxAdapter(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                    child: Column(
                      children: [
                        // Everyone sees it, the owner too. Hiding it from
                        // the owner meant the like COUNT disappeared along
                        // with the button — the one person guaranteed to
                        // care how many a vehicle has was the only one who
                        // could not see it.
                        _buildLikeButton(theme),
                        const SizedBox(height: 12),
                        _buildVehicleActions(theme),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Tabs
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabController,
                      labelColor: const Color(0xFF111111),
                      unselectedLabelColor: Colors.grey.shade500,
                      // The rule the design draws under the row. It
                      // was transparent — hidden deliberately while this
                      // page was black, where a grey line across it
                      // would have read as a seam. On white it is what
                      // separates the tabs from the grid beneath them,
                      // and the gold indicator needs something to sit
                      // on or it floats.
                      dividerColor: const Color(0xFFEDEDED),
                      dividerHeight: 1,
                      indicatorColor: const Color(0xFFD5B56B),
                      // Full tab width, not label width. Material 3
                      // defaults indicatorSize to `label`, so the bar
                      // hugged the word and three tabs of different
                      // lengths gave three different-sized indicators —
                      // which reads as a measurement rather than as a
                      // selection. `tab` is the Material 2 default and
                      // what the design draws.
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorWeight: 3,
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
                Icon(Icons.lock_outline, size: 40, color: Colors.grey.shade500),
                const SizedBox(height: 14),
                Text(
                  'Tagging is off for this vehicle',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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
                    color: _mutedText,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Center(
        child: Text('No tagged posts', style: TextStyle(color: _mutedText)),
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
                      color: _lightPanel,
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
              style: TextStyle(color: _mutedText),
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
                color: _lightPanel,
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
          style: TextStyle(color: _mutedText),
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
                      color: Color(0xFF111111),
                    ),
                  ),
                  Text(
                    '${typeMods.length} upgrade${typeMods.length > 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 14, color: _mutedText),
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
          color: _lightPanel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _lightHairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mod['title'] ?? '',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111111),
              ),
            ),
            if (mod['description'] != null &&
                mod['description'].isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                mod['description'],
                style: const TextStyle(fontSize: 14, color: _mutedText),
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
                    color: _lightPanel,
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
                    color: _mutedText,
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
    // White, following GarageModsList — whose cards went light again
    // when the vehicle page did.
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF111111)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Upgrades',
          style: TextStyle(
            color: Color(0xFF111111),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF111111)),
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

/// A round translucent button floating on the cover photo.
class _HeroButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _HeroButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      // Dark rather than light: the photograph behind could be anything,
      // and white-on-light is the pair that disappears.
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// One of the three numbers under the car's name.
class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color accent;

  const _HeroStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: accent,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        // Baseline-aligned, so the unit sits on the number's feet rather
        // than floating beside its middle.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  // 25, from a 17.8pt figure height on "710".
                  fontSize: 25,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Text(
              unit,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Edit / Upgrades / Reminders.
class _VehicleAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  /// Draws a dot on the icon. See the note at the Reminders call site.
  final bool alert;

  const _VehicleAction({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      // Dark, as drawn. A relight pass turned this light and left the
      // label white, which made Edit, Upgrades and Reminders invisible —
      // a fill and the text on it are one decision and have to move
      // together.
      color: _panel,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 16, color: accent),
                  if (alert)
                    Positioned(
                      top: -2,
                      right: -3,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE53935),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    // 14, from 14.5. The three buttons are Expanded and
                    // so share the width equally, which means the
                    // longest label decides how cramped all three look
                    // — and "Reminders" is nine characters against
                    // "Edit"'s four. Shaving the type, the icon and the
                    // gap between them gives it about 10pt a side
                    // instead of 8.
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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

/// "Add photos", over the gallery, for the vehicle's owner.
///
/// A chip rather than a bare icon: the gesture is not guessable from a
/// plus on a photograph, and this is the only way into the gallery from
/// the vehicle's own page.
class _AddPhotosButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  final Color accent;

  const _AddPhotosButton({
    required this.busy,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Not while an upload is running. Tapping again would start a
        // second picker over the first batch, and the two would race to
        // write the same gallery.
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                )
              else
                Icon(Icons.add_a_photo_outlined, size: 14, color: accent),
              const SizedBox(width: 7),
              Text(
                busy ? 'Uploading' : 'Add photos',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
