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
