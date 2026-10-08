import 'package:drivelife/config/feature_flags.dart';
import 'package:drivelife/main.dart' show rootScaffoldMessengerKey;
import 'package:drivelife/screens/events/add_event_screen.dart';
import 'package:drivelife/screens/events/event_editor_web.dart';
import 'package:drivelife/utils/navigation_helper.dart';
import 'package:flutter/material.dart';

/// Opens the event editor, wherever it currently lives.
///
/// One place for the decision so the five entry points — the events list, the
/// home tab, the posts screen, the admin view and the named route — do not
/// each have to know about it, and so turning the flag off restores the
/// native screen everywhere at once.
///
/// [eventId] is the raw post id the native screen takes; [eventEid] is the
/// encrypted one the dashboard takes. Both are needed because the two editors
/// address an event differently, and an edit can only go to the dashboard if
/// the encrypted id is to hand.
Future<void> openEventEditor(
  BuildContext context, {
  String? eventId,
  String? eventEid,
  String site = 'uk',
  int? clubId,
}) async {
  final editing = (eventId ?? '').isNotEmpty || (eventEid ?? '').isNotEmpty;

  // The dashboard addresses events by their encrypted id, so an edit can only
  // go there when we have one. Creating needs no id at all, so it always can.
  final canUseWeb =
      FeatureFlags.webEventEditor &&
      clubId == null &&
      (!editing || (eventEid ?? '').isNotEmpty);

  if (canUseWeb) {
    final opened = await EventEditorWeb.open(
      eventEid: eventEid,
      site: site,
      context: context,
    );

    if (opened) return;

    // Signed out, no session, or no browser would take it. Falling through to
    // the native screen rather than stopping: the organiser came here to edit
    // an event, and the old form still works.
    debugPrint('📝 [Editor] Web editor unavailable; using the native screen');
  }

  if (!context.mounted) return;

  if (FeatureFlags.webEventEditor && canUseWeb) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Opening the full editor failed — using the basic one.'),
      ),
    );
  }

  NavigationHelper.navigateTo(
    context,
    AddEventScreen(eventId: eventId, clubId: clubId),
  );
}
