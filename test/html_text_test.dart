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

  test('the fallback is the text of the whole field', () {
    expect(
      stripHtml('<table><tr><td>Mon</td><td>9 til 5</td></tr></table>'),
      'Mon9 til 5',
    );
  });
}
