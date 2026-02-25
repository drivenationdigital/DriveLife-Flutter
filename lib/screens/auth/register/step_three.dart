import 'package:drivelife/api/profile_api.dart';
import 'package:drivelife/providers/registration_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RegisterStepThreeScreen extends StatelessWidget {
  const RegisterStepThreeScreen({Key? key}) : super(key: key);

  // Map of interest IDs to labels
  static const Map<int, String> interestOptions = {
    0: 'Sports Cars / Supercars / Exotics',
    1: 'JDM & Modded',
    2: 'Classic Cars',
    3: 'Electric Cars',
    4: 'Hotrods & Dragsters',
    5: 'Race Cars',
    6: 'Motorbikes',
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
                              'About You',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'What type of content revs your engine?',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tick all that apply',
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                            const SizedBox(height: 40),
                            ...interestOptions.entries.map((entry) {
                              final interestId = entry.key;
                              final interestLabel = entry.value;
                              final isSelected = registrationProvider
                                  .interestIds
                                  .contains(interestId);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: InkWell(
                                  onTap: () {
                                    registrationProvider.toggleInterestId(
                                      interestId,
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
                                              ? const Icon(
                                                  Icons.check,
                                                  size: 16,
                                                  color: Colors.white,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            interestLabel,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),
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
                                if (registrationProvider.validateStep3()) {
                                  // Set loading state
                                  registrationProvider.setLoading(true);

                                  // Call API to update content IDs
                                  final response =
                                      await ProfileAPI.updateContentIds(
                                        contentIds:
                                            registrationProvider.interestIds,
                                        userId: registrationProvider.userId!,
                                      );

                                  // Stop loading
                                  registrationProvider.setLoading(false);
                                  print(
                                    'Update Content IDs Response: $response',
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
                                    '/register-step-4',
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please select at least one interest',
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
