import 'dart:io';

import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
import 'package:provider/provider.dart';

class AppPermissionsScreen extends StatefulWidget {
  const AppPermissionsScreen({super.key});

  @override
  State<AppPermissionsScreen> createState() => _AppPermissionsScreenState();
}

class _AppPermissionsScreenState extends State<AppPermissionsScreen> with WidgetsBindingObserver {
  final Map<String, bool> _expandedStates = {
    'camera': false,
    'location': false,
    // 'photos': false,
    'notifications': false,
  };

  final Map<String, PermissionStatus?> _permissionStatus = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 👈
    _checkPermissions();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 👈
    super.dispose();
  }

    // 👇 Re-check permissions when returning from Settings app
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  PermissionStatus? _normalizeStatus(PermissionStatus status) {
    if (Platform.isIOS && status == PermissionStatus.denied) {
      // Can't distinguish notDetermined from denied without requesting,
      // so treat denied as null (not yet requested) on iOS —
      // permanentlyDenied is the real "user said no"
      return null;
    }
    return status;
  }

Future<void> _checkPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final locationStatus = Platform.isIOS
        ? await Permission.locationWhenInUse.status
        : await Permission.location.status;
    final notificationsStatus = await Permission.notification.status;

    if (!mounted) return;

    setState(() {
      // 👇 On iOS, map notDetermined (shows as denied) to null so we show "Not Requested"
      _permissionStatus['camera'] = _normalizeStatus(cameraStatus);
      _permissionStatus['location'] = _normalizeStatus(locationStatus);
      _permissionStatus['notifications'] = _normalizeStatus(
        notificationsStatus,
      );
    });
  }
  // Add individual request methods
  Future<void> _requestPermission(String key) async {
    PermissionStatus status;

    switch (key) {
      case 'camera':
        status = await Permission.camera.request();
        break;
      case 'location':
        status = Platform.isIOS
            ? await Permission.locationWhenInUse.request()
            : await Permission.location.request();
        break;
      case 'notifications':
        status = await Permission.notification.request();
        break;
      default:
        return;
    }

    if (!mounted) return;

    // On iOS, if still denied after requesting, it's permanently denied
    if (Platform.isIOS && status == PermissionStatus.denied) {
      status = PermissionStatus.permanentlyDenied;
    }

    setState(() => _permissionStatus[key] = status);
  }

  String _getStatusText(PermissionStatus? status) {
    if (status == null) return 'Not Requested';
    switch (status) {
      case PermissionStatus.granted:
        return 'Granted';
      case PermissionStatus.permanentlyDenied:
        return 'Denied';
      case PermissionStatus.restricted:
        return 'Restricted';
      case PermissionStatus.limited:
        return 'Limited';
      default:
        return 'Not Requested';
    }
  }

  Color _getStatusColor(PermissionStatus? status, ThemeProvider theme) {
    if (status == null) return Colors.grey;
    if (status == PermissionStatus.granted) return Colors.green;
    if (status == PermissionStatus.permanentlyDenied ||
        status == PermissionStatus.restricted)
      return Colors.red;
    return theme.primaryColor;
  }

  void _openAppSettings() {
    AppSettings.openAppSettings(type: AppSettingsType.settings);
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String description,
    required String key,
    required ThemeProvider theme,
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
                        color: _getStatusColor(status, theme).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getStatusText(status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(status, theme),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Add request button if not granted
                  if (status != PermissionStatus.granted)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final isPermanent =
                              status == PermissionStatus.permanentlyDenied;
                          final forceSettings =
                              Platform.isIOS &&
                              status == PermissionStatus.denied;

                          if (isPermanent || forceSettings) {
                            _openAppSettings();
                          } else {
                            await _requestPermission(key);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(
                          (status == PermissionStatus.permanentlyDenied ||
                                  (Platform.isIOS &&
                                      status == PermissionStatus.denied))
                              ? 'Open Settings'
                              : 'Request Permission',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

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
                  theme: theme,
                ),
                const SizedBox(height: 12),
                _buildPermissionTile(
                  icon: Icons.location_on,
                  title: 'Location Permissions',
                  description:
                      'This app uses your location to show nearby events and tag posts.',
                  key: 'location',
                  theme: theme,
                ),
                // const SizedBox(height: 12),
                // _buildPermissionTile(
                //   icon: Icons.photo_library,
                //   title: 'Photos & Videos Permissions',
                //   description:
                //       'This app needs access to your photos to upload media to posts.',
                //   key: 'photos',
                //   theme: theme,
                // ),
                const SizedBox(height: 12),
                _buildPermissionTile(
                  icon: Icons.notifications,
                  title: 'Notification Permissions',
                  description:
                      'This app sends notifications for likes, comments, and follows.',
                  key: 'notifications',
                  theme: theme,
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
          const SizedBox(height: 26),
        ],
      ),
    );
  }
}
