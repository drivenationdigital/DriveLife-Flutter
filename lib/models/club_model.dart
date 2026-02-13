// Models
class ClubDetail {
  final String id;
  final String title;
  final List<String> categories;
  final String locationType; // 'local' or 'national'
  final String location;
  final String? clubEmail;
  final String? clubPhone;
  final String? website;
  final String? facebook;
  final String? instagram;
  final String? merchandiseLink;
  final String? description;
  final String? terms;
  final List<String> membershipQuestions;
  final List<String> administrators;
  final ImageInfo logo;
  final ImageInfo coverPhoto;
  final String status;

  ClubDetail({
    required this.id,
    required this.title,
    required this.categories,
    required this.locationType,
    required this.location,
    this.clubEmail,
    this.clubPhone,
    this.website,
    this.facebook,
    this.instagram,
    this.merchandiseLink,
    this.description,
    this.terms,
    this.membershipQuestions = const [],
    this.administrators = const [],
    required this.logo,
    required this.coverPhoto,
    required this.status,
  });
}

class ImageInfo {
  final String url;
  final int? width;
  final int? height;

  ImageInfo({required this.url, this.width, this.height});
}

class ClubCategoryList {
  final int id;
  final String name;
  final String slug;
  final int count;

  ClubCategoryList({
    required this.id,
    required this.name,
    required this.slug,
    required this.count,
  });

  factory ClubCategoryList.fromJson(Map<String, dynamic> json) {
    return ClubCategoryList(
      id: json['id'],
      name: json['name'],
      slug: json['slug'],
      count: json['count'],
    );
  }
}
