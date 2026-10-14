import 'package:flutter/material.dart';

/// A section that exists in the navigation but has nothing behind it yet.
///
/// Said plainly rather than shown as an empty list. "No businesses found"
/// reads as a search that came back empty — as though there are none near
/// you — when the truth is that nothing has been added anywhere yet. The
/// first invites you to widen the search; the second tells you not to bother.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;

  const ComingSoonScreen({
    super.key,
    required this.title,
    this.icon = Icons.storefront_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  color: Color(0xFFF4F4F4),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: const Color(0xFF9A9A9E)),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Coming soon.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFB08E4F),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "We're working on this one. Check back shortly.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: Color(0xFF8A8A8E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
