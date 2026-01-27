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

  double get subtotal => _cart.fold(0.0, (sum, item) => sum + item.totalPrice);

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
    required String variantId,
    required String productId,
    required String name,
    required double price,
    required String image,
    String? selectedColor,
    int quantity = 1,
  }) async {
    // Check if item already exists in cart
    final existingIndex = _cart.indexWhere(
      (item) =>
          item.variantId == variantId && item.selectedColor == selectedColor,
    );

    if (existingIndex != -1) {
      // Update quantity of existing item
      _cart[existingIndex].quantity += quantity;
    } else {
      // Add new item to cart
      _cart.add(
        CartItem(
          variantId: variantId,
          productId: productId,
          name: name,
          price: price,
          image: image,
          selectedColor: selectedColor,
          quantity: quantity,
        ),
      );
    }

    await _saveCart();
    notifyListeners();
  }

  // Remove item from cart
  Future<void> removeFromCart(String variantId, {String? selectedColor}) async {
    _cart.removeWhere(
      (item) =>
          item.variantId == variantId && item.selectedColor == selectedColor,
    );
    await _saveCart();
    notifyListeners();
  }

  // Update item quantity
  Future<void> updateQuantity(
    String variantId,
    int quantity, {
    String? selectedColor,
  }) async {
    if (quantity <= 0) {
      await removeFromCart(variantId, selectedColor: selectedColor);
      return;
    }

    final index = _cart.indexWhere(
      (item) =>
          item.variantId == variantId && item.selectedColor == selectedColor,
    );

    if (index != -1) {
      _cart[index].quantity = quantity;
      await _saveCart();
      notifyListeners();
    }
  }

  // Increment quantity
  Future<void> incrementQuantity(
    String variantId, {
    String? selectedColor,
  }) async {
    final index = _cart.indexWhere(
      (item) =>
          item.variantId == variantId && item.selectedColor == selectedColor,
    );

    if (index != -1) {
      _cart[index].quantity++;
      await _saveCart();
      notifyListeners();
    }
  }

  // Decrement quantity
  Future<void> decrementQuantity(
    String variantId, {
    String? selectedColor,
  }) async {
    final index = _cart.indexWhere(
      (item) =>
          item.variantId == variantId && item.selectedColor == selectedColor,
    );

    if (index != -1) {
      if (_cart[index].quantity > 1) {
        _cart[index].quantity--;
        await _saveCart();
        notifyListeners();
      } else {
        await removeFromCart(variantId, selectedColor: selectedColor);
      }
    }
  }

  // Clear entire cart
  Future<void> clearCart() async {
    _cart.clear();
    await _saveCart();
    notifyListeners();
  }

  // Check if item is in cart
  bool isInCart(String variantId, {String? selectedColor}) {
    return _cart.any(
      (item) =>
          item.variantId == variantId && item.selectedColor == selectedColor,
    );
  }

  // Get quantity of specific item in cart
  int getItemQuantity(String variantId, {String? selectedColor}) {
    final item = _cart.firstWhere(
      (item) =>
          item.variantId == variantId && item.selectedColor == selectedColor,
      orElse: () => CartItem(
        variantId: '',
        productId: '',
        name: '',
        price: 0,
        image: '',
        quantity: 0,
      ),
    );
    return item.quantity;
  }
}
