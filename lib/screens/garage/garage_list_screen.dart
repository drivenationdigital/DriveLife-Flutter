import 'package:drivelife/api/garage_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class GarageListScreen extends StatefulWidget {
  const GarageListScreen({Key? key}) : super(key: key);

  @override
  _GarageListScreenState createState() => _GarageListScreenState();
}

class _GarageListScreenState extends State<GarageListScreen> {
  bool _loadingGarage = true;
  List<dynamic> _currentVehicles = [];
  List<dynamic> _pastVehicles = [];
  List<dynamic> _dreamVehicles = [];

  Map<String, dynamic>? _userProfile;
  bool _garageLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile().then((_) => _loadGarage(false));
  }

  // Get session user
  Future<void> _loadUserProfile() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (!mounted) return;

    setState(() {
      _userProfile = user;
    });
  }

  Future<void> _loadGarage(bool? refresh) async {
    if ((_garageLoaded || _userProfile == null) && refresh != true) return;

    setState(() {
      _loadingGarage = true;
      _garageLoaded = true; // prevents double calls
    });

    final garage = await GarageAPI.getUserGarage(_userProfile!['id']);

    if (!mounted) return;

    final current = <dynamic>[];
    final past = <dynamic>[];
    final dream = <dynamic>[];

    if (garage != null) {
      for (final vehicle in garage) {
        if (vehicle['primary_car'] == '2') {
          dream.add(vehicle);
        } else if (vehicle['owned_until'] == '' ||
            vehicle['owned_until']?.toString().toLowerCase() == 'present') {
          current.add(vehicle);
        } else {
          past.add(vehicle);
        }
      }
    }

    setState(() {
      _currentVehicles = current;
      _pastVehicles = past;
      _dreamVehicles = dream;
      _loadingGarage = false;
    });
  }

  Widget _buildGarageContent(ThemeProvider theme) {
    if (_loadingGarage) {
      return SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          _buildGarageSection('Current Vehicles', _currentVehicles, theme),
          const SizedBox(height: 24),
          _buildGarageSection('Past Vehicles', _pastVehicles, theme),
          const SizedBox(height: 24),
          _buildGarageSection('Dream Vehicles', _dreamVehicles, theme),
        ]),
      ),
    );
  }

  Widget _buildGarageSection(
    String title,
    List<dynamic> vehicles,
    ThemeProvider theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.textColor,
          ),
        ),
        const SizedBox(height: 12),
        if (vehicles.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'No ${title.toLowerCase()}',
              style: TextStyle(color: theme.subtextColor),
            ),
          )
        else
          ...vehicles.map(
            (vehicle) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.cardColor,

                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    color: theme.dividerColor,
                    child: vehicle['cover_photo'] != null
                        ? Image.network(
                            vehicle['cover_photo'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[300],
                                child: const Icon(
                                  Icons.broken_image,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: Colors.grey[200],
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value:
                                        loadingProgress.expectedTotalBytes !=
                                            null
                                        ? loadingProgress
                                                  .cumulativeBytesLoaded /
                                              loadingProgress
                                                  .expectedTotalBytes!
                                        : null,
                                  ),
                                ),
                              );
                            },
                          )
                        : Icon(Icons.directions_car, color: theme.subtextColor),
                  ),
                ),
                title: Text(
                  '${vehicle['make']} ${vehicle['model']}',
                  style: TextStyle(
                    color: theme.textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: Icon(Icons.chevron_right, color: theme.subtextColor),
                // UPDATE: garage_list_screen.dart - vehicle list tile onTap
                onTap: () async {
                  final result = await Navigator.pushNamed(
                    context,
                    '/vehicle-detail',
                    arguments: {'garageId': vehicle['id'].toString()},
                  );

                  // Refresh if vehicle was updated or deleted
                  if (result != null) {
                    _loadGarage(true);
                  }
                },
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        // Use a Builder so Scaffold.of(context).openDrawer() has the right context
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true, // 👈 ensures the title is centered
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          IconButton(
            padding: const EdgeInsets.only(right: 14),
            onPressed: () async {
              final result = await NavigationHelper.navigateTo(
                context,
                const AddVehicleScreen(),
              );

              // Refresh if vehicle was added
              if (result != null) {
                _loadGarage(true);
              }
            },
            icon: Row(
              spacing: 4,
              children: [
                const Icon(Icons.add, color: Colors.black, size: 20),
                const Text(
                  'Add',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadGarage(true),
        color: theme.primaryColor,
        child: CustomScrollView(slivers: [_buildGarageContent(theme)]),
      ),
    );
  }
}
