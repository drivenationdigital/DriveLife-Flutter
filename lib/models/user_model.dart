class User {
  final int id;
  final bool verified;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String? profileImage;
  final String? coverImage;
  final bool canUpdateUsername;
  final int nextUpdateUsername;
  final List<String> followers;
  final List<String> following;
  final String postsCount;
  final bool emailVerified;
  final LastLocation? lastLocation;
  final ProfileLinks? profileLinks;
  final BillingInfo? billingInfo;

  User({
    required this.id,
    required this.verified,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.profileImage,
    this.coverImage,
    required this.canUpdateUsername,
    required this.nextUpdateUsername,
    required this.followers,
    required this.following,
    required this.postsCount,
    required this.emailVerified,
    this.lastLocation,
    this.profileLinks,
    this.billingInfo,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      verified: json['verified'] ?? false,
      username: json['username'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      email: json['email'] ?? '',
      profileImage: json['profile_image'],
      coverImage: json['cover_image'],
      canUpdateUsername: json['can_update_username'] ?? false,
      nextUpdateUsername: json['next_update_username'] ?? 0,
      followers: json['followers'] != null
          ? List<String>.from(json['followers'])
          : [],
      following: json['following'] != null
          ? List<String>.from(json['following'])
          : [],
      postsCount: json['posts_count']?.toString() ?? '0',
      emailVerified: json['email_verified'] ?? false,
      lastLocation: json['last_location'] != null
          ? LastLocation.fromJson(json['last_location'])
          : null,
      profileLinks: json['profile_links'] != null
          ? ProfileLinks.fromJson(json['profile_links'])
          : null,
      billingInfo: json['billing_info'] != null
          ? BillingInfo.fromJson(json['billing_info'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'verified': verified,
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'profile_image': profileImage,
      'cover_image': coverImage,
      'can_update_username': canUpdateUsername,
      'next_update_username': nextUpdateUsername,
      'followers': followers,
      'following': following,
      'posts_count': postsCount,
      'email_verified': emailVerified,
      'last_location': lastLocation?.toJson(),
      'profile_links': profileLinks?.toJson(),
      'billing_info': billingInfo?.toJson(),
    };
  }

  // Helper getters
  String get fullName => '$firstName $lastName'.trim();
  int get followersCount => followers.length;
  int get followingCount => following.length;
  bool get hasProfileImage => profileImage != null && profileImage!.isNotEmpty;
  bool get hasCoverImage => coverImage != null && coverImage!.isNotEmpty;

  // CopyWith method for easy updates
  User copyWith({
    int? id,
    bool? verified,
    String? username,
    String? firstName,
    String? lastName,
    String? email,
    String? profileImage,
    String? coverImage,
    bool? canUpdateUsername,
    int? nextUpdateUsername,
    List<String>? followers,
    List<String>? following,
    String? postsCount,
    bool? emailVerified,
    LastLocation? lastLocation,
    ProfileLinks? profileLinks,
    BillingInfo? billingInfo,
  }) {
    return User(
      id: id ?? this.id,
      verified: verified ?? this.verified,
      username: username ?? this.username,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      profileImage: profileImage ?? this.profileImage,
      coverImage: coverImage ?? this.coverImage,
      canUpdateUsername: canUpdateUsername ?? this.canUpdateUsername,
      nextUpdateUsername: nextUpdateUsername ?? this.nextUpdateUsername,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      postsCount: postsCount ?? this.postsCount,
      emailVerified: emailVerified ?? this.emailVerified,
      lastLocation: lastLocation ?? this.lastLocation,
      profileLinks: profileLinks ?? this.profileLinks,
      billingInfo: billingInfo ?? this.billingInfo,
    );
  }
}

class LastLocation {
  final double latitude;
  final double longitude;
  final String updatedAt;
  final String country;

  LastLocation({
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    required this.country,
  });

  factory LastLocation.fromJson(Map<String, dynamic> json) {
    return LastLocation(
      latitude: double.tryParse(json['latitude']?.toString() ?? '0.0') ?? 0.0,
      longitude: double.tryParse(json['longitude']?.toString() ?? '0.0') ?? 0.0,
      updatedAt: json['updated_at'] ?? '',
      country: json['country'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'updated_at': updatedAt,
      'country': country,
    };
  }
}

class ProfileLinks {
  final String? instagram;
  final String? facebook;
  final String? tiktok;
  final String? youtube;
  final String? mivia;
  final String? custodian;
  final List<ExternalLink> externalLinks;

  ProfileLinks({
    this.instagram,
    this.facebook,
    this.tiktok,
    this.youtube,
    this.mivia,
    this.custodian,
    this.externalLinks = const [],
  });

  factory ProfileLinks.fromJson(Map<String, dynamic> json) {
    return ProfileLinks(
      instagram: json['instagram'],
      facebook: json['facebook'],
      tiktok: json['tiktok'],
      youtube: json['youtube'],
      mivia: json['mivia'],
      custodian: json['custodian'],
      externalLinks: json['external_links'] != null
          ? (json['external_links'] as List)
                .map((e) => ExternalLink.fromJson(e))
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'instagram': instagram,
      'facebook': facebook,
      'tiktok': tiktok,
      'youtube': youtube,
      'mivia': mivia,
      'custodian': custodian,
      'external_links': externalLinks.map((e) => e.toJson()).toList(),
    };
  }
}

class ExternalLink {
  final String id;
  final LinkDetails link;

  ExternalLink({required this.id, required this.link});

  factory ExternalLink.fromJson(Map<String, dynamic> json) {
    return ExternalLink(
      id: json['id']?.toString() ?? '',
      link: LinkDetails.fromJson(json['link']),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'link': link.toJson()};
  }
}

class LinkDetails {
  final String label;
  final String url;

  LinkDetails({required this.label, required this.url});

  factory LinkDetails.fromJson(Map<String, dynamic> json) {
    return LinkDetails(label: json['label'] ?? '', url: json['url'] ?? '');
  }

  Map<String, dynamic> toJson() {
    return {'label': label, 'url': url};
  }
}

class BillingInfo {
  final String phone;
  final String country;
  final String address1;
  final String address2;
  final String city;
  final String state;
  final String postcode;

  BillingInfo({
    required this.phone,
    required this.country,
    required this.address1,
    required this.address2,
    required this.city,
    required this.state,
    required this.postcode,
  });

  factory BillingInfo.fromJson(Map<String, dynamic> json) {
    return BillingInfo(
      phone: json['phone'] ?? '',
      country: json['country'] ?? '',
      address1: json['address_1'] ?? '',
      address2: json['address_2'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      postcode: json['postcode'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'phone': phone,
      'country': country,
      'address_1': address1,
      'address_2': address2,
      'city': city,
      'state': state,
      'postcode': postcode,
    };
  }

  bool get isEmpty =>
      phone.isEmpty &&
      country.isEmpty &&
      address1.isEmpty &&
      city.isEmpty &&
      postcode.isEmpty;
}
