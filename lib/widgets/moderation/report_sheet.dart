import 'package:drivelife/api/moderation_api.dart';
import 'package:flutter/material.dart';

/// "Why are you reporting this?"
///
/// One sheet for everything reportable — a message, a post, a person —
/// because the reasons are the same and a second copy of this list is a
/// second thing to keep in step with dl_report_reasons() on the server.
///
/// Reporting is deliberately one tap deep. Somebody using it is often
/// upset, and a flow that asks them to confirm, categorise and explain
/// before anything happens is one they abandon.
class ReportSheet extends StatefulWidget {
  /// 'user', 'message', 'post', 'comment' — what the server stores.
  final String subjectType;

  /// Its id. A String, because a Supabase message id is a uuid and a
  /// WordPress post id is an int.
  final String subjectId;

  /// Who is responsible for it, when that is known.
  final int? subjectUserId;

  /// For a message: the surrounding ones. Stored with the report so a
  /// reviewer sees the conversation rather than one line of it — and so
  /// it survives the message being deleted.
  final List<Map<String, dynamic>>? context;

  /// Shown under the title, e.g. "Report this message".
  final String title;

  const ReportSheet({
    super.key,
    required this.subjectType,
    required this.subjectId,
    required this.title,
    this.subjectUserId,
    this.context,
  });

  /// Open it. Resolves to true when a report was filed.
  static Future<bool> show(
    BuildContext context, {
    required String subjectType,
    required String subjectId,
    required String title,
    int? subjectUserId,
    List<Map<String, dynamic>>? messageContext,
  }) async {
    final filed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ReportSheet(
        subjectType: subjectType,
        subjectId: subjectId,
        title: title,
        subjectUserId: subjectUserId,
        context: messageContext,
      ),
    );

    return filed ?? false;
  }

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason? _reason;
  final _detail = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _sending) return;

    setState(() => _sending = true);

    final ok = await ModerationAPI.report(
      subjectType: widget.subjectType,
      subjectId: widget.subjectId,
      reason: reason,
      detail: _detail.text,
      subjectUserId: widget.subjectUserId,
      context: widget.context,
    );

    if (!mounted) return;

    Navigator.pop(context, ok);

    // Said plainly either way. A report that silently failed is worse
    // than one that was never offered: the person believes it is dealt
    // with.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Thanks — our team will take a look.'
              : 'Could not send that report. Please try again.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The keyboard, when the detail box has focus.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Your report is anonymous — they will not be told who '
                'sent it.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),

              // RadioGroup rather than groupValue/onChanged on each
              // tile: those were deprecated after Flutter 3.32 and the
              // app is past it.
              RadioGroup<ReportReason>(
                groupValue: _reason,
                // Always a handler — RadioGroup's onChanged is not
                // nullable, so "disabled" has to be a no-op rather than
                // a null. The send button is what actually locks.
                onChanged: (v) {
                  if (_sending) return;
                  setState(() => _reason = v);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final reason in ReportReason.values)
                      RadioListTile<ReportReason>(
                        value: reason,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        title: Text(
                          reason.label,
                          style: const TextStyle(fontSize: 14.5),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              TextField(
                controller: _detail,
                enabled: !_sending,
                minLines: 2,
                maxLines: 4,
                // Not required. Somebody frightened enough to report
                // should not have to compose a paragraph first — the
                // category alone is a usable signal.
                decoration: InputDecoration(
                  hintText: 'Anything else we should know? (optional)',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _reason == null || _sending ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF111111),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Send report',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
