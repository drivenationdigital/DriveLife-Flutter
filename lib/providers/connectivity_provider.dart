import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drivelife/config/api_config.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// What the app currently believes about its connection.
enum NetworkStatus {
  /// Before the first check finishes. Treated as online everywhere: refusing
  /// to load during the half-second it takes to find out would break every
  /// cold start on a perfectly good connection.
  unknown,
  online,
  offline,
}

/// Whether the app can actually reach its API.
///
/// Two signals, because neither is enough on its own:
///
/// 1. The radio, from connectivity_plus. Fast and event-driven, but it only
///    reports which interface is up. Its own documentation says not to decide
///    whether a request will work from it — joining a hotel wifi with a login
///    page in front of it reports "connected" while nothing can get out.
/// 2. A reachability probe against our own host. Slow and deliberate, but it
///    answers the question the app actually has.
///
/// So the radio is a trigger and the probe is the answer. A radio change
/// prompts a probe; while offline the probe repeats on a backoff, because a
/// captive portal being passed fires no event at all.
class ConnectivityProvider extends ChangeNotifier with WidgetsBindingObserver {
  NetworkStatus _status = NetworkStatus.unknown;

  /// Set for a moment after a recovery, so the banner can say so and go.
  bool _justRestored = false;

  StreamSubscription<List<ConnectivityResult>>? _radio;
  Timer? _debounce;
  Timer? _retry;
  Timer? _restored;

  /// Which backoff step the next retry uses.
  int _attempt = 0;

  /// One probe at a time. Several triggers can land together — a radio change
  /// and a failed request and a resume — and three probes answer one question.
  bool _probing = false;

  bool _stopped = false;

  static const Duration _probeTimeout = Duration(seconds: 6);

  /// Rises, then settles. Aggressive at first because most drops are brief —
  /// a tunnel, a lift — and then patient, because a probe every three seconds
  /// for an hour is a battery complaint.
  static const List<int> _backoffSeconds = [3, 6, 12, 24, 30];

  NetworkStatus get status => _status;

  /// Offline for certain. False while [NetworkStatus.unknown], so nothing
  /// blocks itself before the first answer arrives.
  bool get isOffline => _status == NetworkStatus.offline;

  bool get isOnline => _status != NetworkStatus.offline;

  bool get justRestored => _justRestored;

  /// Whether the banner has anything to say.
  bool get showBanner => isOffline || _justRestored;

  /// Begins watching. Safe to call once, from the app root.
  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);

    _radio = Connectivity().onConnectivityChanged.listen(_onRadioChanged);

    try {
      _onRadioChanged(await Connectivity().checkConnectivity());
    } catch (_) {
      // The plugin is unavailable on this platform or failed to start. The
      // probe still works, so fall back to asking the network directly.
      unawaited(_check());
    }
  }

  void _onRadioChanged(List<ConnectivityResult> results) {
    final hasInterface = results.any((r) => r != ConnectivityResult.none);

    if (!hasInterface) {
      // Nothing is up, so nothing can be reached. No probe needed, and no
      // retry timer either — the next radio event is what changes this.
      _retry?.cancel();
      _debounce?.cancel();
      _attempt = 0;
      _set(NetworkStatus.offline);
      return;
    }

    // An interface coming up says a request is now worth trying, not that it
    // will succeed. Debounced because switching networks emits several events
    // in a row as each interface settles.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_check());
    });
  }

  /// Re-checks now. For an API layer that has just seen a request fail in a
  /// way that looks like a dead connection.
  void reportNetworkFailure() {
    if (_probing) return;
    unawaited(_check());
  }

  /// Re-checks now, for a user who has tapped "Retry".
  Future<void> refresh() => _check();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS suspends the radio stream in the background, so the first thing we
    // know on the way back may be hours stale.
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (_stopped || _probing) return;

    _probing = true;

    try {
      final reachable = await _probe();

      if (_stopped) return;

      _set(reachable ? NetworkStatus.online : NetworkStatus.offline);

      _retry?.cancel();

      if (reachable) {
        _attempt = 0;
        return;
      }

      // Nothing will tell us when a captive portal is passed or a flaky
      // connection steadies, so the only way back is to keep asking.
      final seconds =
          _backoffSeconds[_attempt.clamp(0, _backoffSeconds.length - 1)];
      if (_attempt < _backoffSeconds.length - 1) _attempt++;

      _retry = Timer(Duration(seconds: seconds), () => unawaited(_check()));
    } finally {
      _probing = false;
    }
  }

  /// Can we reach the API?
  ///
  /// HEAD, so nothing but headers crosses the wire. Any HTTP response at all
  /// means the request got out and back, which is the question — a 404 proves
  /// reachability as well as a 200 does.
  ///
  /// The content type is checked when there is one: WordPress answers this
  /// path as JSON, and a captive portal answers everything as HTML. That is
  /// the difference between "connected" and "connected to the login page of a
  /// hotel". Where the header is missing we take the response at face value
  /// rather than calling a working connection dead.
  Future<bool> _probe() async {
    try {
      final response = await http
          .head(Uri.parse('${ApiConfig.baseUrl}/wp-json/'))
          .timeout(_probeTimeout);

      final type = response.headers['content-type'];

      if (type == null || type.isEmpty) return true;

      return type.toLowerCase().contains('json');
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } on http.ClientException {
      return false;
    } catch (_) {
      return false;
    }
  }

  void _set(NetworkStatus next) {
    if (next == _status) return;

    final recovered =
        _status == NetworkStatus.offline && next == NetworkStatus.online;

    _status = next;

    _restored?.cancel();

    if (recovered) {
      // Worth saying once. A banner that only ever appears for bad news
      // leaves people unsure whether it ever came back.
      _justRestored = true;
      _restored = Timer(const Duration(seconds: 2), () {
        _justRestored = false;
        if (!_stopped) notifyListeners();
      });
    } else {
      _justRestored = false;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _stopped = true;
    WidgetsBinding.instance.removeObserver(this);
    _radio?.cancel();
    _debounce?.cancel();
    _retry?.cancel();
    _restored?.cancel();
    super.dispose();
  }
}
