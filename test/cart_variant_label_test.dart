import 'package:drivelife/models/cart_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// The line under a product's name in the basket and the checkout.
///
/// ── THE BUG THIS PINS ───────────────────────────────────────────────
///
/// The checkout read selectedColorName and selectedSize through `!`.
/// The DriveTag has a colour and no size, so that threw — and an
/// exception thrown inside a builder takes out the whole subtree, so
/// the page rendered as the plain grey box a release build paints in
/// place of the red error screen. Proceed to Checkout led nowhere.
///
/// Every product with only one of the two hit it, which is most of them.
void main() {
  CartItem item({String? colour, String? size}) => CartItem(
    variantId: 'v1',
    productId: 'p1',
    name: 'DriveTag — Your car, your story',
    price: 0,
    image: '',
    currencySymbol: '£',
    selectedColorName: colour,
    selectedSize: size,
  );

  test('a colour and a size read as one line', () {
    expect(item(colour: 'Black', size: 'Large').variantLabel, 'Black · Large');
  });

  test('a colour and no size is just the colour', () {
    // The DriveTag. This is the one that brought the page down.
    expect(item(colour: 'Black').variantLabel, 'Black');
  });

  test('a size and no colour is just the size', () {
    expect(item(size: 'Large').variantLabel, 'Large');
  });

  test('neither is empty, not an error and not a stray separator', () {
    expect(item().variantLabel, '');
  });

  test('an empty string counts as absent', () {
    // The API sends '' as readily as it sends null, and " · Large" is
    // not a thing anybody should see.
    expect(item(colour: '', size: 'Large').variantLabel, 'Large');
    expect(item(colour: 'Black', size: '').variantLabel, 'Black');
    expect(item(colour: '', size: '').variantLabel, '');
  });

  test('whitespace counts as absent too', () {
    expect(item(colour: '   ', size: 'Large').variantLabel, 'Large');
  });
}
