import 'package:drivelife/models/user_model.dart';

class Account {
  final String token;
  final User user;
  final DateTime lastUsed;

  Account({required this.token, required this.user, required this.lastUsed});

  Map<String, dynamic> toJson() => {
    'token': token,
    'user': user.toJson(),
    'lastUsed': lastUsed.toIso8601String(),
  };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    token: json['token'],
    user: User.fromJson(json['user']),
    lastUsed: DateTime.parse(json['lastUsed']),
  );
}
