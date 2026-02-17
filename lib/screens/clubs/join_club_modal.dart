import 'package:flutter/material.dart';
import 'package:drivelife/api/club_api_service.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:provider/provider.dart';

/// Call this from your Join button:
///
/// onTap: () => showClubJoinModal(
///   context,
///   clubId: _clubData!['id'].toString(),
///   questions: List<String>.from(_clubData!['membership_questions'] ?? []),
/// )
void showClubJoinModal(
  BuildContext context, {
  required String clubId,
  required List<String> questions,
  required Function onSuccess,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ClubJoinModal(
      clubId: clubId,
      questions: questions,
      onSuccess: onSuccess,
    ),
  );
}

class ClubJoinModal extends StatefulWidget {
  final String clubId;
  final List<String> questions;
  final Function onSuccess;

  const ClubJoinModal({
    super.key,
    required this.clubId,
    required this.questions,
    required this.onSuccess,
  });

  @override
  State<ClubJoinModal> createState() => _ClubJoinModalState();
}

class _ClubJoinModalState extends State<ClubJoinModal> {
  late List<TextEditingController> _controllers;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.questions.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Validate all answered
    final unanswered = _controllers.any((c) => c.text.trim().isEmpty);
    if (unanswered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer all questions.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final payload = List.generate(
      widget.questions.length,
      (i) => {
        'question': widget.questions[i],
        'answer': _controllers[i].text.trim(),
      },
    );

    final success = await ClubApiService.submitJoinRequest(
      clubId: widget.clubId,
      questionsAndAnswers: payload,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    Navigator.pop(context);

    if (success) {
      widget.onSuccess();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Request sent! The club owner will review your application.'
              : 'Something went wrong. Please try again.',
        ),
        backgroundColor: success ? Colors.green.shade600 : Colors.red.shade400,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Membership Questions',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 22, color: Colors.grey),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            'To validate your membership request, the club would like you to fill out the below questions before joining:',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 20),

          // Questions
          ...List.generate(
            widget.questions.length,
            (i) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.questions[i],
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controllers[i],
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Enter your answer',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: theme.primaryColor),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Submit Now',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
