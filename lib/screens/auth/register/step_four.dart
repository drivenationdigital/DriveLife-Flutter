import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/providers/registration_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RegisterStepFourScreen extends StatelessWidget {
  const RegisterStepFourScreen({Key? key}) : super(key: key);

  static const Map<int, String> profileTypeOptions = {
    0: 'Car Owner / Enthusiast',
    1: 'Photographer / Videographer',
    2: 'Event Organiser',
    3: 'Automotive Venue',
    4: 'Automotive Business',
    5: 'Car Club',
  };

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
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 40),
                            Text(
                              'Your Profile',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Which best describes you?',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Unlock app features based on your requirements',
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                            const SizedBox(height: 40),
                            ...profileTypeOptions.entries.map((entry) {
                              final profileTypeId = entry.key;
                              final profileTypeLabel = entry.value;
                              final isSelected =
                                  registrationProvider.profileTypeId ==
                                  profileTypeId;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: InkWell(
                                  onTap: () {
                                    registrationProvider.setProfileTypeId(
                                      profileTypeId,
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.grey[900]
                                          : Colors.grey[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFFB8966B)
                                            : isDark
                                            ? Colors.grey[800]!
                                            : Colors.grey[300]!,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFFB8966B)
                                                  : isDark
                                                  ? Colors.grey[600]!
                                                  : Colors.grey[400]!,
                                              width: 2,
                                            ),
                                            color: isSelected
                                                ? const Color(0xFFB8966B)
                                                : Colors.transparent,
                                          ),
                                          child: isSelected
                                              ? Container(
                                                  margin: const EdgeInsets.all(
                                                    5,
                                                  ),
                                                  decoration:
                                                      const BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            profileTypeLabel,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(
                                            Icons.check,
                                            color: Color(0xFFB8966B),
                                            size: 24,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: registrationProvider.isLoading
                            ? null
                            : () async {
                                if (registrationProvider.validateStep4()) {
                                  // Set loading state
                                  registrationProvider.setLoading(true);

                                  // Call API to update about user ID
                                  final response =
                                      await ProfileAPI.updateAboutUserIds(
                                        contentIds: [
                                          registrationProvider.profileTypeId!,
                                        ],
                                        userId: registrationProvider.userId!,
                                      );

                                  // Stop loading
                                  registrationProvider.setLoading(false);
                                  print(
                                    'Update About User ID Response: $response',
                                  );

                                  // Check response
                                  if (response?['success'] != true) {
                                    ScaffoldMessenger.of(context).showSnackBar(
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

                                  // Success - move to next step
                                  registrationProvider.nextStep();
                                  Navigator.pushNamed(
                                    context,
                                    '/register-step-5',
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please select a profile type',
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
