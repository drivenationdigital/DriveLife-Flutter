class ClubCategory {
  final int termId;
  final String name;
  final String slug;

  ClubCategory({required this.termId, required this.name, required this.slug});

  factory ClubCategory.fromJson(Map<String, dynamic> json) {
    return ClubCategory(
      termId: json['term_id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'term_id': termId, 'name': name, 'slug': slug};
  }
}

class ClubAdministrator {
  final String? userId;
  final String? invitationId;
  final String email;
  final String status; // 'active' or 'invited'

  ClubAdministrator({
    this.userId,
    this.invitationId,
    required this.email,
    required this.status,
  });

  factory ClubAdministrator.fromJson(Map<String, dynamic> json) {
    return ClubAdministrator(
      userId: json['user_id'] as String?,
      invitationId: json['invitation_id'] as String?,
      email: json['email'] as String,
      status: json['status'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (userId != null) 'user_id': userId,
      if (invitationId != null) 'invitation_id': invitationId,
      'email': email,
      'status': status,
    };
  }

  bool get isActive => status == 'active';
  bool get isInvited => status == 'invited';
}

class ClubEditData {
  final String clubId;
  final String clubTitle;
  final ClubCategories categories;
  final int clubLocationType;
  final String clubLocation;
  final String latitude;
  final String longitude;
  final String? logo;
  final String? coverImage;
  final String clubEmail;
  final String website;
  final String facebook;
  final String instagram;
  final String merchandiseLink;
  final String description;
  final List<String> membershipQuestions;
  final String clubTerms;
  final List<ClubAdministrator> administrators;

  ClubEditData({
    required this.clubId,
    required this.clubTitle,
    required this.categories,
    required this.clubLocationType,
    required this.clubLocation,
    required this.latitude,
    required this.longitude,
    this.logo,
    this.coverImage,
    required this.clubEmail,
    required this.website,
    required this.facebook,
    required this.instagram,
    required this.merchandiseLink,
    required this.description,
    required this.membershipQuestions,
    required this.clubTerms,
    required this.administrators,
  });

  factory ClubEditData.fromJson(Map<String, dynamic> json) {
    return ClubEditData(
      clubId: json['club_id'] as String,
      clubTitle: json['club_title'] as String,
      categories: ClubCategories.fromJson(
        json['categories'] as Map<String, dynamic>,
      ),
      clubLocationType: json['club_location_type'] as int,
      clubLocation: json['club_location'] as String? ?? '',
      latitude: json['latitude'] as String? ?? '',
      longitude: json['longitude'] as String? ?? '',
      logo: json['logo'] as String?,
      coverImage: json['cover_image'] as String?,
      clubEmail: json['club_email'] as String? ?? '',
      website: json['website'] as String? ?? '',
      facebook: json['facebook'] as String? ?? '',
      instagram: json['instagram'] as String? ?? '',
      merchandiseLink: json['merchandise_link'] as String? ?? '',
      description: json['description'] as String? ?? '',
      membershipQuestions:
          (json['membership_questions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      clubTerms: json['club_terms'] as String? ?? '',
      administrators:
          (json['administrators'] as List<dynamic>?)
              ?.map(
                (e) => ClubAdministrator.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'club_id': clubId,
      'club_title': clubTitle,
      'categories': categories.toJson(),
      'club_location_type': clubLocationType,
      'club_location': clubLocation,
      'latitude': latitude,
      'longitude': longitude,
      if (logo != null) 'logo': logo,
      if (coverImage != null) 'cover_image': coverImage,
      'club_email': clubEmail,
      'website': website,
      'facebook': facebook,
      'instagram': instagram,
      'merchandise_link': merchandiseLink,
      'description': description,
      'membership_questions': membershipQuestions,
      'club_terms': clubTerms,
      'administrators': administrators.map((e) => e.toJson()).toList(),
    };
  }

  bool get isNationalClub => clubLocationType == 1;
  bool get isLocalClub => clubLocationType == 2;
}

// lib/models/club_categories.dart
class ClubCategories {
  final List<ClubCategory> available;
  final List<int> selected;

  ClubCategories({required this.available, required this.selected});

  factory ClubCategories.fromJson(Map<String, dynamic> json) {
    return ClubCategories(
      available: (json['available'] as List<dynamic>)
          .map((e) => ClubCategory.fromJson(e as Map<String, dynamic>))
          .toList(),
      selected: (json['selected'] as List<dynamic>)
          .map((e) => e as int)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'available': available.map((e) => e.toJson()).toList(),
      'selected': selected,
    };
  }

  List<ClubCategory> get selectedCategories {
    return available.where((cat) => selected.contains(cat.termId)).toList();
  }
}

// lib/models/club_update_request.dart
class ClubUpdateRequest {
  final String? status; // 'publish' or 'draft'
  final String? clubTitle;
  final List<int>? categories;
  final int? clubLocationType;
  final String? clubLocation;
  final String? latitude;
  final String? longitude;
  final String? clubEmail;
  final String? website;
  final String? facebook;
  final String? instagram;
  final String? merchandiseLink;
  final String? description;
  final List<String>? membershipQuestions;
  final String? clubTerms;

  ClubUpdateRequest({
    this.status,
    this.clubTitle,
    this.categories,
    this.clubLocationType,
    this.clubLocation,
    this.latitude,
    this.longitude,
    this.clubEmail,
    this.website,
    this.facebook,
    this.instagram,
    this.merchandiseLink,
    this.description,
    this.membershipQuestions,
    this.clubTerms,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};

    if (status != null) data['status'] = status;
    if (clubTitle != null) data['club_title'] = clubTitle;
    if (categories != null) data['categories'] = categories;
    if (clubLocationType != null) data['club_location_type'] = clubLocationType;
    if (clubLocation != null) data['club_location'] = clubLocation;
    if (latitude != null) data['latitude'] = latitude;
    if (longitude != null) data['longitude'] = longitude;
    if (clubEmail != null) data['club_email'] = clubEmail;
    if (website != null) data['website'] = website;
    if (facebook != null) data['facebook'] = facebook;
    if (instagram != null) data['instagram'] = instagram;
    if (merchandiseLink != null) data['merchandise_link'] = merchandiseLink;
    if (description != null) data['description'] = description;
    if (membershipQuestions != null)
      data['membership_questions'] = membershipQuestions;
    if (clubTerms != null) data['club_terms'] = clubTerms;

    return data;
  }
}

// lib/models/api_response.dart
class ApiResponse<T> {
  final bool success;
  final String? message;
  final T? data;

  ApiResponse({required this.success, this.message, this.data});

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>)? fromJsonT,
  ) {
    return ApiResponse<T>(
      success: json['success'] as bool,
      message: json['message'] as String?,
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'] as Map<String, dynamic>)
          : null,
    );
  }
}
