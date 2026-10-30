import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Where the app's haptics are chosen, so every tab feels the same.
abstract final class DLHaptics {
  /// Changing tab: the bottom nav, the top sections, and the sub-tabs
  /// inside a screen.
  ///
  /// `mediumImpact`, not `selectionClick`. selectionClick is the faint tick
  /// meant for a spinning picker wheel, and through a phone case most
  /// people cannot feel it at all. Changing tab replaces everything on
  /// screen, so it should land like a button rather than a rumour.
  static void tabChange() => HapticFeedback.mediumImpact();

  /// A long press that opened something: the reaction row on a message.
  ///
  /// `heavyImpact` rather than the medium used for tabs. A long press has
  /// no visible progress — you are holding still, waiting to find out
  /// whether the gesture registered — so the tap back is the only
  /// confirmation, and it arrives at the moment the sheet starts to
  /// animate in. Making it the heaviest of the three is what separates
  /// "it worked" from "something moved".
  static void longPressMenu() => HapticFeedback.heavyImpact();
}

/// Makes [controller] fire [DLHaptics.tabChange] whenever it moves to a
/// different tab — by tap, and by swipe where the view allows one.
///
/// Call it once, from `initState`. There is nothing to undo: the listener
/// lives on the controller and goes when the controller is disposed.
///
/// A TabController notifies on every frame of the indicator animation, and
/// `animation.value` passes through every number in between, so reacting to
/// notifications alone would buzz a dozen times for one tab. This fires on
/// the integer index actually changing, which happens once per move.
void attachTabHaptics(TabController controller) {
  var last = controller.index;

  controller.addListener(() {
    if (controller.index == last) return;
    last = controller.index;
    DLHaptics.tabChange();
  });
}
