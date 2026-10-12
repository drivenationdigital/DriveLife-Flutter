import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Whether the app's chrome — header, section tabs, bottom bar — is showing.
///
/// On a long feed the chrome is worth roughly a third of a phone screen, and
/// none of it is what somebody came to look at. So it gets out of the way as
/// they read, and comes back when they deliberately scroll back up or reach
/// the top.
///
/// What stays either way is the feed selector, which is pinned separately.
/// Hiding that would mean scrolling back to the top to change tab, which is
/// the one thing this is supposed to save.
class ChromeVisibility extends ValueNotifier<bool> {
  ChromeVisibility() : super(true);

  /// How far the reader has to drag before the chrome reacts.
  ///
  /// Asymmetric on purpose, and the difference is the whole feel of it.
  /// Hiding is cheap to be wrong about — the chrome comes back — so it goes
  /// early. Showing is expensive to be wrong about: it shoves the feed down
  /// mid-read, so it waits for a movement that clearly means "bring it back"
  /// rather than a thumb settling or the small upward drift at the end of a
  /// flick.
  static const double _hideAfter = 40;
  static const double _showAfter = 110;

  /// Distance dragged since the chrome last changed, signed: positive is
  /// down the page.
  double _dragged = 0;

  bool _pending = false;

  /// Feed a scroll notification in. Returns false so it keeps bubbling.
  bool handle(ScrollNotification notification) {
    // Horizontal scrolling belongs to a carousel inside a post, not to the
    // page, and must not move the chrome.
    if (notification.metrics.axis != Axis.vertical) return false;

    // Only movement the reader's finger actually caused.
    //
    // `dragDetails` is what makes this safe. An earlier version read raw
    // offsets, and that fed back on itself: hiding the header shortened the
    // viewport, the new metrics arrived as another update, and the chrome
    // toggled again — a loop that ate the gesture and made the feed
    // impossible to scroll. Layout-driven updates carry no drag details, so
    // they cannot drive this.
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;

      // Turning around starts the count again, so a long read down the page
      // does not leave credit that makes the next flick upward instant.
      if (delta != 0 && !delta.isNegative != !_dragged.isNegative) {
        _dragged = 0;
      }

      _dragged += delta;

      if (_dragged > _hideAfter) {
        _dragged = 0;
        _set(false);
      } else if (_dragged < -_showAfter) {
        _dragged = 0;
        _set(true);
      }
    }

    // Lifting the finger clears the count: the next gesture is a new
    // intention and should not inherit half a threshold from the last one.
    if (notification is ScrollEndNotification) _dragged = 0;

    // At the very top the chrome is always shown, whatever the gesture was.
    // This is what people reach for when they want it back, and it also
    // covers an overscroll bounce.
    if (notification.metrics.pixels <= 0) _set(true);

    return false;
  }

  /// Changes the value without scheduling a build inside a running frame.
  ///
  /// Scroll notifications can be dispatched from layout, and setting a
  /// listenable then throws "Build scheduled during frame". When a frame is
  /// already in flight the change waits for the end of it.
  void _set(bool next) {
    if (value == next || _pending) return;

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      value = next;
      return;
    }

    _pending = true;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      // Re-checked rather than assumed: a whole frame has passed, and the
      // gesture may have turned around in it.
      if (value != next) value = next;
    });
  }

  void show() {
    _dragged = 0;
    _set(true);
  }

  /// Called when a screen that hides chrome goes away, so the next one does
  /// not inherit a hidden header it has no way to bring back.
  void reset() => show();

  @override
  void dispose() {
    _pending = true; // stops a queued callback touching a dead notifier
    super.dispose();
  }
}
