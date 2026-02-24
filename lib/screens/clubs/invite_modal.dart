import 'package:drivelife/api/club_api_service.dart';
import 'package:flutter/material.dart';

class ClubInviteModal extends StatefulWidget {
  final String clubName;
  final String inviteId;
  final String notificationId;

  const ClubInviteModal({required this.clubName, required this.inviteId, required this.notificationId, super.key});

  @override
  State<ClubInviteModal> createState() => _ClubInviteModalState();
}

class _ClubInviteModalState extends State<ClubInviteModal> {
  bool _isLoading = false;
  static const Color _gold = Color(0xFFAE9159);

  Future<void> _handleAccept() async {
    setState(() => _isLoading = true);
    try {
      await ClubApiService.acceptClubAdminInvitation(widget.inviteId,widget.notificationId);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You\'ve joined ${widget.clubName}!'),
            backgroundColor: _gold,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept invite: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleDecline() async {
    Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icon ────────────────────────────────────────
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_rounded, color: _gold, size: 30),
            ),
            const SizedBox(height: 20),

            // ── Title ────────────────────────────────────────
            const Text(
              'Club Admin Invitation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),

            // ── Body ─────────────────────────────────────────
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
                children: [
                  const TextSpan(
                    text: "You've been invited to become an admin of ",
                  ),
                  TextSpan(
                    text: widget.clubName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const TextSpan(text: '. Would you like to accept?'),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Buttons ──────────────────────────────────────
            Row(
              children: [
                // Decline
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _handleDecline,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Decline',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Accept
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Accept',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),

            // Safe area padding for bottom sheet
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}
