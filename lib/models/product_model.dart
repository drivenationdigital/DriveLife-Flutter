class Product {
  final int id;
  final String name;
  final String permalink;
  final String image;
  final double price;
  final double? salePrice;
  final String formattedPrice;
  final String? formattedSalePrice;
  final bool isOnSale;
  final String currencySymbol;
  final bool inStock;
  final String stockStatus;
  final List<ProductColour> colours;
  final List<String> sizes;
  final List<String>? gallery;
  final String? description;
  final String? sku;
  final String? variant;
  final String? shortDescription;

  Product({
    required this.id,
    required this.name,
    required this.permalink,
    required this.image,
    required this.price,
    this.salePrice,
    required this.formattedPrice,
    this.formattedSalePrice,
    required this.isOnSale,
    required this.currencySymbol,
    required this.inStock,
    required this.stockStatus,
    required this.colours,
    required this.sizes,
    this.variant,
    this.gallery,
    this.description,
    this.shortDescription,
    this.sku,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      name: json['name'] as String,
      permalink: json['permalink'] as String,
      image: json['image'] as String,
      price: (json['price'] as num).toDouble(),
      salePrice: json['sale_price'] != null
          ? (json['sale_price'] as num).toDouble()
          : null,
      formattedPrice: json['formatted_price'] as String,
      formattedSalePrice: json['formatted_sale_price'] as String?,
      isOnSale: json['is_on_sale'] as bool,
      currencySymbol: json['currency_symbol'] as String,
      inStock: json['in_stock'] as bool,
      stockStatus: json['stock_status'] as String,
      variant: json['variant'] as String?,
      colours:
          (json['colours'] as List<dynamic>?)
              ?.map((e) => ProductColour.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      sizes:
          (json['sizes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      gallery: (json['gallery'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      description: json['description'] as String?,
      shortDescription: json['short_description'] as String?,
      sku: json['sku'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'permalink': permalink,
      'image': image,
      'price': price,
      'sale_price': salePrice,
      'formatted_price': formattedPrice,
      'formatted_sale_price': formattedSalePrice,
      'is_on_sale': isOnSale,
      'currency_symbol': currencySymbol,
      'in_stock': inStock,
      'stock_status': stockStatus,
      'colours': colours.map((e) => e.toJson()).toList(),
      'sizes': sizes,
      'gallery': gallery,
      'description': description,
      'short_description': shortDescription,
      'sku': sku,
    };
  }

  // Helper to get just hex colors for backward compatibility
  List<String> get colorHexes => colours.map((c) => c.hex).toList();

  // Get effective price (sale price if on sale, otherwise regular)
  double get effectivePrice => salePrice ?? price;

  // Get formatted effective price
  String get effectiveFormattedPrice => formattedSalePrice ?? formattedPrice;
}

class ProductColour {
  final String hex;
  final String name;
  final String sku;
  final String? mockupFront;

  ProductColour({
    required this.hex,
    required this.name,
    required this.sku,
    this.mockupFront,
  });

  factory ProductColour.fromJson(Map<String, dynamic> json) {
    return ProductColour(
      hex: json['hex'] as String,
      name: json['name'] as String,
      sku: json['sku'] as String? ?? '',
      mockupFront: json['mockup_front'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'hex': hex, 'name': name, 'sku': sku, 'mockup_front': mockupFront};
  }
}

class ProductsResponse {
  final bool success;
  final List<Product> products;
  final Pagination? pagination;
  final CategoryInfo? category;

  ProductsResponse({
    required this.success,
    required this.products,
    this.pagination,
    this.category,
  });

  factory ProductsResponse.fromJson(Map<String, dynamic> json) {
    print(json);
    return ProductsResponse(
      success: json['success'] as bool,
      products: (json['data'] as List<dynamic>)
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList(),
      pagination: json['pagination'] != null
          ? Pagination.fromJson(json['pagination'] as Map<String, dynamic>)
          : null,
      category: json['category'] != null
          ? CategoryInfo.fromJson(json['category'] as Map<String, dynamic>)
          : null,
    );
  }
}

class Pagination {
  final int total;
  final int totalPages;
  final int currentPage;
  final int perPage;

  Pagination({
    required this.total,
    required this.totalPages,
    required this.currentPage,
    required this.perPage,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      total: json['total'] as int,
      totalPages: json['total_pages'] as int,
      currentPage: json['current_page'] as int,
      perPage: json['per_page'] as int,
    );
  }

  bool get hasNextPage => currentPage < totalPages;
  bool get hasPreviousPage => currentPage > 1;
}

class CategoryInfo {
  final String name;
  final String slug;
  final String description;

  CategoryInfo({
    required this.name,
    required this.slug,
    required this.description,
  });

  factory CategoryInfo.fromJson(Map<String, dynamic> json) {
    return CategoryInfo(
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String,
    );
  }
}
