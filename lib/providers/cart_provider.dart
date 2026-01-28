import 'dart:convert';
import 'package:drivelife/models/cart_item.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartProvider with ChangeNotifier {
  List<CartItem> _cart = [];
  static const String _cartKey = 'cart_items';

  List<CartItem> get cart => _cart;

  int get itemCount => _cart.length;

  int get totalQuantity => _cart.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      _cart.fold(0.0, (sum, item) => sum + item.price * item.quantity);

  double get tax => subtotal * 0.2; // 20% VAT

  double get total => subtotal + tax;

  // Initialize cart from local storage
  Future<void> loadCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartData = prefs.getString(_cartKey);

      if (cartData != null) {
        final List<dynamic> decodedData = json.decode(cartData);
        _cart = decodedData.map((item) => CartItem.fromJson(item)).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading cart: $e');
    }
  }

  // Save cart to local storage
  Future<void> _saveCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartData = json.encode(_cart.map((item) => item.toJson()).toList());
      await prefs.setString(_cartKey, cartData);
    } catch (e) {
      debugPrint('Error saving cart: $e');
    }
  }

  // Add item to cart
  Future<void> addToCart({
    required String productId,
    required String name,
    required double price,
    required String image,
    required String currencySymbol,
    bool? isOnSale,
    double? originalPrice,
    String? variant,
    String? selectedColorHex,
    String? selectedColorName,
    String? selectedSize,
    String? supplierSku,
    int quantity = 1,
  }) async {
    // Create unique variant ID
    final variantId =
        '${productId}_${selectedColorHex ?? 'default'}_${selectedSize ?? 'default'}';

    // Check if item already exists
    final existingIndex = _cart.indexWhere(
      (item) => item.variantId == variantId,
    );

    if (existingIndex != -1) {
      _cart[existingIndex].quantity += quantity;
    } else {
      _cart.add(
        CartItem(
          variantId: variantId,
          productId: productId,
          name: name,
          price: price,
          isOnSale: isOnSale,
          currencySymbol: currencySymbol,
          originalPrice: originalPrice,
          image: image,
          variant: variant,
          selectedColorHex: selectedColorHex,
          selectedColorName: selectedColorName,
          selectedSize: selectedSize,
          supplierSku: supplierSku,
          quantity: quantity,
        ),
      );
    }

    await _saveCart();
    notifyListeners();
  }

  // Updated remove/update methods to use variantId only
  Future<void> removeFromCart(String variantId) async {
    _cart.removeWhere((item) => item.variantId == variantId);
    await _saveCart();
    notifyListeners();
  }

  Future<void> updateQuantity(String variantId, int quantity) async {
    if (quantity <= 0) {
      await removeFromCart(variantId);
      return;
    }

    final index = _cart.indexWhere((item) => item.variantId == variantId);

    if (index != -1) {
      _cart[index].quantity = quantity;
      await _saveCart();
      notifyListeners();
    }
  }

  Future<void> incrementQuantity(String variantId) async {
    final index = _cart.indexWhere((item) => item.variantId == variantId);

    if (index != -1) {
      _cart[index].quantity++;
      await _saveCart();
      notifyListeners();
    }
  }

  Future<void> decrementQuantity(String variantId) async {
    final index = _cart.indexWhere((item) => item.variantId == variantId);

    if (index != -1) {
      if (_cart[index].quantity > 1) {
        _cart[index].quantity--;
        await _saveCart();
        notifyListeners();
      } else {
        await removeFromCart(variantId);
      }
    }
  }

  bool isInCart(String variantId) {
    return _cart.any((item) => item.variantId == variantId);
  }

  int getItemQuantity(String variantId) {
    final item = _cart.firstWhere(
      (item) => item.variantId == variantId,
      orElse: () => CartItem(
        variantId: '',
        productId: '',
        name: '',
        price: 0,
        image: '',
        quantity: 0,
        currencySymbol: '',
      ),
    );
    return item.quantity;
  }

  // Clear entire cart
  Future<void> clearCart() async {
    _cart.clear();
    await _saveCart();
    notifyListeners();
  }
}
