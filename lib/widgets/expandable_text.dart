import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:linkify/linkify.dart';
import 'package:url_launcher/url_launcher.dart';

/// Text that starts clipped, opens on a tap, and makes its links
/// tappable.
///
/// ── WHY THE TOGGLE IS NOT ALWAYS THERE ──────────────────────────────
///
/// Because most of the time there is nothing to expand. A DriveLife
/// upload's description is usually a line or two, and a "Read more"
/// under a line and a half is a control that does nothing - somebody
/// taps it, nothing visible happens, and they stop trusting the next
/// one.
///
/// So the text is MEASURED first, at the width it will actually be
/// drawn at, and the toggle appears only when it genuinely overflows.
/// That is what the LayoutBuilder and TextPainter below are for; there
/// is no reliable shortcut, because whether a given string exceeds
/// three lines depends on the font, the scale factor and the width,
/// none of which are known until layout.
///
/// ── AND WHY NOT FormattedText ───────────────────────────────────────
///
/// The app already has a widget that linkifies, and it is built for
/// the feed: it truncates by CHARACTER COUNT rather than by lines, and
/// it also parses hashtags and DriveLife user tags, neither of which
/// means anything in a video description pulled off YouTube.
///
/// Clipping by characters is the part that matters. Three lines is a
/// shape somebody can see; three hundred characters is a number that
/// lands mid-word in a different place on every screen width.
class ExpandableText extends StatefulWidget {
  const ExpandableText(
    this.text, {
    super.key,
    required this.style,
    required this.toggleStyle,
    required this.linkStyle,
    this.maxLines = 3,
    this.moreLabel = 'Read more',
    this.lessLabel = 'Show less',
  });

  final String text;
  final TextStyle style;

  /// The Read more / Show less line. Passed in rather than derived,
  /// because the one thing it must do is look tappable against
  /// whatever this text sits on, and only the caller knows that.
  final TextStyle toggleStyle;

  /// URLs and email addresses within the text.
  final TextStyle linkStyle;

  /// How much shows before it is cut.
  final int maxLines;

  final String moreLabel;
  final String lessLabel;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _open = false;

  /// Held so they can be disposed. A TapGestureRecognizer left behind
  /// by a rebuilt span is a leak, and a description full of links
  /// rebuilds on every expand and collapse.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void didUpdateWidget(ExpandableText oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A different description is a different decision. Without this,
    // opening one video's notes and moving to the next would show the
    // next one already expanded.
    if (oldWidget.text != widget.text) _open = false;
  }

  @override
  void dispose() {
    _disposeRecognizers();

    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }

    _recognizers.clear();
  }

  Future<void> _launch(String url) async {
    // externalApplication so a YouTube or Instagram link opens in its
    // own app rather than a webview where nobody is signed in.
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((Object e) {
      debugPrint('[description] could not open $url: $e');

      return false;
    });

    if (opened || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open that link.')),
    );
  }

  /// The text as spans, with the links picked out.
  ///
  /// Built once per build and used for BOTH the measurement and the
  /// drawing - measuring one thing and rendering another is how a
  /// "Read more" ends up on text that does not overflow.
  TextSpan _spans(String text) {
    _disposeRecognizers();

    final elements = linkify(
      text,
      // ── EMAIL FIRST, AND IT MATTERS ────────────────────────────
      //
      // The default order runs the URL linkifier first, and with
      // looseUrl on it claims "hi@example.com" as a web address -
      // tapping it tried to open http://hi@example.com. Email has to
      // get first refusal.
      linkifiers: const [EmailLinkifier(), UrlLinkifier()],
      options: const LinkifyOptions(
        // ── humanize, NOT raw ──────────────────────────────────
        //
        // This was false, on the reasoning that it would show the URL
        // as somebody typed it. It does the opposite: the element's
        // text becomes the NORMALISED url, so "example.com/kit" was
        // displayed as "http://example.com/kit". humanize keeps the
        // written form for display and leaves the full url for the
        // tap.
        humanize: true,
        removeWww: true,
        // So "example.com/thing" is a link without needing https://
        // in front of it, which is how people type them.
        looseUrl: true,
      ),
    );

    return TextSpan(
      style: widget.style,
      children: [
        for (final element in elements)
          if (element is UrlElement)
            TextSpan(
              text: element.text,
              style: widget.linkStyle,
              recognizer: _tap(() => _launch(element.url)),
            )
          else if (element is EmailElement)
            TextSpan(
              text: element.text,
              style: widget.linkStyle,
              recognizer: _tap(() => _launch('mailto:${element.emailAddress}')),
            )
          else
            TextSpan(text: element.text),
      ],
    );
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;

    _recognizers.add(recognizer);

    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();

    if (text.isEmpty) return const SizedBox.shrink();

    final span = _spans(text);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: span,
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          // So the measurement matches what the person has actually
          // set their phone to, not a default nobody is using.
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);

        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: Text.rich(
                span,
                maxLines: _open ? null : widget.maxLines,
                overflow: _open ? TextOverflow.clip : TextOverflow.ellipsis,
              ),
            ),

            if (overflows)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  // Generous above, so the words are clear of the text
                  // they belong to; generous below, so the tap target
                  // is a real one rather than a line of 13pt type.
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Text(
                    _open ? widget.lessLabel : widget.moreLabel,
                    style: widget.toggleStyle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
