import 'dart:async';

import 'package:drivelife/models/event_editor_models.dart';
import 'package:flutter/foundation.dart';

/// STUB — discounts, show cars, car clubs and traders are not on the app's
/// event API yet.
///
/// The app saves events through `app/v2` (event-creation.php), which reads only
/// title, location, categories, dates, description, ticket type and visibility.
/// The Next.js dashboard saves the richer event through a different endpoint,
/// `POST dl-accounts/v1/event-update` (dl-accounts-event-update.php), and that
/// is where these four sections live.
///
/// So the UI is built against this stub: it holds the draft in memory for the
/// session and hands back what was given. Nothing is persisted, and the app
/// makes no claim that it is.
///
/// **To make it real**, replace the two methods below with calls to
/// `dl-accounts/v1/event-update`. The models already serialise to that
/// endpoint's snake_case shape via [EventExtrasDraft.toJson], so the change
/// should be confined to this file:
///
/// ```dart
/// final response = await http.post(
///   Uri.parse('$_accountsBase/event-update?eid=$encryptedId&site=$site'),
///   headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
///   body: jsonEncode(draft.toJson()),
/// );
/// ```
///
/// Note the dashboard addresses events by `encrypted_id` + `site` on the query
/// string, not the numeric post id the app uses — that mismatch needs resolving
/// when the endpoints are joined up.
class EventExtrasAPI {
  EventExtrasAPI._();

  /// In-memory store, keyed by event id. Survives navigation within a session
  /// and nothing more — deliberately, so a reviewer cannot mistake this for
  /// persistence.
  static final Map<String, EventExtrasDraft> _drafts = {};

  /// Stand-in latency, so the UI's loading states are exercised rather than
  /// only ever seeing instant results.
  static const Duration _fakeLatency = Duration(milliseconds: 250);

  /// Returns the draft for an event, or an empty one.
  static Future<EventExtrasDraft> fetch({required String? eventId}) async {
    await Future<void>.delayed(_fakeLatency);

    if (eventId == null) return const EventExtrasDraft();

    debugPrint(
      'EventExtrasAPI.fetch($eventId) — STUB, returning in-memory draft',
    );
    return _drafts[eventId] ?? const EventExtrasDraft();
  }

  /// Pretends to save. Returns the draft it was given so callers can be written
  /// exactly as they will be against the real endpoint.
  static Future<EventExtrasDraft> save({
    required String? eventId,
    required EventExtrasDraft draft,
  }) async {
    await Future<void>.delayed(_fakeLatency);

    if (eventId != null) {
      _drafts[eventId] = draft;
    }

    debugPrint(
      'EventExtrasAPI.save($eventId) — STUB, nothing sent to the server. '
      'Payload would be: ${draft.toJson()}',
    );

    return draft;
  }

  /// Clears the in-memory store. For tests, and for signing out.
  static void reset() => _drafts.clear();
}
