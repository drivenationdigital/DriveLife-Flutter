import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Makes a build-time crash say where it came from.
///
/// Flutter already prints the exception, but the console prints the whole
/// framework stack with it — forty frames of `Element.inflateWidget` and
/// `ComponentElement.performRebuild` with our own code nowhere in sight,
/// because by the time a widget builds, the method that created it has long
/// since returned. Reading which screen broke out of that is the problem.
///
/// This reprints the same error with the two things that actually locate it:
/// the frames that are ours, and the widget the framework blames.
///
/// Debug only. In release the default handler is left alone.
void installCrashTrace() {
  if (!kDebugMode) return;

  final previous = FlutterError.onError;

  FlutterError.onError = (details) {
    previous?.call(details);

    debugPrint('');
    debugPrint('╔══ DRIVELIFE ══════════════════════════════════════════');
    debugPrint('║ ${details.exception}');

    // Which of our widgets the framework was building. This is the line
    // that names the screen, and the default dump buries it in prose.
    final context = details.context?.toDescription();
    if (context != null && context.isNotEmpty) {
      debugPrint('║ while: $context');
    }

    final blamed = details.informationCollector
        ?.call()
        .map((node) => node.toDescription())
        .where((line) => line.contains('drivelife'))
        .toList();

    if (blamed != null && blamed.isNotEmpty) {
      for (final line in blamed) {
        debugPrint('║ $line');
      }
    }

    // Our own frames, in order, with the framework's thrown away. The
    // topmost one is where to look.
    final ours = details.stack
        .toString()
        .split('\n')
        .where((line) => line.contains('package:drivelife/'))
        .take(8)
        .toList();

    if (ours.isEmpty) {
      debugPrint('║ no drivelife frames — the throw is inside a widget we');
      debugPrint('║ handed bad data to. The "while:" line above names it.');
    } else {
      debugPrint('║ ours:');
      for (final line in ours) {
        debugPrint('║   ${line.trim()}');
      }
    }

    debugPrint('╚═══════════════════════════════════════════════════════');
    debugPrint('');
  };
}

/// Names the subtree it wraps in any build-time crash underneath it.
///
/// Wrap the parts of a screen you are trying to tell apart. The label is
/// pushed on before the children build and popped after, so whatever is on
/// the stack when something throws is the innermost label that contains it.
///
/// Costs nothing in release: it returns [child] untouched.
class CrashTrace extends StatelessWidget {
  final String label;
  final Widget child;

  const CrashTrace({super.key, required this.label, required this.child});

  /// The labels currently being built, outermost first.
  static final List<String> _open = [];

  /// Where the last build got to, for printing beside an exception.
  static String get trail => _open.isEmpty ? '(none)' : _open.join(' › ');

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;

    _open.add(label);
    debugPrint('🔎 building: $trail');

    // Popped on the next frame rather than here: the children have not been
    // built yet when this returns, so popping now would clear the trail
    // before the thing it describes has run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_open.isNotEmpty) _open.removeLast();
    });

    return child;
  }
}
