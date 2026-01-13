import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/garage_api.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_post_grid.dart';

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
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadVehicle();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadVehicle() async {
    final vehicle = await GarageAPI.getGarageById(widget.garageId);
    final mods = await GarageAPI.getVehicleMods(widget.garageId);

    if (!mounted) return;

    setState(() {
      _vehicle = vehicle;
      _mods = mods ?? [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    if (_vehicle == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: Text('Vehicle not found')),
      );
    }

    final coverPhoto = _vehicle!['cover_photo'];
    final hasCoverPhoto = coverPhoto != null && coverPhoto.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // Cover photo with back button
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {},
              ),
            ],
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
                  // Gradient overlay
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
                  // Added by badge
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

          // Vehicle info
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Vehicle name with variant
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${_vehicle!['make']} ${_vehicle!['model']}',
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
                        _buildInfoChip(Icons.pin, _vehicle!['registration']),
                      if (_vehicle!['colour'] != null &&
                          _vehicle!['colour'].isNotEmpty)
                        _buildInfoChip(Icons.palette, _vehicle!['colour']),
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

                  // Tabs
                  TabBar(
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
                ],
              ),
            ),
          ),

          // Tab content
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _GaragePostsGrid(garageId: widget.garageId, tagged: false),
                _GarageModsList(garageId: widget.garageId, mods: _mods),
                _GaragePostsGrid(garageId: widget.garageId, tagged: true),
              ],
            ),
          ),
        ],
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

// Mods list widget
class _GarageModsList extends StatelessWidget {
  final String garageId;
  final List<dynamic> mods;

  const _GarageModsList({required this.garageId, required this.mods});

  @override
  Widget build(BuildContext context) {
    if (mods.isEmpty) {
      return Center(
        child: Text(
          'No modifications added yet',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    // Group mods by type
    final grouped = <String, List<dynamic>>{};
    for (final mod in mods) {
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
            ...typeMods.map((mod) => _buildModCard(mod)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildModCard(Map<String, dynamic> mod) {
    final hasImage = mod['image'] != null && mod['image'].isNotEmpty;

    return Container(
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
          if (mod['description'] != null && mod['description'].isNotEmpty) ...[
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
              onTap: () {
                // TODO: Open product link
                print('Open: ${mod['product_link']}');
              },
              child: Row(
                children: [
                  Icon(Icons.link, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'Product Link',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
