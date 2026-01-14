import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/garage_api.dart';

class GarageTab extends StatefulWidget {
  final int userId;

  const GarageTab({super.key, required this.userId});

  @override
  State<GarageTab> createState() => _GarageTabState();
}

class _GarageTabState extends State<GarageTab>
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
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGarage,
      color: theme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('Current Vehicles', _currentVehicles, theme),
          const SizedBox(height: 24),
          _buildSection('Past Vehicles', _pastVehicles, theme),
          const SizedBox(height: 24),
          _buildSection('Dream Vehicles', _dreamVehicles, theme),
        ],
      ),
    );
  }

  Widget _buildSection(
    String title,
    List<dynamic> vehicles,
    ThemeProvider theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
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
            width: double.infinity, // Full width
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No ${title.toLowerCase()}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          )
        else
          ...vehicles.map((vehicle) => _buildVehicleCard(vehicle)),
      ],
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle) {
    final coverPhoto = vehicle['cover_photo'];
    final hasImage = coverPhoto != null && coverPhoto.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
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
              // Vehicle image
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 60,
                  height: 60,
                  color: Colors.grey.shade300,
                  child: hasImage
                      ? Image.network(
                          coverPhoto,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.directions_car,
                            color: Colors.grey.shade600,
                            size: 30,
                          ),
                        )
                      : Icon(
                          Icons.directions_car,
                          color: Colors.grey.shade600,
                          size: 30,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Vehicle name
              Expanded(
                child: Text(
                  '${vehicle['make']} ${vehicle['model']}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
              // Arrow
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
