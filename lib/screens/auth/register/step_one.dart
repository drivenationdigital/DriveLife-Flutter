import 'package:drivelife/providers/registration_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/widgets/auth/privacy_modal.dart';
import 'package:drivelife/widgets/auth/terms_modal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RegisterStepOneScreen extends StatefulWidget {
  const RegisterStepOneScreen({Key? key}) : super(key: key);

  @override
  State<RegisterStepOneScreen> createState() => _RegisterStepOneScreenState();
}

class _RegisterStepOneScreenState extends State<RegisterStepOneScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        appBar: AppBar(
          backgroundColor: isDark ? Colors.black : Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false, // Remove back button
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: Text(
                'Login',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Consumer<RegistrationProvider>(
                builder: (context, registrationProvider, child) {
                  return Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        Text(
                          'Register',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create your DriveLife Account',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 40),

                        // First Name
                        _buildTextField(
                          label: 'First Name',
                          hint: 'Enter first name',
                          initialValue: registrationProvider.firstName,
                          onChanged: registrationProvider.setFirstName,
                          validator: (value) => value?.isEmpty ?? true
                              ? 'First name is required'
                              : null,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 20),

                        // Last Name
                        _buildTextField(
                          label: 'Last Name',
                          hint: 'Enter last name',
                          initialValue: registrationProvider.lastName,
                          onChanged: registrationProvider.setLastName,
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Last name is required'
                              : null,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 20),

                        // Email
                        _buildTextField(
                          label: 'Email',
                          hint: 'Enter email address',
                          initialValue: registrationProvider.email,
                          keyboardType: TextInputType.emailAddress,
                          onChanged: registrationProvider.setEmail,
                          validator: registrationProvider.validateEmail,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 20),

                        // Password
                        _buildPasswordField(
                          label: 'Password',
                          hint: 'Enter password',
                          obscureText: _obscurePassword,
                          onChanged: registrationProvider.setPassword,
                          validator: registrationProvider.validatePassword,
                          onToggleVisibility: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          isDark: isDark,
                        ),
                        const SizedBox(height: 20),

                        // Confirm Password
                        _buildPasswordField(
                          label: 'Confirm Password',
                          hint: 'Enter password',
                          obscureText: _obscureConfirmPassword,
                          onChanged: registrationProvider.setConfirmPassword,
                          validator:
                              registrationProvider.validateConfirmPassword,
                          onToggleVisibility: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                          isDark: isDark,
                        ),
                        const SizedBox(height: 20),

                        // Country Dropdown
                        _buildCountryDropdown(registrationProvider, isDark),
                        const SizedBox(height: 30),

                        // Terms Checkbox
                        _buildCheckbox(
                          value: registrationProvider.agreeTerms,
                          onChanged: registrationProvider.setAgreeTerms,
                          isDark: isDark,
                          child: Row(
                            children: [
                              Text(
                                'I agree to the ',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _showTermsModal(context),
                                child: const Text(
                                  'Terms & Conditions',
                                  style: TextStyle(
                                    color: Color(0xFFB8966B),
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Privacy Checkbox
                        _buildCheckbox(
                          value: registrationProvider.agreePrivacy,
                          onChanged: registrationProvider.setAgreePrivacy,
                          isDark: isDark,
                          child: Row(
                            children: [
                              Text(
                                'I agree to the ',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _showPrivacyModal(context),
                                child: const Text(
                                  'Privacy Policy',
                                  style: TextStyle(
                                    color: Color(0xFFB8966B),
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Next Button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: registrationProvider.isLoading
                                ? null
                                : () async {
                                    if (_formKey.currentState!.validate() &&
                                        registrationProvider.validateStep1()) {
                                      // Set loading state
                                      registrationProvider.setLoading(true);

                                      // Call registration API
                                      final response = await _authService
                                          .registerUser(
                                            fullName:
                                                '${registrationProvider.firstName} ${registrationProvider.lastName}',
                                            email: registrationProvider.email,
                                            password:
                                                registrationProvider.password,
                                            country:
                                                registrationProvider.country,
                                          );

                                      // Stop loading
                                      registrationProvider.setLoading(false);
                                      print('Registration Response: $response');
                                      // Check response
                                      if (response['success'] != true) {
                                        // Show error dialog
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text(
                                              'Registration Error',
                                            ),
                                            content: Text(
                                              response['message'] ??
                                                  'An error occurred, please try again',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text('OK'),
                                              ),
                                            ],
                                          ),
                                        );
                                        return;
                                      }

                                      // Save user_id and suggested username
                                      registrationProvider.setUserId(
                                        response['user_id'],
                                      );
                                      registrationProvider.setSuggestedUsername(
                                        response['username'] ?? '',
                                      );

                                      // Move to next step
                                      registrationProvider.nextStep();
                                      Navigator.pushNamed(
                                        context,
                                        '/register-step-2',
                                      );
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Please complete all fields and agree to terms',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB8966B),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                              disabledBackgroundColor: Colors.grey,
                            ),
                            child: registrationProvider.isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'NEXT',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ); // WillPopScope closing
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required String initialValue,
    required Function(String) onChanged,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: initialValue,
          onChanged: onChanged,
          validator: validator,
          keyboardType: keyboardType,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            filled: true,
            fillColor: isDark ? Colors.grey[900] : Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFB8966B), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.red),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required String label,
    required String hint,
    required bool obscureText,
    required Function(String) onChanged,
    String? Function(String?)? validator,
    required VoidCallback onToggleVisibility,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          onChanged: onChanged,
          validator: validator,
          obscureText: obscureText,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            filled: true,
            fillColor: isDark ? Colors.grey[900] : Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFB8966B), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.red),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              onPressed: onToggleVisibility,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountryDropdown(RegistrationProvider provider, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Country',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: provider.country.isEmpty ? null : provider.country,
          dropdownColor: isDark ? Colors.grey[900] : Colors.white,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: 'Select Country',
            hintStyle: TextStyle(
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            filled: true,
            fillColor: isDark ? Colors.grey[900] : Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFB8966B), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          items: const [
            DropdownMenuItem(value: 'UK', child: Text('United Kingdom')),
            DropdownMenuItem(value: 'USA', child: Text('United States')),
            DropdownMenuItem(value: 'Canada', child: Text('Canada')),
            DropdownMenuItem(value: 'Other', child: Text('Other')),
          ],
          onChanged: (value) {
            if (value != null) {
              provider.setCountry(value);
            }
          },
          validator: (value) =>
              value == null ? 'Please select a country' : null,
        ),
      ],
    );
  }

  Widget _buildCheckbox({
    required bool value,
    required Function(bool) onChanged,
    required Widget child,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: value,
            onChanged: (val) => onChanged(val ?? false),
            activeColor: const Color(0xFFB8966B),
            checkColor: Colors.white,
            side: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[400]!,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    );
  }

  void _showTermsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TermsModal(),
    );
  }

  void _showPrivacyModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const PrivacyModal(),
    );
  }
}
