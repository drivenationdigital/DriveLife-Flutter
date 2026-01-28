class CartItem {
  final String variantId;
  final String productId;
  final String name;
  final double price;
  final String image;
  final String currencySymbol;
  final String? selectedColorHex;
  final String? selectedColorName;
  final String? selectedSize;
  final String? supplierSku;
  final String? variant;
  int quantity;
  final bool? isOnSale;
  final double? originalPrice;

  CartItem({
    required this.variantId,
    required this.productId,
    required this.name,
    required this.price,
    required this.image,
    required this.currencySymbol,
    this.isOnSale,
    this.originalPrice,
    this.variant,
    this.selectedColorHex,
    this.selectedColorName,
    this.selectedSize,
    this.supplierSku,
    this.quantity = 1,
  });

  Map<String, dynamic> toJson() {
    return {
      'variantId': variantId,
      'productId': productId,
      'name': name,
      'price': price,
      'image': image,
      'variant': variant,
      'currencySymbol': currencySymbol,
      'selectedColorHex': selectedColorHex,
      'selectedColorName': selectedColorName,
      'selectedSize': selectedSize,
      'supplierSku': supplierSku,
      'quantity': quantity,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      variantId: json['variantId'] as String,
      productId: json['productId'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      currencySymbol: json['currencySymbol'] as String,
      image: json['image'] as String,
      variant: json['variant'] as String?,
      selectedColorHex: json['selectedColorHex'] as String?,
      selectedColorName: json['selectedColorName'] as String?,
      selectedSize: json['selectedSize'] as String?,
      supplierSku: json['supplierSku'] as String?,
      quantity: json['quantity'] as int,
    );
  }

  double get totalPrice => price * quantity;

  CartItem copyWith({
    String? variantId,
    String? productId,
    String? name,
    double? price,
    String? image,
    String? selectedColorHex,
    String? selectedColorName,
    String? selectedSize,
    String? supplierSku,
    String? currencySymbol,
    int? quantity,
  }) {
    return CartItem(
      variantId: variantId ?? this.variantId,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      price: price ?? this.price,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      image: image ?? this.image,
      selectedColorHex: selectedColorHex ?? this.selectedColorHex,
      selectedColorName: selectedColorName ?? this.selectedColorName,
      selectedSize: selectedSize ?? this.selectedSize,
      supplierSku: supplierSku ?? this.supplierSku,
      quantity: quantity ?? this.quantity,
    );
  }
}
