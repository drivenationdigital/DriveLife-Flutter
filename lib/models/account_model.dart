// models/account.dart - Update to differentiate account types
import 'package:drivelife/models/user_model.dart';

enum AccountType { user, club, venue }

class Account {
  final String token;
  final User user;
  final DateTime lastUsed;
  final AccountType accountType; // ✅ NEW
  final int? parentUserId; // ✅ NEW - Links entity to owner
  final Map<String, dynamic>? entityMeta; // ✅ NEW - Club/venue specific data

  Account({
    required this.token,
    required this.user,
    required this.lastUsed,
    this.accountType = AccountType.user,
    this.parentUserId,
    this.entityMeta,
  });

  bool get isUserAccount => accountType == AccountType.user;
  bool get isEntityAccount => accountType != AccountType.user;
  bool get isClubAccount => accountType == AccountType.club;
  bool get isVenueAccount => accountType == AccountType.venue;

  factory Account.fromJson(Map<String, dynamic> json) {
    // ✅ Properly parse accountType
    AccountType type = AccountType.user;
    if (json['accountType'] != null) {
      final typeString = json['accountType'].toString();
      print('📝 Parsing accountType: $typeString'); // Debug

      // Handle both "club" and "AccountType.club" formats
      if (typeString.contains('club')) {
        type = AccountType.club;
      } else if (typeString.contains('venue')) {
        type = AccountType.venue;
      } else if (typeString.contains('user')) {
        type = AccountType.user;
      }
    }

    print('✅ Parsed account: ${json['user']['username']} as $type'); // Debug

    return Account(
      token: json['token'],
      user: User.fromJson(json['user']),
      lastUsed: DateTime.parse(json['lastUsed']),
      accountType: type,
      parentUserId: json['parentUserId'],
      entityMeta: json['entityMeta'],
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'user': user.toJson(),
    'lastUsed': lastUsed.toIso8601String(),
    'accountType': accountType
        .toString()
        .split('.')
        .last, // ✅ Saves as "club", "user", "venue"
    'parentUserId': parentUserId,
    'entityMeta': entityMeta,
  };

  // Helper to create club account
  factory Account.club({
    required String token,
    required User clubUser,
    required int parentUserId,
    required Map<String, dynamic> clubMeta,
  }) {
    return Account(
      token: token,
      user: clubUser,
      lastUsed: DateTime.now(),
      accountType: AccountType.club,
      parentUserId: parentUserId,
      entityMeta: clubMeta,
    );
  }

  // Helper to create venue account
  factory Account.venue({
    required String token,
    required User venueUser,
    required int parentUserId,
    required Map<String, dynamic> venueMeta,
  }) {
    return Account(
      token: token,
      user: venueUser,
      lastUsed: DateTime.now(),
      accountType: AccountType.venue,
      parentUserId: parentUserId,
      entityMeta: venueMeta,
    );
  }
}
