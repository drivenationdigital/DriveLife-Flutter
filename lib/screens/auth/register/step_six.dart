import 'package:drivelife/screens/garage/add_vehicle_screen.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../routes.dart';

/// The last screen of signup: add your first vehicle.
///
/// WHY THIS EXISTS AT ALL
///
/// Signup used to end by dropping somebody straight into the app with
/// an empty garage. An empty garage is the state that makes almost
/// everything else — reminders, the leaderboard, Your week — look
/// broken rather than new, and the one moment somebody is certain to be
/// paying attention is the moment they finish signing up.
///
/// Skippable on purpose, and skipping goes to the same place. Forcing a
/// vehicle here would mean somebody who has not decided yet either
/// inventing one or abandoning the signup they have just completed.
class RegisterStepSixScreen extends StatelessWidget {
  const RegisterStepSixScreen({super.key});

  static const Color _ink = Color(0xFF0B0B0B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),

              SvgPicture.asset('assets/logo-flag-black.svg', height: 84),
              const SizedBox(height: 34),

              const DlHeading(
                "Start your engine, you're in!",
                fontSize: 38,
                height: 1.05,
                color: _ink,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),

              Text(
                'To unlock all app features, add your current, past or '
                'dream garage.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.5,
                  height: 1.45,
                  color: Colors.grey.shade700,
                ),
              ),

              const Spacer(flex: 4),

              SizedBox(
                width: double.infinity,
                child: Material(
                  color: _ink,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _addVehicle(context),
                    child: Container(
                      height: 62,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Add vehicle',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // The reward, in the shape it will arrive in.
                          // The number matches dl_points_rules() on the
                          // server — if that changes, this changes.
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFAE9159),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              '+500 points',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),
              TextButton(
                onPressed: () => _finish(context),
                child: Text(
                  'Skip',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Add a vehicle, then go in.
  ///
  /// The reward is shown HERE rather than left to AddVehicleScreen,
  /// because that screen pops back to this one — and a reward fired
  /// during a pop either stacks on the wrong route or is dismissed
  /// with it.
  Future<void> _addVehicle(BuildContext context) async {
    final added = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(builder: (_) => const AddVehicleScreen()),
    );

    if (!context.mounted) return;

    // Backed out without saving: stay here rather than pushing them on,
    // since they may simply have wanted a second look at the form.
    if (added == null) return;

    _finish(context);
  }

  void _finish(BuildContext context) {
    Navigator.pushReplacementNamed(context, AppRoutes.home);
  }
}
