import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:linkify/linkify.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// ignore: must_be_immutable
class FormattedText extends StatelessWidget {
  final String text;
  final double? fontSize;
  final Color? textColor;
  final int maxTextLength;
  final VoidCallback? onSuffixPressed;
  final bool showAllText;
  final String suffix;
  final String? parentText;
  final TextStyle? parentTextStyle;
  final VoidCallback? onParentPressed;
  final Function(String)? onUserTagPressed;
  final Function(String)? onHashtagPressed;

  FormattedText({
    Key? key,
    required this.text,
    this.maxTextLength = 300,
    this.showAllText = false,
    this.suffix = "Show more",
    this.fontSize,
    this.onSuffixPressed,
    this.parentText,
    this.parentTextStyle,
    this.textColor,
    this.onParentPressed,
    this.onUserTagPressed,
    this.onHashtagPressed,
  }) : _suffix = "...$suffix",
       _text = text.trim(),
       _fontSize = fontSize ?? 14,
       super(key: key);

  final double _fontSize;
  late ThemeProvider _theme;

  final String _text;

  final String _suffix;

  late final List<TextSpan> _spans = [];

  TextSpan _copyWith(TextSpan span, {String? text}) {
    return TextSpan(
      style: span.style,
      recognizer: span.recognizer,
      children: span.children,
      text: text ?? span.text,
    );
  }

  bool _isEmail(String? email) {
    if (email != null) {
      String source =
          r"[a-zA-Z0-9\+\.\_\%\-\+]{1,256}\\@[a-zA-Z0-9][a-zA-Z0-9\\-]{0,64}(\\.[a-zA-Z0-9][a-zA-Z0-9\\-]{0,25})+";
      return RegExp(source).hasMatch(email);
    }
    return false;
  }

  TextSpan get _parsedTextSpan {
    final List<TextSpan> spans = [];
    int length = 0;
    bool truncated = false;

    final elements = linkify(
      _text,
      options: const LinkifyOptions(removeWww: true, looseUrl: true),
      linkifiers: [
        const UrlLinkifier(),
        CustomUserTagLinkifier(),
        HashtagLinkifier(),
      ],
    );

    void addSpan(TextSpan span, String spanText) {
      if (truncated) return;

      if (!showAllText && length + spanText.length > maxTextLength) {
        final remaining = maxTextLength - length;
        if (remaining > 0) {
          spans.add(_copyWith(span, text: spanText.substring(0, remaining)));
        }
        truncated = true;
        return;
      }

      spans.add(span);
      length += spanText.length;
    }

    for (var element in elements) {
      if (element is UrlElement) {
        addSpan(
          TextSpan(
            text: element.text,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: _fontSize,
              color: _theme.primaryColor,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                final isEmail = _isEmail(element.text);
                if (isEmail) {
                  await launchUrl(Uri.parse("mailto:${element.text}"));
                } else {
                  await launchUrl(Uri.parse(element.url));
                }
              },
          ),
          element.text,
        );
      } else if (element is CustomUserTagElement) {
        addSpan(
          TextSpan(
            text: element.name,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: _fontSize,
              color: _theme.primaryColor,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => onUserTagPressed?.call(element.userId),
          ),
          element.name,
        );
      } else if (element is HashtagElement) {
        addSpan(
          TextSpan(
            text: element.title,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: _fontSize,
              color: _theme.primaryColor,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => onHashtagPressed?.call(element.title),
          ),
          element.title,
        );
      } else {
        addSpan(
          TextSpan(
            text: element.text,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: _fontSize,
              color: textColor ?? Colors.black.withOpacity(.8),
            ),
          ),
          element.text,
        );
      }
    }

    // Append suffix if collapsed+truncated, or expanded and text exceeds limit
    if (truncated || (showAllText && _text.length > maxTextLength)) {
      spans.add(
        TextSpan(
          text: _suffix,
          style: TextStyle(
            color: _theme.primaryColor,
            fontWeight: FontWeight.w600,
          ),
          recognizer: TapGestureRecognizer()..onTap = onSuffixPressed,
        ),
      );
    }

    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    _theme = Provider.of<ThemeProvider>(context);

    TextSpan child = _parsedTextSpan;

    if (parentText != null) {
      child = TextSpan(
        text: parentText,
        style: parentTextStyle,
        children: [child],
        recognizer: TapGestureRecognizer()..onTap = onParentPressed,
      );
    }

    final isCollapsed = !showAllText && _text.length > maxTextLength;

    return GestureDetector(
      onTap: isCollapsed ? onSuffixPressed : null,
      child: RichText(text: child),
    );
  }
}

class CustomUserTagLinkifier extends Linkifier {
  ///This matches any string in this format
  ///"@{userId}#{userName}#"
  final _userTagRegex = RegExp(r'^([\s\S]*?)(\@[^#]+\#[^#]+\#)', dotAll: true);
  @override
  List<LinkifyElement> parse(
    List<LinkifyElement> elements,
    LinkifyOptions options,
  ) {
    final list = <LinkifyElement>[];

    for (var element in elements) {
      if (element is TextElement) {
        final match = _userTagRegex.firstMatch(element.text);

        if (match == null) {
          list.add(element);
        } else {
          final text = element.text.replaceFirst(match.group(0)!, '');

          if (match.group(1)?.isNotEmpty == true) {
            list.add(TextElement(match.group(1)!));
          }

          if (match.group(2)?.isNotEmpty == true) {
            final blob = match.group(2)!.split("#");
            list.add(
              CustomUserTagElement(
                userId: blob.first.replaceAll("@", ""),
                name: "@${blob[1]}",
              ),
            );
          }

          if (text.isNotEmpty) {
            list.addAll(parse([TextElement(text)], options));
          }
        }
      } else {
        list.add(element);
      }
    }

    return list;
  }
}

class CustomUserTagElement extends LinkableElement {
  final String userId;
  final String name;
  CustomUserTagElement({required this.userId, required this.name})
    : super(userId, name);

  @override
  String toString() {
    return "CustomUserTagElement(userId: '$userId', name: $name)";
  }

  @override
  bool operator ==(other) => equals(other);

  @override
  int get hashCode => Object.hashAll([userId, name]);

  @override
  bool equals(other) =>
      other is CustomUserTagElement &&
      super.equals(other) &&
      other.userId == userId &&
      other.name == name;
}

class HashtagLinkifier extends Linkifier {
  ///This matches any string in this format
  ///"#{id}#{hashtagTitle}#"
  final _userTagRegex = RegExp(r'^([\s\S]*?)(\#[^#]+\#[^#]+\#)', dotAll: true);
  @override
  List<LinkifyElement> parse(
    List<LinkifyElement> elements,
    LinkifyOptions options,
  ) {
    final list = <LinkifyElement>[];

    for (var element in elements) {
      if (element is TextElement) {
        final match = _userTagRegex.firstMatch(element.text);

        if (match == null) {
          list.add(element);
        } else {
          final text = element.text.replaceFirst(match.group(0)!, '');

          if (match.group(1)?.isNotEmpty == true) {
            list.add(TextElement(match.group(1)!));
          }

          if (match.group(2)?.isNotEmpty == true) {
            final blob = match.group(2)!.split("#");
            list.add(HashtagElement(title: "#${blob[blob.length - 2]}"));
          }

          if (text.isNotEmpty) {
            list.addAll(parse([TextElement(text)], options));
          }
        }
      } else {
        list.add(element);
      }
    }

    return list;
  }
}

class HashtagElement extends LinkableElement {
  final String title;
  HashtagElement({required this.title}) : super(title, title);

  @override
  String toString() {
    return "HashtagElement(title: '$title')";
  }

  @override
  bool operator ==(other) => equals(other);

  @override
  int get hashCode => Object.hashAll([title]);

  @override
  bool equals(other) =>
      other is HashtagElement && super.equals(other) && other.title == title;
}
