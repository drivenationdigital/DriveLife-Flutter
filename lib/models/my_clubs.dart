class MyClub {
  final String clubId;
  final String title;
  final String status; // 'publish' or 'draft'
  final String? logo;
  final String? coverImage;
  final int locationType; // 1 = National, 2 = Local
  final String location;
  final int memberCount;
  final DateTime createdDate;

  MyClub({
    required this.clubId,
    required this.title,
    required this.status,
    this.logo,
    this.coverImage,
    required this.locationType,
    required this.location,
    required this.memberCount,
    required this.createdDate,
  });

  factory MyClub.fromJson(Map<String, dynamic> json) {
    return MyClub(
      clubId: json['club_id'] as String,
      title: json['title'] as String,
      status: json['status'] as String,
      logo: json['logo'] as String?,
      coverImage: json['cover_image'] as String?,
      locationType: json['location_type'] as int,
      location: json['location'] as String? ?? '',
      memberCount: json['member_count'] as int? ?? 0,
      createdDate: DateTime.parse(json['created_date'] as String),
    );
  }

  bool get isPublished => status == 'publish';
  bool get isDraft => status == 'draft';
  bool get isNational => locationType == 1;
  bool get isLocal => locationType == 2;
}

class MyClubsResponse {
  final List<MyClub> clubs;
  final int total;

  MyClubsResponse({required this.clubs, required this.total});

  factory MyClubsResponse.fromJson(Map<String, dynamic> json) {
    return MyClubsResponse(
      clubs: (json['clubs'] as List<dynamic>)
          .map((club) => MyClub.fromJson(club as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
    );
  }
}
