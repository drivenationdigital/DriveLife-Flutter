import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:provider/provider.dart';

class EmailVerificationModal extends StatefulWidget {
  final String token;

  const EmailVerificationModal({super.key, required this.token});

  @override
  State<EmailVerificationModal> createState() => _EmailVerificationModalState();
}

class _EmailVerificationModalState extends State<EmailVerificationModal> {
  bool _isVerifying = true;
  bool _isSuccess = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _verifyEmail();
  }

  Future<void> _verifyEmail() async {
    setState(() => _isVerifying = true);

    try {
      final authService = AuthService();
      final result = await authService.verifyEmailToken(widget.token);

      print(result);

      if (!mounted) return;

      if (result['success'] == true) {
        // Refresh user details
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.forceRefresh();

        setState(() {
          _isSuccess = true;
          _isVerifying = false;
          _message =
              result['message'] ?? 'Your email has been successfully verified!';
        });
      } else {
        setState(() {
          _isSuccess = false;
          _isVerifying = false;
          _message =
              result['message'] ?? 'Verification failed. Please try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSuccess = false;
          _isVerifying = false;
          _message = 'An unexpected error occurred. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 32),

              // Content
              if (_isVerifying) _buildLoadingView(),
              if (!_isVerifying && _isSuccess) _buildSuccessView(),
              if (!_isVerifying && !_isSuccess) _buildErrorView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
        ),
        const SizedBox(height: 24),
        const Text(
          'Verifying your email...',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Text(
          'Please wait a moment',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSuccessView() {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Success icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle,
            size: 50,
            color: theme.primaryColor,
          ),
        ),

        const SizedBox(height: 24),

        // Success title
        const Text(
          'Email Verified!',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 12),

        // Success message
        Text(
          _message,
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 32),

        // Continue button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildErrorView() {
    final theme = Provider.of<ThemeProvider>(context, listen: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Error icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.error_outline,
            size: 50,
            color: Colors.red.shade700,
          ),
        ),

        const SizedBox(height: 24),

        // Error title
        const Text(
          'Verification Failed',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 12),

        // Error message
        Text(
          _message,
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 8),

        Text(
          'If you continue to experience issues, please contact support.',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 32),

        // Retry and Go Back buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Go Back',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _verifyEmail,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}
