import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/providers/registration_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RegisterStepTwoScreen extends StatefulWidget {
  const RegisterStepTwoScreen({Key? key}) : super(key: key);

  @override
  State<RegisterStepTwoScreen> createState() => _RegisterStepTwoScreenState();
}

class _RegisterStepTwoScreenState extends State<RegisterStepTwoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final registrationProvider = Provider.of<RegistrationProvider>(
      context,
      listen: false,
    );
    // Set the suggested username from API response
    _usernameController.text = registrationProvider.username;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Consumer<RegistrationProvider>(
              builder: (context, registrationProvider, child) {
                return Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Username',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create your DriveLife username',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 60),
                            TextFormField(
                              controller: _usernameController,
                              // onChanged: registrationProvider.setUsername,
                              validator: registrationProvider.validateUsername,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText:
                                    registrationProvider
                                        .suggestedUsername
                                        .isEmpty
                                    ? 'Enter your username'
                                    : registrationProvider.suggestedUsername,
                                hintStyle: TextStyle(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.black26,
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.grey[900]
                                    : Colors.grey[50],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? Colors.grey[800]!
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? Colors.grey[800]!
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFB8966B),
                                    width: 2,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: registrationProvider.isLoading
                              ? null
                              : () async {
                                  if (_formKey.currentState!.validate() &&
                                      registrationProvider.validateStep2()) {
                                    bool usernameDirty =
                                        _usernameController.text !=
                                        registrationProvider.username;

                                    // check if username was dirtied
                                    if (usernameDirty) {
                                      // Set loading state
                                      registrationProvider.setLoading(true);

                                      // Call registration API
                                      final response =
                                          await ProfileAPI.updateUsername(
                                            username: _usernameController.text,
                                            userId:
                                                registrationProvider.userId!,
                                            isRegistration: true,
                                          );

                                      // Stop loading
                                      registrationProvider.setLoading(false);
                                      print('Registration Response: $response');

                                      // Check response
                                      if (response?['success'] != true) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              response?['message'] ??
                                                  'An error occurred, please try again',
                                            ),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                        return;
                                      }

                                      // ✅ Only update provider AFTER successful API call
                                      registrationProvider.setUsername(
                                        _usernameController.text,
                                      );
                                    }

                                    registrationProvider.nextStep();
                                    Navigator.pushNamed(
                                      context,
                                      '/register-step-3',
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please enter a valid username',
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
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ); // WillPopScope closing
  }
}
