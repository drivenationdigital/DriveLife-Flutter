import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Which app to hand a destination to.
///
/// Every one of these is opened by its https link rather than its private
/// scheme (waze://, comgooglemaps://). A universal link opens the app when it
/// is installed and the website when it is not, so there is no "you don't have
/// Waze" dead end — and no LSApplicationQueriesSchemes in the iOS plist or
/// `queries` entries in the Android manifest to keep in step with this file.
enum _NavApp { waze, google, apple }

extension on _NavApp {
  String get label => switch (this) {
    _NavApp.waze => 'Waze',
    _NavApp.google => 'Google Maps',
    _NavApp.apple => 'Apple Maps',
  };

  IconData get icon => switch (this) {
    _NavApp.waze => FontAwesomeIcons.waze,
    _NavApp.google => FontAwesomeIcons.google,
    _NavApp.apple => FontAwesomeIcons.apple,
  };

  Color get tint => switch (this) {
    _NavApp.waze => const Color(0xFF33CCFF),
    _NavApp.google => const Color(0xFF34A853),
    _NavApp.apple => const Color(0xFF1C1C1E),
  };

  /// The destination as each app wants it written.
  ///
  /// Coordinates where we have them: an address is a search, and a search can
  /// land on the wrong branch of a chain or fail outright on a field in the
  /// middle of nowhere — which is most of what gets listed here.
  String url(double? lat, double? lng, String address) {
    final hasPoint = lat != null && lng != null && (lat != 0 || lng != 0);
    final point = '$lat,$lng';
    final query = Uri.encodeComponent(address);

    return switch (this) {
      _NavApp.waze => hasPoint
          ? 'https://waze.com/ul?ll=$point&navigate=yes'
          : 'https://waze.com/ul?q=$query&navigate=yes',
      _NavApp.google => hasPoint
          ? 'https://www.google.com/maps/dir/?api=1&destination=$point'
          : 'https://www.google.com/maps/dir/?api=1&destination=$query',
      _NavApp.apple => hasPoint
          ? 'https://maps.apple.com/?daddr=$point&dirflg=d'
          : 'https://maps.apple.com/?daddr=$query&dirflg=d',
    };
  }
}

/// Offers the navigation apps for a place, and hands the destination over.
///
/// Returns once the sheet closes. Does nothing when there is neither a point
/// nor an address — there would be nothing to navigate to.
Future<void> showNavigateSheet(
  BuildContext context, {
  double? latitude,
  double? longitude,
  String address = '',
  String? title,
}) async {
  final trimmed = address.trim();
  final hasPoint =
      latitude != null && longitude != null && (latitude != 0 || longitude != 0);

  if (!hasPoint && trimmed.isEmpty) return;

  // Apple Maps is not installable on Android, and its web page is a poor
  // substitute for the two apps that are.
  final apps = <_NavApp>[
    _NavApp.waze,
    _NavApp.google,
    if (Platform.isIOS) _NavApp.apple,
  ];

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Get directions',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  if (title != null && title.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      title.trim(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                  if (trimmed.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      trimmed,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.grey.shade600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final app in apps)
              ListTile(
                leading: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: FaIcon(app.icon, size: 22, color: app.tint),
                  ),
                ),
                title: Text(
                  app.label,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: Icon(
                  Icons.north_east,
                  size: 17,
                  color: Colors.grey.shade400,
                ),
                onTap: () async {
                  // Closed first: the app switch takes a moment, and a sheet
                  // still sitting there on return looks like the tap failed.
                  Navigator.of(sheetContext).pop();

                  await _launch(
                    context,
                    app.url(latitude, longitude, trimmed),
                    app.label,
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _launch(BuildContext context, String url, String label) async {
  var opened = false;

  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }

  if (opened || !context.mounted) return;

  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Could not open $label')));
}
