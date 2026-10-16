/// WordPress and WooCommerce return HTML-encoded text in JSON: a product called
/// "Brands & Clubs" arrives as "Brands &amp; Clubs", and the editor's smart
/// quotes arrive as `&#8217;` / `&rsquo;`. Rendered straight into a [Text]
/// widget, the user reads the entity rather than the character.
///
/// Decoding belongs at the model boundary, not at each render site — a name
/// travels from the shop grid into the cart, the checkout and the order
/// confirmation, and every one of those has to get it right.
library;

import 'package:html_unescape/html_unescape.dart';

/// Shared instance — building one per call allocates its (large) entity table
/// every time, and names are decoded on a list-building hot path.
final HtmlUnescape _unescape = HtmlUnescape();

/// Decodes HTML entities in a plain-text string.
///
/// For things that are text and only text — product names, colour names,
/// category names. Safe on strings that hold no entities, so it can be applied
/// unconditionally while parsing.
String decodeHtmlText(String? value) {
  if (value == null || value.isEmpty) return '';
  return _unescape.convert(value);
}

/// Decodes entities *and* removes markup, for fields that may carry real HTML
/// (WooCommerce descriptions are authored in the block editor and come back
/// wrapped in `<p>`).
///
/// Do not use this on a string that is about to be handed to an HTML renderer —
/// it is for showing rich text inside a plain [Text].
String stripHtml(String? value) {
  if (value == null || value.isEmpty) return '';
  return _unescape.convert(value).replaceAll(RegExp(r'<[^>]*>'), '').trim();
}

/// Tags this app's HTML renderer cannot draw.
///
/// flutter_html is pinned at 3.0.0-beta.2 and needs an explicit extension for
/// several of these — tables, iframes, svg, MathML, audio and video all go
/// through `extensions:`, and nothing in this app registers any. Unregistered,
/// they are not ignored: the build throws, and a throw during build takes the
/// whole page with it rather than the one paragraph it came from.
///
/// The rest are tags that have no business rendering inside a description
/// whatever the renderer supports.
const Set<String> _unrenderableTags = {
  'audio',
  'canvas',
  'embed',
  'form',
  'iframe',
  'math',
  'object',
  'script',
  'style',
  'svg',
  'table',
  'video',
};

/// Matches an opening tag and captures its name.
final RegExp _openingTag = RegExp(
  r'<\s*([a-zA-Z][a-zA-Z0-9]*)',
  multiLine: true,
);

/// Whether [html] is safe to hand to an HTML renderer.
///
/// False means "show this as plain text instead". It is a check rather than a
/// sanitiser on purpose: stripping the offending tags out of a description
/// leaves the surrounding markup in a state nobody authored — a table's cells
/// run together into one paragraph, a video caption floats with nothing above
/// it. Falling back to the text of the whole field is honest about what
/// happened and always reads as something.
///
/// A field authored in the block editor — paragraphs, headings, lists, links,
/// bold, images — passes, which is nearly all of them.
bool htmlIsRenderable(String? html) {
  if (html == null || html.isEmpty) return false;

  for (final match in _openingTag.allMatches(html)) {
    final tag = match.group(1)?.toLowerCase();
    if (tag != null && _unrenderableTags.contains(tag)) return false;
  }

  return true;
}

/// Matches a whole tag, opening or closing.
final RegExp _anyTag = RegExp(r'<[^>]*>');

/// Matches an inline `style` or `class` attribute, quoted either way.
final RegExp _inlineAttr = RegExp(
  r'''\s(?:style|class)\s*=\s*(?:"[^"]*"|'[^']*')''',
  caseSensitive: false,
);

/// Strips inline `style` and `class` attributes out of CMS HTML.
///
/// flutter_html parses every inline style through its own CSS parser, and
/// that parser is where this app's venue pages were dying. The markup that
/// did it was a single `<p>` — nothing exotic in the tags at all — carrying
/// a style attribute pasted out of a word processor:
///
///     <p class="p1" style="margin-bottom: 0px; font-variant-numeric: normal;
///     font-variant-east-asian: normal; font-kerning: auto;
///     font-optical-sizing: auto; font-variation-settings: normal;
///     font-stretch: normal; line-height: normal;">
///
/// Whichever of those properties it choked on is beside the point: the fix
/// is not to hand it CSS we did not write. Every call site already gives the
/// renderer a `style:` map of its own, so the inline declarations were only
/// ever fighting with it — a line height pasted from Pages is not a decision
/// anyone made about how this app should look.
///
/// `class` goes too. There is no stylesheet here for a class to name, so it
/// is bytes the parser reads and discards.
String withoutInlineStyles(String? html) {
  if (html == null || html.isEmpty) return '';

  // Inside tags only. Run across the whole string, the attribute pattern
  // also matches the words `style="x"` written in the prose itself, and
  // quietly eats them out of the sentence.
  return html.replaceAllMapped(
    _anyTag,
    (match) => match.group(0)!.replaceAll(_inlineAttr, ''),
  );
}
