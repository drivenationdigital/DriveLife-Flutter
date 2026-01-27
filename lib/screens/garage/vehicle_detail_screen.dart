import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/screens/garage/mods/add_mods_screen.dart';
import 'package:drivelife/services/qr_scanner.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
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

class VehicleDetailScreen extends StatefulWidget {
  final String garageId;

  const VehicleDetailScreen({super.key, required this.garageId});

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _vehicle;
  List<dynamic> _mods = [];
  bool _loading = true;
  bool _isFromCache = false; // ADD THIS
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Try to load from cache first
    final cached = _VehicleCache.get(widget.garageId);
    if (cached != null) {
      setState(() {
        _vehicle = cached;
        _loading = false;
        _isFromCache = true;
      });
    }

    _loadVehicle();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // UPDATE: _loadVehicle
  Future<void> _loadVehicle() async {
    final vehicle = await GarageAPI.getGarageById(widget.garageId);

    print(vehicle);
    final mods = await GarageAPI.getVehicleMods(widget.garageId);

    if (!mounted) return;

    if (vehicle != null) {
      _VehicleCache.put(widget.garageId, vehicle);
    }

    setState(() {
      _vehicle = vehicle;
      _mods = mods ?? [];
      _loading = false;
      _isFromCache = false;
    });
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
    final currentUserId = userProvider.user?['id']?.toString();

    if (currentUserId == null) return false;
    if (ownerId == null || ownerId != currentUserId) {
      return false;
    }

    return true;
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
            Expanded(
              // FULL WIDTH SPLIT
              child: ElevatedButton(
                onPressed: () async {
                  final result = await NavigationHelper.navigateTo(
                    context,
                    AddVehicleScreen(vehicle: _vehicle),
                  );

                  if (result != null) {
                    _VehicleCache.invalidate(widget.garageId);

                    if (result == 'deleted') {
                      // Vehicle was deleted, go back with 'deleted' result
                      Navigator.pop(context, 'deleted');
                    } else {
                      // Vehicle was updated, reload this screen
                      _loadVehicle();
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text(
                  'Edit Vehicle',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await NavigationHelper.navigateTo(
                    context,
                    AddModificationScreen(garageId: widget.garageId),
                  );

                  if (result != null) {
                    // Reload vehicle to get updated mods
                    _loadVehicle();
                  }
                },
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text(
                  'Add Mod',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16), // ADD SPACING BEFORE TABS
      ],
    );
  }

  // UPDATE: vehicle_detail_screen.dart - Fix tab structure

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
            IconButton(
              onPressed: () async {
                final result = await QrScannerService.showScanner(context);
                if (result != null && mounted) {
                  QrScannerService.handleScanResult(
                    context,
                    result,
                    onSuccess: (data) {
                      if (data['entity_type'] == 'profile') {
                        Navigator.pushNamed(
                          context,
                          '/view-profile',
                          arguments: {'userId': data['entity_id']},
                        );
                      } else if (data['entity_type'] == 'vehicle') {
                        Navigator.pushNamed(
                          context,
                          '/vehicle-detail',
                          arguments: {'garageId': data['entity_id'].toString()},
                        );
                      }
                    },
                  );
                }
              },
              icon: const Icon(Icons.qr_code, color: Colors.black),
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
            onPressed: () async {
              final result = await QrScannerService.showScanner(context);
              if (result != null && mounted) {
                QrScannerService.handleScanResult(
                  context,
                  result,
                  onSuccess: (data) {
                    if (data['entity_type'] == 'profile') {
                      Navigator.pushNamed(
                        context,
                        '/view-profile',
                        arguments: {'userId': data['entity_id']},
                      );
                    } else if (data['entity_type'] == 'vehicle') {
                      Navigator.pushNamed(
                        context,
                        '/vehicle-detail',
                        arguments: {'garageId': data['entity_id'].toString()},
                      );
                    }
                  },
                );
              }
            },
            icon: const Icon(Icons.qr_code, color: Colors.black),
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            ProfileAvatar(
                              imageUrl: _vehicle!['owner']?['profile_image'],
                              radius: 12,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Added By',
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
                          ],
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
                                'Since ${_vehicle!['owned_since']}',
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
                              _vehicle!['vehicle_bhp']?.toString() ?? '-',
                              'BHP',
                            ),
                            _buildStat(
                              _vehicle!['vehicle_062']?.toString() ?? '-',
                              '0-62',
                            ),
                            _buildStat(
                              _vehicle!['vehicle_top_speed'] != null
                                  ? '${_vehicle!['vehicle_top_speed']}mph'
                                  : '-',
                              'Top Speed',
                            ),
                            _buildStat(_mods.length.toString(), 'Mods'),
                          ],
                        ),
                        const SizedBox(height: 24),

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
                        Tab(text: 'Mods'),
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
            _GaragePostsGrid(garageId: widget.garageId, tagged: true),
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

// Posts grid widget
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

  const GarageModsList({
    super.key,
    required this.garageId,
    required this.mods,
    required this.onModsChanged,
    required this.isOwner,
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
          'No modifications added yet',
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
                    '${typeMods.length} mod${typeMods.length > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            ...typeMods.map((mod) => _buildModCard(mod, widget.isOwner)),
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
                child: Image.network(
                  mod['image'],
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
          ],
        ),
      ),
    );
  }
}
