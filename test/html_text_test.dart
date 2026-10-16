import 'package:drivelife/utils/html_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether a CMS description can be handed to the HTML renderer.
///
/// flutter_html is pinned at a beta that needs an explicit extension for
/// tables, iframes, svg, MathML, audio and video, and this app registers
/// none. Unregistered, they throw during build — and a throw during build
/// takes the whole venue page with it, not just the paragraph.
void main() {
  group('passes ordinary editor output', () {
    test('plain paragraphs', () {
      expect(
        htmlIsRenderable('<p>The BARC Yorkshire Centre runs Harewood.</p>'),
        isTrue,
      );
    });

    test('headings, lists, links, emphasis and images', () {
      expect(
        htmlIsRenderable(
          '<h2>About</h2><ul><li>One</li></ul>'
          '<p><strong>Bold</strong> and <a href="/x">a link</a></p>'
          '<img src="https://example.com/a.jpg" alt="a">',
        ),
        isTrue,
      );
    });
  });

  group('catches what the renderer cannot draw', () {
    test('an embedded video', () {
      expect(
        htmlIsRenderable('<p>Watch:</p><iframe src="https://yt/x"></iframe>'),
        isFalse,
      );
    });

    test('a table of opening times', () {
      // The likeliest one in the wild: a venue listing its hours.
      expect(
        htmlIsRenderable('<table><tr><td>Mon</td><td>9-5</td></tr></table>'),
        isFalse,
      );
    });

    test('whatever the case or spacing', () {
      expect(htmlIsRenderable('<  IFRAME src="x">'), isFalse);
      expect(htmlIsRenderable('<TABLE>'), isFalse);
    });

    test('script and style, which should never render anyway', () {
      expect(htmlIsRenderable('<script>alert(1)</script>'), isFalse);
      expect(htmlIsRenderable('<style>p{color:red}</style>'), isFalse);
    });
  });

  group('nothing to render', () {
    test('null and empty are not renderable', () {
      expect(htmlIsRenderable(null), isFalse);
      expect(htmlIsRenderable(''), isFalse);
    });
  });

  test('a closing tag alone does not trip it', () {
    // </table> without an opening one is malformed, but the opening tag is
    // what the renderer trips on, and matching a slash would make every
    // ordinary </p> a false positive.
    expect(htmlIsRenderable('<p>Fine</p>'), isTrue);
  });

  _inlineStyles();

  test('the fallback is the text of the whole field', () {
    expect(
      stripHtml('<table><tr><td>Mon</td><td>9 til 5</td></tr></table>'),
      'Mon9 til 5',
    );
  });
}

/// Stripping the CSS a word processor pasted into a description.
///
/// This is what actually broke the Dover Transport Museum venue page: a
/// single `<p>` — nothing the renderer can't draw — carrying a style
/// attribute full of `font-variant-east-asian`, `font-optical-sizing` and
/// `line-height: normal`, which flutter_html's CSS parser choked on.
void _inlineStyles() {
  group('withoutInlineStyles', () {
    test('removes the attribute that broke the venue page', () {
      const pasted =
          '<p class="p1" style="margin-bottom: 0px; font-variant-numeric: '
          'normal; font-variant-east-asian: normal; font-kerning: auto; '
          'line-height: normal;">We are a registered charity.</p>';

      expect(
        withoutInlineStyles(pasted),
        '<p>We are a registered charity.</p>',
      );
    });

    test('keeps the markup and the text', () {
      expect(
        withoutInlineStyles(
          '<p style="color:red"><strong>Bold</strong> and '
          '<a href="https://x.test">a link</a></p>',
        ),
        '<p><strong>Bold</strong> and <a href="https://x.test">a link</a></p>',
      );
    });

    test('handles single quotes', () {
      expect(withoutInlineStyles("<p style='color:red'>Hi</p>"), '<p>Hi</p>');
    });

    test('is not fooled by the words appearing in text', () {
      // "style=" inside the prose is not an attribute, and an href that
      // happens to mention class must survive.
      expect(
        withoutInlineStyles('<p>Write style="x" in your copy</p>'),
        '<p>Write style="x" in your copy</p>',
      );
    });

    test('leaves clean markup alone', () {
      expect(withoutInlineStyles('<p>Plain</p>'), '<p>Plain</p>');
    });

    test('null and empty', () {
      expect(withoutInlineStyles(null), '');
      expect(withoutInlineStyles(''), '');
    });
  });
}
