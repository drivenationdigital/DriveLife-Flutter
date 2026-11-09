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
  final bool isAdmin;

  /// Whether the server will serve this person the Activity tab.
  ///
  /// Null means the server did not say — an older API, or one without
  /// the activity files deployed — and the caller falls back to its own
  /// default. Not defaulted to false here: "we were not told" and "you
  /// are not allowed" are different answers, and conflating them would
  /// hide the tab on every server that has not been updated yet.
  final bool? activityAccess;

  /// What they ticked at signup, as the ids step_three.dart stores.
  ///
  /// Ids rather than labels, because the app holds the same numbered
  /// list and two copies of the wording would drift. Empty means they
  /// answered nothing — either they predate the question or they
  /// skipped it — which is what the prompt keys off.
  final List<int> interests;

  /// Marque group ids they follow. See BrandsAPI.
  final List<int> brands;

  /// Whether they have ever been ASKED about brands.
  ///
  /// Not the same as [brands] being empty: somebody who looked and
  /// picked none has answered and must not be prompted again. Only this
  /// tells the two apart, and it is what BrandsPrompt keys off.
  ///
  /// Defaults TRUE so a server that does not send it yet prompts
  /// nobody — a field appearing in a later deploy must not make every
  /// user see a popup.
  final bool brandsAnswered;

  /// Which providers this account can sign in with: 'google', 'apple',
  /// or neither.
  ///
  /// Empty for an ordinary password account. Non-empty means the
  /// account was created or linked through a provider and may have NO
  /// password anybody has ever seen — so a screen that has to prove
  /// identity, which is the delete-account screen, asks for the
  /// provider's sheet rather than a password field that cannot be
  /// filled in. See account_settings_screen.dart.
  final List<String> socialProviders;

  /// The provider this account was CREATED with, or null.
  ///
  /// NOT derivable from [socialProviders]. An account linked to Google
  /// and an account created with Google both list 'google', but only
  /// the second has no password its owner has ever seen — so only the
  /// second cannot be disconnected without losing the account.
  ///
  /// Decides whether Connected Accounts offers "Disconnect" or points
  /// at deletion instead. Null for accounts made before the server
  /// recorded this, which is the safe direction: they fall through to
  /// the password check, which a passwordless account cannot pass.
  final String? socialCreatedWith;

  /// Which of step_four.dart's profile types they picked, or null.
  final int? profileType;

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
    this.isAdmin = false,
    this.activityAccess,
    this.interests = const [],
    this.brands = const [],
    this.brandsAnswered = true,
    this.socialProviders = const [],
    this.socialCreatedWith,
    this.profileType,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      verified: json['verified'] ?? false,
      username: json['username'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      email: json['email'] ?? '',

      // ✅ Handle profile_image - check if it's actually a string
      profileImage:
          json['profile_image'] is String &&
              json['profile_image'].toString().isNotEmpty
          ? json['profile_image']
          : null,

      // ✅ Handle cover_image - check if it's actually a string (not array)
      coverImage:
          json['cover_image'] is String &&
              json['cover_image'].toString().isNotEmpty
          ? json['cover_image']
          : null,

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
      lastLocation:
          json['last_location'] != null && json['last_location'] is Map
          ? LastLocation.fromJson(json['last_location'])
          : null,
      profileLinks:
          json['profile_links'] != null && json['profile_links'] is Map
          ? ProfileLinks.fromJson(json['profile_links'])
          : null,
      billingInfo: json['billing_info'] != null && json['billing_info'] is Map
          ? BillingInfo.fromJson(json['billing_info'])
          : null,
      isAdmin: json['is_admin'] ?? false,
      brands: json['brands'] is List
          ? (json['brands'] as List)
                .map((v) => int.tryParse('$v') ?? -1)
                .where((v) => v >= 0)
                .toList()
          : const [],
      socialCreatedWith:
          (json['social_created_with'] is String &&
              (json['social_created_with'] as String).isNotEmpty)
          ? json['social_created_with'] as String
          : null,
      socialProviders: json['social_providers'] is List
          ? (json['social_providers'] as List)
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList()
          : const [],
      brandsAnswered: json['brands_answered'] is bool
          ? json['brands_answered'] as bool
          : true,
      interests: json['interests'] is List
          ? (json['interests'] as List)
                .map((v) => int.tryParse('$v'))
                .whereType<int>()
                .toList()
          : const [],
      profileType: json['profile_type'] == null
          ? null
          : int.tryParse('${json['profile_type']}'),
      activityAccess: json['activity_access'] is bool
          ? json['activity_access'] as bool
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
      'is_admin': isAdmin,
      'activity_access': activityAccess,
      'interests': interests,
      'brands': brands,
      'brands_answered': brandsAnswered,
      'social_providers': socialProviders,
      'social_created_with': socialCreatedWith,
      'profile_type': profileType,
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
    bool? isAdmin,
    bool? activityAccess,
    List<int>? interests,
    List<int>? brands,
    bool? brandsAnswered,
    List<String>? socialProviders,
    String? socialCreatedWith,
    int? profileType,
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
      isAdmin: isAdmin ?? this.isAdmin,
      activityAccess: activityAccess ?? this.activityAccess,
      interests: interests ?? this.interests,
      brands: brands ?? this.brands,
      brandsAnswered: brandsAnswered ?? this.brandsAnswered,
      socialProviders: socialProviders ?? this.socialProviders,
      socialCreatedWith: socialCreatedWith ?? this.socialCreatedWith,
      profileType: profileType ?? this.profileType,
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
