import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';

class AppPermissionsScreen extends StatefulWidget {
  const AppPermissionsScreen({super.key});

  @override
  State<AppPermissionsScreen> createState() => _AppPermissionsScreenState();
}

class _AppPermissionsScreenState extends State<AppPermissionsScreen> {
  final Map<String, bool> _expandedStates = {
    'camera': false,
    'location': false,
    'photos': false,
    'notifications': false,
  };

  final Map<String, PermissionStatus> _permissionStatus = {};

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.location,
      Permission.photos,
      Permission.notification,
    ].request();

    if (!mounted) return;

    setState(() {
      _permissionStatus['camera'] = statuses[Permission.camera]!;
      _permissionStatus['location'] = statuses[Permission.location]!;
      _permissionStatus['photos'] = statuses[Permission.photos]!;
      _permissionStatus['notifications'] = statuses[Permission.notification]!;
    });
  }

  String _getStatusText(PermissionStatus? status) {
    if (status == null) return 'Checking...';
    switch (status) {
      case PermissionStatus.granted:
        return 'Granted';
      case PermissionStatus.denied:
        return 'Denied';
      case PermissionStatus.permanentlyDenied:
        return 'Permanently Denied';
      case PermissionStatus.restricted:
        return 'Restricted';
      case PermissionStatus.limited:
        return 'Limited';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor(PermissionStatus? status) {
    if (status == PermissionStatus.granted) return Colors.green;
    if (status == PermissionStatus.denied) return Colors.orange;
    return Colors.red;
  }

  void _openAppSettings() {
    AppSettings.openAppSettings(type: AppSettingsType.settings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Image.asset('assets/logo-dark.png', height: 18),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code, color: Colors.black),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPermissionTile(
                  icon: Icons.camera_alt,
                  title: 'Camera Permissions',
                  description:
                      'This app uses the camera to allow you to take photos to create posts, and scan QR codes.',
                  key: 'camera',
                ),
                const SizedBox(height: 12),
                _buildPermissionTile(
                  icon: Icons.location_on,
                  title: 'Location Permissions',
                  description:
                      'This app uses your location to show nearby events and tag posts.',
                  key: 'location',
                ),
                const SizedBox(height: 12),
                _buildPermissionTile(
                  icon: Icons.photo_library,
                  title: 'Photos & Videos Permissions',
                  description:
                      'This app needs access to your photos to upload media to posts.',
                  key: 'photos',
                ),
                const SizedBox(height: 12),
                _buildPermissionTile(
                  icon: Icons.notifications,
                  title: 'Notification Permissions',
                  description:
                      'This app sends notifications for likes, comments, and follows.',
                  key: 'notifications',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _openAppSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFAE9159),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'UPDATE PERMISSIONS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String description,
    required String key,
  }) {
    final isExpanded = _expandedStates[key] ?? false;
    final status = _permissionStatus[key];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _expandedStates[key] = !isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, color: Colors.grey.shade700, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (status != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getStatusText(status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(status),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Divider(height: 1, color: Colors.grey.shade300),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
