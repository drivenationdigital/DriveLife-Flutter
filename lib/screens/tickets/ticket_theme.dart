import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// The look of the ticket checkout, in one place.
///
/// Three screens that have to feel like one flow, so the cards, fields and
/// bottom bar are built here rather than repeated. It mirrors the web
/// checkout's palette — the same cream ground and gold accent — because a
/// buyer can end up on either.
abstract final class TicketTheme {
  const TicketTheme._();

  static const Color ink = Color(0xFF14140F);
  static const Color muted = Color(0xFF7A7A72);
  static const Color gold = Color(0xFFC4A062);
  static const Color line = Color(0xFFE8E6E1);
  static const Color canvas = Color(0xFFFAF9F7);
  static const Color danger = Color(0xFFC0392B);

  /// "£12.00", in the event's currency.
  static String money(double amount, String currency) {
    final symbol = switch (currency.toUpperCase()) {
      'USD' => r'$',
      'EUR' => '€',
      _ => '£',
    };

    return NumberFormat.currency(
      symbol: symbol,
      decimalDigits: 2,
    ).format(amount);
  }

  /// The bar at the top, with which step this is.
  static PreferredSizeWidget appBar(
    BuildContext context,
    String title, {
    required int step,
  }) {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.chevron_left, color: ink, size: 30),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'Step $step of 3',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: Row(
          children: [
            for (var i = 1; i <= 3; i++)
              Expanded(
                child: Container(height: 3, color: i <= step ? gold : line),
              ),
          ],
        ),
      ),
    );
  }

  /// A white panel with an optional heading.
  static Widget card({
    required Widget child,
    String? title,
    String? subtitle,

    /// Numbers the card, which is how the checkout shows its order of
    /// business. Omitted for a card that is not a step in itself.
    int? step,

    /// Runs the heading full width with a rule under it, for a card whose
    /// contents are a list rather than a form.
    bool ruledHeader = false,
    EdgeInsets padding = const EdgeInsets.fromLTRB(16, 16, 16, 16),
  }) {
    final heading = title == null
        ? null
        : Row(
            children: [
              if (step != null) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: gold,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$step',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: muted,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A ruled header sits edge to edge with its own padding so the rule
          // reaches both sides of the card rather than floating inside it. A
          // plain one just stacks above the content.
          if (heading != null && ruledHeader) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, 14, padding.right, 12),
              child: heading,
            ),
            const Divider(height: 1, thickness: 1, color: line),
          ],
          Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (heading != null && !ruledHeader) ...[
                  heading,
                  const SizedBox(height: 14),
                ],
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The checkout's own page header: eyebrow, event, date.
  ///
  /// Centred and quiet. The buyer already knows which event they tapped, so
  /// this says where they have arrived rather than what they are choosing.
  static Widget pageHeader({
    required String eyebrow,
    required String title,
    String? subtitle,

    /// Shown above the eyebrow, as the web checkout shows it. Skipped when
    /// there is no image rather than leaving a gap where one would be.
    String? imageUrl,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 96,
                // contain, not cover: this is a logo as often as a photo, and
                // cropping somebody's branding to fill a box is worse than
                // letting it sit in the space it wants.
                fit: BoxFit.contain,
                memCacheHeight: 288,
                // A missing image is not worth a hole in the header — the
                // title and date below say what this is on their own.
                errorWidget: (_, _, _) => const SizedBox.shrink(),
                placeholder: (_, _) => const SizedBox(height: 96),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            eyebrow.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: gold,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ink,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A "Done" strip that appears above the keyboard while one is open.
  ///
  /// iOS's phone and number pads have no return key, so a buyer who taps a
  /// phone field is left with a keyboard and no obvious way to close it. This
  /// is the visible answer; [field] also dismisses on a tap outside, which is
  /// what somebody who already knows the gesture will reach for first.
  ///
  /// Nothing on Android, where the system back gesture closes the keyboard
  /// and every keyboard has its own dismiss key — a second one would be
  /// clutter.
  ///
  /// Goes last in a [Stack] that fills the body, so it settles against the
  /// bottom of the space the keyboard leaves.
  static Widget keyboardDismissBar(BuildContext context) {
    if (!Platform.isIOS) return const SizedBox.shrink();

    // The field is focused but the keyboard has not finished coming up, or is
    // on its way out. Reading the inset rather than the focus means the strip
    // tracks the keyboard itself and cannot be left stranded on screen.
    if (MediaQuery.of(context).viewInsets.bottom <= 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerRight,
        decoration: const BoxDecoration(
          color: Color(0xFFF4F2EC),
          border: Border(top: BorderSide(color: line)),
        ),
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              'Done',
              style: TextStyle(
                color: gold,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Who is actually selling the ticket, in the smallest voice available.
  static Widget poweredBy(String company) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        'Powered by ${company.isEmpty ? 'CarEvents.com' : company}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFA9A69D), fontSize: 12.5),
      ),
    );
  }

  /// A blocking "working on it" over whatever is underneath.
  ///
  /// Blocking on purpose: these moments reserve stock and open payments, and
  /// a second tap during one is how a buyer ends up with two carts.
  static Widget overlay(String label) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black26,
        child: Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(32, 26, 32, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(strokeWidth: 3, color: gold),
                ),
                const SizedBox(height: 16),
                Text(
                  label,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A labelled text input.
  static Widget field({
    required String label,
    required TextEditingController controller,
    String? error,
    String? hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,

    /// The label is a sentence somebody wrote, not the name of a field.
    ///
    /// An organiser's custom question is prose — often a full sentence, often
    /// long enough to wrap. Small caps at 10.5px with letter spacing is right
    /// for "PHONE NUMBER" and close to unreadable for "Would you like to ask
    /// the question yourself or have it asked for you?".
    bool proseLabel = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          proseLabel ? label : label.toUpperCase(),
          style: proseLabel
              ? const TextStyle(
                  color: ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                )
              : const TextStyle(
                  color: muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          // Tapping the form anywhere outside the field closes the keyboard.
          // Flutter does not do this on mobile by default, and on iOS a phone
          // field has no return key to close it with — so without this the
          // keyboard can only be dismissed by scrolling blind or submitting.
          // See also [keyboardDismissBar], which makes the same escape
          // visible rather than relying on the buyer guessing.
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          style: const TextStyle(fontSize: 15, color: ink),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(color: muted, fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 13,
            ),
            filled: true,
            fillColor: const Color(0xFFFCFCFB),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: error == null ? line : danger),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: error == null ? gold : danger,
                width: 1.6,
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 5),
          Text(error, style: const TextStyle(color: danger, fontSize: 12)),
        ],
      ],
    );
  }

  /// A tick box with its label as the tap target.
  static Widget checkbox({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? error,

    /// Replaces the plain [label] where part of it has to be tappable — a
    /// terms link, say. The box itself still toggles from its own tap target,
    /// so tapping the link cannot accidentally tick the box.
    Widget? richLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: value,
                    onChanged: (v) => onChanged(v ?? false),
                    activeColor: gold,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: error == null ? const Color(0xFFBFBDB6) : danger,
                      width: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child:
                        richLabel ??
                        Text(
                          label,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 33, bottom: 4),
            child: Text(
              error,
              style: const TextStyle(color: danger, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Pick-or-replace for a single photo.
  static Widget photoField({
    required String label,
    required String url,
    required bool busy,
    required VoidCallback onPick,
    String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F3F0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: error == null ? line : danger),
              ),
              clipBehavior: Clip.antiAlias,
              child: busy
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : url.isEmpty
                  ? const Icon(
                      Icons.directions_car_outlined,
                      color: muted,
                      size: 26,
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      memCacheWidth: 220,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onPick,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  side: const BorderSide(color: line),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  url.isEmpty ? 'Choose photo' : 'Replace photo',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error, style: const TextStyle(color: danger, fontSize: 12)),
        ],
      ],
    );
  }

  /// One line of an order summary: what it is on the left, what it costs on
  /// the right.
  static Widget summaryRow(
    String label,
    String value, {
    bool bold = false,
    bool accent = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: bold ? ink : muted,
                fontSize: bold ? 15 : 13.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: accent ? gold : ink,
              fontSize: bold ? 17 : 13.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              // Figures line up down the column rather than jittering as the
              // digits change.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// Something the buyer needs to read before carrying on.
  static Widget notice(String message, {bool isError = true}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFDF2F1) : const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? const Color(0xFFF3D3D0) : const Color(0xFFF0DCC0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 17,
            color: isError ? danger : const Color(0xFF9A6B1E),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError
                    ? const Color(0xFF8A2E24)
                    : const Color(0xFF7A5416),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The total and the one action, pinned to the bottom.
  static Widget bar({
    required String label,
    required String value,
    required String action,
    required VoidCallback onPressed,
    bool busy = false,
    bool enabled = true,
  }) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: busy || !enabled ? null : onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE8E4DA),
                  disabledForegroundColor: const Color(0xFFA9A69D),
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        action,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
