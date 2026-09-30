import 'package:drivelife/providers/connectivity_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A strip above the whole app while the connection is down.
///
/// Wraps the app rather than floating over it, so it pushes the content down
/// instead of covering an app bar. While it is hidden — which is nearly
/// always — it returns [child] untouched and costs nothing.
class OfflineBanner extends StatelessWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  static const Color _down = Color(0xFF1C1C1E);
  static const Color _back = Color(0xFF1E7F4E);

  @override
  Widget build(BuildContext context) {
    final network = context.watch<ConnectivityProvider>();

    if (!network.showBanner) return child;

    final restored = network.justRestored;
    final topInset = MediaQuery.paddingOf(context).top;

    return Column(
      children: [
        Material(
          color: restored ? _back : _down,
          child: Padding(
            // Paints behind the status bar and keeps its text clear of it, so
            // the strip reads as part of the system chrome rather than as a
            // dialog that has landed in the wrong place.
            padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  restored ? Icons.wifi : Icons.wifi_off_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    restored ? 'Back online' : 'No internet connection',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!restored) ...[
                  const SizedBox(width: 14),
                  // The probe retries on its own, so this is only for someone
                  // who has just fixed it and does not want to wait out the
                  // backoff.
                  InkWell(
                    onTap: network.refresh,
                    borderRadius: BorderRadius.circular(999),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      child: Text(
                        'Retry',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // The strip has taken the status bar inset, so the app below must not
        // take it a second time — every SafeArea in there would add a second
        // gap the size of the notch.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
