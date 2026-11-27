package com.app.carcalendar

import com.ryanheise.audioservice.AudioServiceFragmentActivity

// ── WHY THIS IS NOT FlutterFragmentActivity ANY MORE ────────────────
//
// audio_service needs the activity to be its own subclass: that is how
// the media session is bound to the Flutter engine, so the foreground
// service can be started and the notification's controls routed back
// into Dart.
//
// AudioServiceFragmentActivity rather than AudioServiceActivity,
// because this was a FlutterFragmentActivity and has to stay one -
// the image picker and the Firebase plugins rely on the fragment host.
//
// See lib/services/video_audio_handler.dart.
class MainActivity : AudioServiceFragmentActivity()