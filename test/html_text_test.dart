import 'package:drivelife/utils/html_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeHtmlText', () {
    test('decodes the entities WooCommerce actually sends', () {
      expect(decodeHtmlText('Brands &amp; Clubs'), 'Brands & Clubs');
      expect(decodeHtmlText('Driver&#8217;s Tee'), 'Driver’s Tee');
      expect(decodeHtmlText('Driver&rsquo;s Tee'), 'Driver’s Tee');
      expect(decodeHtmlText('&quot;Slammed&quot;'), '"Slammed"');
      expect(decodeHtmlText('S &lt; M &gt; L'), 'S < M > L');
    });

    test('leaves plain text alone, so it is safe to apply while parsing', () {
      expect(decodeHtmlText('Plain Product Name'), 'Plain Product Name');
      expect(decodeHtmlText('Café Racer — 3/4 sleeve'), 'Café Racer — 3/4 sleeve');
    });

    test('handles null and empty', () {
      expect(decodeHtmlText(null), '');
      expect(decodeHtmlText(''), '');
    });
  });

  group('stripHtml', () {
    test('removes markup as well as entities', () {
      expect(
        stripHtml('<span class="woocommerce-Price-amount">&pound;30.00</span>'),
        '£30.00',
      );
      expect(stripHtml('<p>Tough &amp; light</p>'), 'Tough & light');
    });

    test('trims the whitespace block markup leaves behind', () {
      expect(stripHtml('<p>  Spaced  </p>'), 'Spaced');
    });
  });
}
