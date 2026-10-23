import 'package:drivelife/services/notification_target.dart';
import 'package:flutter_test/flutter_test.dart';

/// Routing a notification tap to the account it belongs to.
///
/// With two accounts signed in, both get notifications on the same device —
/// the device token is registered against each in turn. Without the
/// recipient's id travelling with the notification, a tap opened the
/// content under whichever account happened to be active: often the wrong
/// one, sometimes one that cannot see the thing at all.
///
/// Two things are pinned here. That the payload survives the round trip
/// through a local notification, including payloads written by an older
/// build; and the decision about whether to switch account, which has a
/// case that must NOT navigate.
void main() {
  group('fromData', () {
    test('reads the fields the server sends', () {
      final t = NotificationTarget.fromData({
        'title': 'Keshan Jude',
        'body': 'Nice one',
        'url': 'post-view/1234',
        'account_id': '67004',
        'account_name': 'keshanj',
      });

      expect(t.url, 'post-view/1234');
      expect(t.accountId, '67004');
      expect(t.accountName, 'keshanj');
      expect(t.isEmpty, isFalse);
    });

    test('an int account_id is still read', () {
      // FCM data values are strings on the wire, but a local decode or a
      // future change could hand this one through as a number.
      final t = NotificationTarget.fromData({
        'url': 'post-view/1',
        'account_id': 67004,
      });

      expect(t.accountId, '67004');
    });

    test('blank fields read as absent, not as empty strings', () {
      final t = NotificationTarget.fromData({
        'url': 'post-view/1',
        'account_id': '',
        'account_name': '   ',
      });

      expect(t.accountId, isNull);
      expect(t.accountName, isNull);
    });
  });

  group('payload round trip', () {
    test('encode then decode keeps everything', () {
      const original = NotificationTarget(
        url: 'gallery/99?photo=4',
        accountId: '67004',
        accountName: 'keshanj',
      );

      final back = NotificationTarget.fromPayload(original.encode());

      expect(back.url, original.url);
      expect(back.accountId, original.accountId);
      expect(back.accountName, original.accountName);
    });

    test('a bare url still works', () {
      // The payload used to be just the url. One can be sitting in the
      // notification shade from before the app was updated, and a cold
      // start reads it — so this has to keep opening rather than being
      // parsed as nothing.
      final t = NotificationTarget.fromPayload('post-view/1234');

      expect(t.url, 'post-view/1234');
      expect(t.accountId, isNull);
    });

    test('nonsense that starts with a brace falls back to a url', () {
      final t = NotificationTarget.fromPayload('{not json');
      expect(t.url, '{not json');
    });

    test('empty and null payloads are empty targets', () {
      expect(NotificationTarget.fromPayload(null).isEmpty, isTrue);
      expect(NotificationTarget.fromPayload('').isEmpty, isTrue);
      expect(NotificationTarget.fromPayload('   ').isEmpty, isTrue);
    });
  });

  group('resolveAccountSwitch', () {
    const signedIn = ['67004', '81200'];

    test('already the active account: nothing to do', () {
      expect(
        resolveAccountSwitch(
          targetAccountId: '67004',
          signedInIds: signedIn,
          activeId: '67004',
        ),
        AccountSwitch.none,
      );
    });

    test('another signed-in account: switch to it', () {
      expect(
        resolveAccountSwitch(
          targetAccountId: '81200',
          signedInIds: signedIn,
          activeId: '67004',
        ),
        AccountSwitch.switchTo,
      );
    });

    test('an account that is not signed in: do not open it', () {
      // The case that must not navigate. Opening it would show one
      // account's notification under another's identity, and most of those
      // requests would be refused by the server anyway.
      expect(
        resolveAccountSwitch(
          targetAccountId: '99999',
          signedInIds: signedIn,
          activeId: '67004',
        ),
        AccountSwitch.notSignedIn,
      );
    });

    test('no account on the notification: open it as before', () {
      // Notifications sent before the server started including account_id
      // land here. Opening them under the active account is what used to
      // happen for everything, and is better than refusing to open them.
      for (final missing in [null, '', '  ']) {
        expect(
          resolveAccountSwitch(
            targetAccountId: missing,
            signedInIds: signedIn,
            activeId: '67004',
          ),
          AccountSwitch.none,
          reason: 'targetAccountId: ${missing == null ? 'null' : '"$missing"'}',
        );
      }
    });

    test('nobody signed in and an account named: do not open it', () {
      expect(
        resolveAccountSwitch(
          targetAccountId: '67004',
          signedInIds: const [],
          activeId: null,
        ),
        AccountSwitch.notSignedIn,
      );
    });
  });
}
