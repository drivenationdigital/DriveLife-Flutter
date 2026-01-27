class CartItem {
  final String variantId;
  final String productId;
  final String name;
  final double price;
  final String image;
  final String? selectedColor;
  int quantity;

  CartItem({
    required this.variantId,
    required this.productId,
    required this.name,
    required this.price,
    required this.image,
    this.selectedColor,
    this.quantity = 1,
  });

  // Convert CartItem to Map for storage
  Map<String, dynamic> toJson() {
    return {
      'variantId': variantId,
      'productId': productId,
      'name': name,
      'price': price,
      'image': image,
      'selectedColor': selectedColor,
      'quantity': quantity,
    };
  }

  // Create CartItem from Map
  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      variantId: json['variantId'] as String,
      productId: json['productId'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      image: json['image'] as String,
      selectedColor: json['selectedColor'] as String?,
      quantity: json['quantity'] as int,
    );
  }

  // Calculate total price for this item
  double get totalPrice => price * quantity;

  // Create a copy with updated fields
  CartItem copyWith({
    String? variantId,
    String? productId,
    String? name,
    double? price,
    String? image,
    String? selectedColor,
    int? quantity,
  }) {
    return CartItem(
      variantId: variantId ?? this.variantId,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      price: price ?? this.price,
      image: image ?? this.image,
      selectedColor: selectedColor ?? this.selectedColor,
      quantity: quantity ?? this.quantity,
    );
  }
}
