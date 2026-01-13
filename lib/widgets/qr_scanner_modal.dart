import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../api/qr_code_api.dart';

class QrScannerModal extends StatefulWidget {
  const QrScannerModal({super.key});

  @override
  State<QrScannerModal> createState() => _QrScannerModalState();
}

class _QrScannerModalState extends State<QrScannerModal> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;
  String? _errorMessage;
  Map<String, dynamic>? _scannedData;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _scannedData = null;
    });

    try {
      // Extract QR code from URL
      final qrCode = QrCodeAPI.extractQrCodeFromUrl(code);

      if (qrCode == null) {
        setState(() {
          _errorMessage =
              'Invalid QR code. Please scan a valid DriveLife QR code.';
          _isProcessing = false;
        });
        return;
      }

      final currentUser = Provider.of<UserProvider>(
        context,
        listen: false,
      ).user;

      // Verify the QR code
      final response = await QrCodeAPI.verifyScan(qrCode, currentUser!['id']);

      if (!mounted) return;

      if (response == null) {
        setState(() {
          _errorMessage = 'Failed to verify QR code. Please try again.';
          _isProcessing = false;
        });
        return;
      }

      setState(() {
        _scannedData = response;
        _isProcessing = false;
      });

      // Close modal and return the result
      if (mounted) {
        Navigator.pop(context, response);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error scanning QR code: ${e.toString()}';
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: theme.textColor),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                Text(
                  'Scan QR Code',
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Scanner
          Expanded(
            child: Stack(
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),

                // Overlay with cutout
                CustomPaint(
                  painter: ScannerOverlayPainter(),
                  child: Container(),
                ),

                // Instructions
                Positioned(
                  bottom: 40,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (_isProcessing)
                          const Column(
                            children: [
                              CircularProgressIndicator(color: Colors.orange),
                              SizedBox(height: 12),
                              Text(
                                'Processing...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          )
                        else if (_errorMessage != null)
                          Column(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _errorMessage = null;
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                ),
                                child: const Text('Try Again'),
                              ),
                            ],
                          )
                        else
                          const Text(
                            'Position the QR code within the frame',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for scanner overlay
class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const scanAreaSize = 250.0;
    final scanAreaRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanAreaSize,
      height: scanAreaSize,
    );

    // Draw semi-transparent background
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final scanAreaPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(scanAreaRect, const Radius.circular(12)),
      );

    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    canvas.drawPath(
      Path.combine(PathOperation.difference, backgroundPath, scanAreaPath),
      paint,
    );

    // Draw corner brackets
    final cornerPaint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const cornerRadius = 12.0;

    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(scanAreaRect.left + cornerRadius, scanAreaRect.top)
        ..lineTo(scanAreaRect.left + cornerLength, scanAreaRect.top)
        ..moveTo(scanAreaRect.left, scanAreaRect.top + cornerRadius)
        ..lineTo(scanAreaRect.left, scanAreaRect.top + cornerLength),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(scanAreaRect.right - cornerRadius, scanAreaRect.top)
        ..lineTo(scanAreaRect.right - cornerLength, scanAreaRect.top)
        ..moveTo(scanAreaRect.right, scanAreaRect.top + cornerRadius)
        ..lineTo(scanAreaRect.right, scanAreaRect.top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(scanAreaRect.left + cornerRadius, scanAreaRect.bottom)
        ..lineTo(scanAreaRect.left + cornerLength, scanAreaRect.bottom)
        ..moveTo(scanAreaRect.left, scanAreaRect.bottom - cornerRadius)
        ..lineTo(scanAreaRect.left, scanAreaRect.bottom - cornerLength),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(scanAreaRect.right - cornerRadius, scanAreaRect.bottom)
        ..lineTo(scanAreaRect.right - cornerLength, scanAreaRect.bottom)
        ..moveTo(scanAreaRect.right, scanAreaRect.bottom - cornerRadius)
        ..lineTo(scanAreaRect.right, scanAreaRect.bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
