import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/garage_api.dart';
import '../providers/theme_provider.dart';

class GarageTabSliver extends StatefulWidget {
  final int userId;

  const GarageTabSliver({super.key, required this.userId});

  @override
  State<GarageTabSliver> createState() => _GarageTabSliverState();
}

class _GarageTabSliverState extends State<GarageTabSliver>
    with AutomaticKeepAliveClientMixin {
  List<dynamic> _currentVehicles = [];
  List<dynamic> _pastVehicles = [];
  List<dynamic> _dreamVehicles = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadGarage();
  }

  Future<void> _loadGarage() async {
    final garage = await GarageAPI.getUserGarage(widget.userId);

    if (!mounted || garage == null) return;

    final current = <dynamic>[];
    final past = <dynamic>[];
    final dream = <dynamic>[];

    for (final vehicle in garage) {
      if (vehicle['primary_car'] == '2') {
        dream.add(vehicle);
      } else if (vehicle['owned_until'] == '' ||
          vehicle['owned_until']?.toLowerCase() == 'present') {
        current.add(vehicle);
      } else {
        past.add(vehicle);
      }
    }

    setState(() {
      _currentVehicles = current;
      _pastVehicles = past;
      _dreamVehicles = dream;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Provider.of<ThemeProvider>(context);

    if (_loading) {
      return SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    // Return list of slivers
    return SliverList(
      delegate: SliverChildListDelegate([
        const SizedBox(height: 16),
        _buildSection('Current Vehicles', _currentVehicles, theme),
        const SizedBox(height: 24),
        _buildSection('Past Vehicles', _pastVehicles, theme),
        const SizedBox(height: 24),
        _buildSection('Dream Vehicles', _dreamVehicles, theme),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _buildSection(
    String title,
    List<dynamic> vehicles,
    ThemeProvider theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'No ${title.toLowerCase()}',
                style: TextStyle(color: theme.subtextColor),
              ),
            )
          else
            ...vehicles.map((vehicle) => _buildVehicleCard(vehicle, theme)),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle, ThemeProvider theme) {
    final coverPhoto = vehicle['cover_photo'];
    final hasImage = coverPhoto != null && coverPhoto.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/vehicle-detail',
            arguments: {'garageId': vehicle['id'].toString()},
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 60,
                  height: 60,
                  color: theme.dividerColor,
                  child: hasImage
                      ? Image.network(
                          coverPhoto,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.directions_car,
                            color: theme.subtextColor,
                            size: 30,
                          ),
                        )
                      : Icon(
                          Icons.directions_car,
                          color: theme.subtextColor,
                          size: 30,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${vehicle['make']} ${vehicle['model']}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: theme.textColor,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: theme.subtextColor),
            ],
          ),
        ),
      ),
    );
  }
}
