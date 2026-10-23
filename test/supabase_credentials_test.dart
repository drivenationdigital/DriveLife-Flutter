import 'dart:convert';

import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsing the reply from `/myapp/v1/supabase-token`.
///
/// This had one bug and it was expensive: the payload was read with
/// `data['user_id'] as String` while the endpoint sends user_id as a JSON
/// *number*. The cast threw on every call, so messaging never worked for
/// anyone — and nothing said so, because the only caller was
/// `fetchAndStore(...).then(...)` with no catch. The throw became an
/// unhandled async error, the inbox notifier was never built, and the
/// screen sat on a spinner that could not finish.
///
/// The first test is the real payload, copied from a device log.
void main() {
  group('SupabaseCredentials.fromJson', () {
    test('reads the body the server actually sends', () {
      // Verbatim from the log, token shortened. Note user_id: a NUMBER.
      final body = jsonDecode('''
        {
          "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc.def",
          "expires_at": 1792760949,
          "user_id": 67004
        }
      ''') as Map<String, dynamic>;

      final creds = SupabaseCredentials.fromJson(body);

      expect(creds.userId, '67004');
      expect(creds.expiresAt, 1792760949);
      expect(creds.token, startsWith('eyJ'));
    });

    test('a quoted user_id works just as well', () {
      // The other way round, in case the endpoint changes its mind back.
      final creds = SupabaseCredentials.fromJson({
        'token': 't',
        'expires_at': 1792760949,
        'user_id': '67004',
      });

      expect(creds.userId, '67004');
    });

    test('a quoted expires_at works too', () {
      final creds = SupabaseCredentials.fromJson({
        'token': 't',
        'expires_at': '1792760949',
        'user_id': 1,
      });

      expect(creds.expiresAt, 1792760949);
    });

    test('a missing token is an error, not an empty session', () {
      // Worth failing loudly: a blank token would be stored, sent as
      // `Bearer `, and every Supabase call would 401 with no clue why.
      expect(
        () => SupabaseCredentials.fromJson({
          'expires_at': 1,
          'user_id': 1,
        }),
        throwsFormatException,
      );

      expect(
        () => SupabaseCredentials.fromJson({
          'token': '',
          'expires_at': 1,
          'user_id': 1,
        }),
        throwsFormatException,
      );
    });

    test('a missing user_id is an error', () {
      expect(
        () => SupabaseCredentials.fromJson({
          'token': 't',
          'expires_at': 1,
        }),
        throwsFormatException,
      );
    });

    test('an unparseable expires_at is an error', () {
      expect(
        () => SupabaseCredentials.fromJson({
          'token': 't',
          'expires_at': 'never',
          'user_id': 1,
        }),
        throwsFormatException,
      );
    });
  });
}
