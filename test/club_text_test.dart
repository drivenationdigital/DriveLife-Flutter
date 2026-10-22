import 'package:drivelife/utils/html_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the groups screen does to a raw API value before showing it.
///
/// `_clubText` is private, so this covers the helper it leans on. The two
/// faults it has to survive both came from the same field: club_category
/// is an ACF multi-select over a taxonomy, so it arrives as a LIST of
/// values, and WordPress stores the names HTML-encoded.
void main() {
  test('entities are decoded, not printed', () {
    // "Sports & Performance" is stored like this, and the banner was
    // showing the raw entity above the group's name.
    expect(decodeHtmlText('Sports &amp; Performance'), 'Sports & Performance');
  });

  test('the other entities a category name can carry', () {
    expect(decodeHtmlText('Mini &#038; Co'), 'Mini & Co');
    expect(decodeHtmlText('Owners&#8217; Club'), 'Owners\u2019 Club');
    expect(decodeHtmlText('&quot;Fast&quot; Club'), '"Fast" Club');
  });

  test('plain text is left exactly as it is', () {
    expect(
      decodeHtmlText('Classic Vehicle Society'),
      'Classic Vehicle Society',
    );
    // A name that is only a number is a real possibility in a car app and
    // must survive: 911, 944, 205. Nothing may strip it as "looks like an
    // id", which is the tempting shortcut after a term id leaked through.
    expect(decodeHtmlText('911'), '911');
  });

  test('nothing in, nothing out', () {
    expect(decodeHtmlText(null), '');
    expect(decodeHtmlText(''), '');
  });
}
