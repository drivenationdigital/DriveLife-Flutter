import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/qr_scanner_modal.dart';
import '../api/qr_code_api.dart';
import '../providers/user_provider.dart';

class QrScannerService {
  /// Show QR scanner modal and return the scanned result
  static Future<Map<String, dynamic>?> showScanner(BuildContext context) async {
    return await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const QrScannerModal(),
    );
  }

  /// Handle scanned QR code result
  static void handleScanResult(
    BuildContext context,
    Map<String, dynamic>? result, {
    Function(Map<String, dynamic>)? onSuccess,
    Function(String)? onError,
  }) {
    if (result == null) return;

    final status = result['status'];
    final available = result['available'] ?? false;
    final data = result['data'] as Map<String, dynamic>?;
    final qrCode = result['qr_code'] ?? '';

    print('📱 [QrScannerService] Handling scan result:');
    print('   Status: $status');
    print('   Available: $available');
    print('   QR Code: $qrCode');
    print('   Data: $data');

    if (status == 'success') {
      if (available) {
        // QR code is available - show acquire dialog
        print('   ✅ QR code available - showing acquire dialog');
        _showAcquireDialog(context, qrCode, result);
      } else {
        // QR code is linked - navigate to profile/entity
        if (data != null && data['linked_to'] != null) {
          final linkedId = data['linked_to'];
          final linkType = data['link_type'] ?? 'profile';

          print(
            '   ✅ QR code linked - navigating to $linkType (ID: $linkedId)',
          );

          if (linkType == 'profile') {
            // Navigate to profile
            Navigator.pushNamed(
              context,
              '/view-profile',
              arguments: {'userId': linkedId},
            );
          } else if (linkType == 'vehicle') {
            // Navigate to vehicle
            Navigator.pushNamed(
              context,
              '/vehicle-detail',
              arguments: {'garageId': linkedId.toString()},
            );
          }

          if (onSuccess != null) {
            onSuccess(result);
          }
        }
      }
    } else {
      // Error
      final message = result['message'] ?? 'Unknown error';
      print('   ❌ Error: $message');
      if (onError != null) {
        onError(message);
      } else {
        _showErrorDialog(context, message);
      }
    }
  }

  /// Show dialog to acquire available QR code
  static void _showAcquireDialog(
    BuildContext context,
    String qrCode,
    Map<String, dynamic> result,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            const Text('QR Code Available!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This QR code is up for grabs!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Would you like to link this QR code to your profile?',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tag, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    qrCode,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _linkQrCodeToProfile(context, qrCode);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Acquire',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Link QR code to current user's profile
  static Future<void> _linkQrCodeToProfile(
    BuildContext context,
    String qrCode,
  ) async {
    // Get current user ID from UserProvider
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final userId = userProvider.user?['id'];

    print('🔗 [QrScannerService] Linking QR code to profile:');
    print('   QR Code: $qrCode');
    print('   User ID: $userId');

    if (userId == null) {
      print('   ❌ User not logged in');
      _showErrorDialog(context, 'User not logged in');
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.orange)),
    );

    try {
      final response = await QrCodeAPI.linkEntity(
        entityId: userId,
        qrCode: qrCode,
        entityType: 'profile',
      );

      print('📥 [QrScannerService] Link response: $response');

      if (!context.mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      if (response != null && response['status'] == 'success') {
        print('   ✅ QR code linked successfully');
        _showSuccessDialog(
          context,
          'QR Code Linked!',
          'The QR code has been successfully linked to your profile.',
        );
      } else {
        print('   ❌ Failed to link QR code');
        _showErrorDialog(
          context,
          response?['message'] ?? 'Failed to link QR code. Please try again.',
        );
      }
    } catch (e) {
      print('   ❌ Error: $e');
      if (context.mounted) {
        Navigator.pop(context); // Close loading
        _showErrorDialog(context, 'Error linking QR code: ${e.toString()}');
      }
    }
  }

  static void _showSuccessDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.green,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
