import 'dart:convert';

/// Where a notification should take you, and whose notification it is.
///
/// Two things made this worth a type of its own rather than a string.
///
/// The first is multi-account. Notifications for every signed-in account
/// land on the same device, because the device token is registered against
/// each of them in turn — so without the recipient's id in the payload the
/// app cannot tell them apart. Tapping one opened the content under
/// whichever account happened to be active, which is frequently the wrong
/// one and sometimes one that cannot see it at all.
///
/// The second is that the local notification carries its own payload, a
/// single string, which used to be the bare `url`. Anything else the tap
/// handler needs has to travel in there too.
class NotificationTarget {
  /// The deep link, e.g. `post-view/1234`.
  final String? url;

  /// The WordPress user id this notification was sent to.
  final String? accountId;

  /// That account's username, for the "which account" line. Sent by the
  /// server so the app does not have to look it up before it can draw a
  /// notification.
  final String? accountName;

  const NotificationTarget({this.url, this.accountId, this.accountName});

  bool get isEmpty => (url ?? '').isEmpty;

  /// From an FCM message's `data` map.
  factory NotificationTarget.fromData(Map<String, dynamic> data) {
    String? read(String key) {
      final value = data[key];
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return NotificationTarget(
      url: read('url'),
      accountId: read('account_id'),
      accountName: read('account_name'),
    );
  }

  /// From a local notification's payload string.
  ///
  /// Accepts a bare URL as well as the JSON this now writes. Payloads
  /// outlive an upgrade — one can be sitting in the notification shade from
  /// before the app was updated, and a cold start reads it — so the old
  /// shape has to keep working rather than being parsed as nothing.
  factory NotificationTarget.fromPayload(String? payload) {
    final text = payload?.trim() ?? '';
    if (text.isEmpty) return const NotificationTarget();

    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          return NotificationTarget.fromData(decoded);
        }
      } catch (_) {
        // Not JSON after all. Fall through and treat it as a URL.
      }
    }

    return NotificationTarget(url: text);
  }

  /// For a local notification's payload. Round-trips through
  /// [NotificationTarget.fromPayload].
  String encode() => jsonEncode({
    if (url != null) 'url': url,
    if (accountId != null) 'account_id': accountId,
    if (accountName != null) 'account_name': accountName,
  });

  @override
  String toString() =>
      'NotificationTarget(url: $url, account: $accountName/$accountId)';
}

/// What to do about the account a notification belongs to.
enum AccountSwitch {
  /// It is already the active account, or the notification does not say
  /// which account it is for — carry on and open it.
  none,

  /// Another signed-in account. Switch to it, then open.
  switchTo,

  /// An account that is not signed in on this device. Opening the content
  /// under somebody else's identity would be wrong, and it may well 403,
  /// so say so instead.
  notSignedIn,
}

/// What should happen, given who the notification is for and who is signed
/// in. A pure decision, separated from the switching so it can be tested.
///
/// [signedInIds] is every signed-in account's user id as a string, and
/// [activeId] the one in use.
AccountSwitch resolveAccountSwitch({
  required String? targetAccountId,
  required List<String> signedInIds,
  required String? activeId,
}) {
  final target = targetAccountId?.trim() ?? '';

  // Nothing to act on. Older notifications, sent before the server started
  // including account_id, land here — and opening them as before is better
  // than refusing to open them at all.
  if (target.isEmpty) return AccountSwitch.none;

  if (target == activeId) return AccountSwitch.none;

  if (signedInIds.contains(target)) return AccountSwitch.switchTo;

  return AccountSwitch.notSignedIn;
}
