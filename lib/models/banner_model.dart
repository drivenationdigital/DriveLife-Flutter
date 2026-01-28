class ProductsBanner {
  final String title;
  final String subtitle;
  final String backgroundImage;
  final String bannerImage;
  final String linkUrl;
  final String linkTitle;
  final bool hideText;

  ProductsBanner({
    required this.title,
    required this.subtitle,
    required this.backgroundImage,
    required this.bannerImage,
    required this.linkUrl,
    required this.linkTitle,
    required this.hideText,
  });

  factory ProductsBanner.fromJson(Map<String, dynamic> json) {
    return ProductsBanner(
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      backgroundImage: json['background_image'] as String,
      bannerImage: json['banner_image'] as String,
      linkUrl: json['link_url'] as String,
      linkTitle: json['link_title'] as String,
      hideText: json['hide_text'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'subtitle': subtitle,
      'background_image': backgroundImage,
      'banner_image': bannerImage,
      'link_url': linkUrl,
      'link_title': linkTitle,
      'hide_text': hideText,
    };
  }

  // Extract category slug from URL
  String? get categorySlug {
    try {
      final uri = Uri.parse(linkUrl);
      final segments = uri.pathSegments;
      return segments.isNotEmpty ? segments.first : null;
    } catch (e) {
      return null;
    }
  }
}

class ProductsBannersResponse {
  final bool success;
  final List<ProductsBanner> banners;

  ProductsBannersResponse({required this.success, required this.banners});

  factory ProductsBannersResponse.fromJson(Map<String, dynamic> json) {
    return ProductsBannersResponse(
      success: json['success'] as bool,
      banners: (json['data'] as List<dynamic>)
          .map((e) => ProductsBanner.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
