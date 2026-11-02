import 'package:flutter/material.dart';

/// A heading followed by one or more paragraphs.
///
/// Paragraphs beginning with "• " are rendered as indented bullet points;
/// paragraphs beginning with "## " are rendered as bold sub-headings.
class PolicySection {
  final String heading;
  final List<String> paragraphs;

  const PolicySection(this.heading, this.paragraphs);
}

/// Shared bottom-sheet renderer used by [TermsModal] and [PrivacyModal].
///
/// Keeps layout in one place so the legal text files contain content only.
class PolicyModal extends StatelessWidget {
  final String title;
  final List<String> intro;
  final List<PolicySection> sections;

  const PolicyModal({
    super.key,
    required this.title,
    this.intro = const [],
    required this.sections,
  });

  static const TextStyle _bodyStyle = TextStyle(height: 1.5);
  static const TextStyle _headingStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final paragraph in intro) ...[
                        _Paragraph(paragraph),
                        const SizedBox(height: 12),
                      ],
                      if (intro.isNotEmpty) const SizedBox(height: 8),
                      for (final section in sections) ...[
                        Text(section.heading, style: _headingStyle),
                        const SizedBox(height: 12),
                        for (final paragraph in section.paragraphs) ...[
                          _Paragraph(paragraph),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Paragraph extends StatelessWidget {
  final String text;

  const _Paragraph(this.text);

  @override
  Widget build(BuildContext context) {
    if (text.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          text.substring(3),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            height: 1.5,
          ),
        ),
      );
    }
    final isBullet = text.startsWith('• ');
    if (!isBullet) {
      return Text(text, style: PolicyModal._bodyStyle);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: PolicyModal._bodyStyle),
          Expanded(
            child: Text(text.substring(2), style: PolicyModal._bodyStyle),
          ),
        ],
      ),
    );
  }
}
