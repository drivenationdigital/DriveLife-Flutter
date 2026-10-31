import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's two typefaces.
///
///   Barlow Condensed 800 — titles and headings
///   DM Sans 600          — everything else
///
/// HOW THIS REACHES THE SCREEN, WHICH IS NOT OBVIOUS
///
/// [textTheme] gives Material its styles, and that is enough for the
/// BODY face: a `Text` with `TextStyle(fontSize: 14)` and no family
/// merges onto the ambient DefaultTextStyle, which Material builds from
/// `textTheme.bodyMedium`. So setting the theme turns all 1,600-odd
/// inline styles in this app into DM Sans without touching one of them.
///
/// Headings cannot work that way. This codebase has no `textTheme.`
/// references at all — every heading is an inline TextStyle with a size
/// and a weight — and nothing in Flutter lets a theme say "anything at
/// w800 is a different typeface". So a heading has to ASK, with
/// [heading]. Until a given screen does, its headings are DM Sans 800,
/// which looks deliberate rather than broken, so the migration can be
/// done a screen at a time.
///
/// WHY CONDENSED CHANGES MEASUREMENTS
///
/// Barlow Condensed is materially narrower than Roboto, which is what
/// this app has been rendering in. Headings will occupy roughly a fifth
/// less width at the same point size and read slightly smaller, because
/// perceived size tracks x-height and cap height rather than the number
/// in the style. Anywhere a heading was sized to just fit, it now fits
/// with room; anywhere a fixed height was tuned to Roboto's line metrics
/// may shift by a pixel or two.
class DlType {
  const DlType._();

  /// Headings are set in capitals, always.
  ///
  /// Tracking for all-caps, as a fraction of the font size. Capitals set
  /// at a face's default spacing look cramped: that spacing is fitted to
  /// lower-case shapes, which have ascenders and descenders to separate
  /// them, where capitals are a row of same-height rectangles. Every
  /// type foundry's advice is to open caps up slightly, and a condensed
  /// face needs it more than most.
  ///
  /// 0.02em is restrained — enough to stop the letters touching without
  /// turning a heading into a logo.
  static const double _capsTracking = 0.02;

  /// Titles and headings. Barlow Condensed, 800 by default.
  ///
  /// Prefer [DlHeading], which also applies the capitals. This returns
  /// the bare style, for the places a widget cannot go — a TextSpan
  /// inside a RichText, say — and there the caller has to uppercase the
  /// string itself.
  ///
  /// The weight is a parameter rather than fixed because a heading
  /// hierarchy needs more than one step, and dropping to 600 within the
  /// same family is a better way to make a subheading than switching
  /// face.
  static TextStyle heading({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w800,
    Color? color,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
    FontStyle? fontStyle,
  }) => GoogleFonts.barlowCondensed(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    // Scaled off the size rather than a flat number of pixels, so a
    // 35pt title and a 15pt label are tracked by the same proportion.
    // A flat value that suits one looks wrong on the other.
    letterSpacing: letterSpacing ?? (fontSize ?? 16) * _capsTracking,
    decoration: decoration,
    fontStyle: fontStyle,
  );

  /// Everything that is not a heading. DM Sans, 600 by default.
  ///
  /// Rarely needed directly: the theme already makes DM Sans the default
  /// family, so a plain `TextStyle(fontSize: 14)` is already this. Use
  /// it where a style is built outside a widget tree and cannot inherit.
  static TextStyle body({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
    FontStyle? fontStyle,
  }) => GoogleFonts.dmSans(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    decoration: decoration,
    fontStyle: fontStyle,
  );

  /// The default AppBar title.
  ///
  /// Matches the hand-built header on the create-post screen, which is
  /// the one this app was already getting right: 17, extra bold, barely
  /// tracked. Screens that set their own style still win — this is the
  /// floor, so a screen that says nothing looks like the rest.
  static AppBarTheme appBarTheme() => AppBarTheme(
    titleTextStyle: body(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
      color: const Color(0xFF0B0B0B),
    ),
  );

  /// Tab labels, stated outright rather than inherited.
  ///
  /// Every TabBar in the app passes its own `labelStyle` with a size and
  /// a weight and no family, which merges onto this. Without it the
  /// family came from textTheme.titleSmall, which is a long way from
  /// the TabBar for something that decides how it looks — and is how
  /// every tab in the app silently went condensed.
  ///
  /// w700 selected against w600 unselected: the colour already
  /// distinguishes them, and the weight step keeps that true for
  /// somebody who cannot rely on the colour.
  static TabBarThemeData tabBarTheme() => TabBarThemeData(
    labelStyle: body(fontSize: 14, fontWeight: FontWeight.w700),
    unselectedLabelStyle: body(fontSize: 14, fontWeight: FontWeight.w600),
  );

  /// The Material text theme: headings condensed, everything else DM Sans.
  ///
  /// Display, headline and title roles take Barlow Condensed; body and
  /// label take DM Sans. Anything in the app that does reach for
  /// `Theme.of(context).textTheme` gets the right face for free, and the
  /// ambient default — which is what every inline style inherits from —
  /// comes from bodyMedium and is therefore DM Sans.
  static TextTheme textTheme(TextTheme base) {
    final headings = GoogleFonts.barlowCondensedTextTheme(base);
    final body = GoogleFonts.dmSansTextTheme(base);

    TextStyle? h(TextStyle? style) =>
        style?.copyWith(fontWeight: FontWeight.w800);

    TextStyle? b(TextStyle? style) =>
        style?.copyWith(fontWeight: FontWeight.w600);

    return base.copyWith(
      displayLarge: h(headings.displayLarge),
      displayMedium: h(headings.displayMedium),
      displaySmall: h(headings.displaySmall),
      headlineLarge: h(headings.headlineLarge),
      headlineMedium: h(headings.headlineMedium),
      headlineSmall: h(headings.headlineSmall),
      // titleLarge is where an AppBar's title resolves, and it is DM
      // Sans, not the condensed face.
      //
      // It was condensed, on the reasoning that a screen title is a
      // heading. In practice that split the app in two: a screen with a
      // real AppBar got Barlow Condensed and a screen with a
      // hand-built header row got DM Sans, so "Messages" and "New post"
      // were set in different typefaces for no reason a user could
      // see.
      //
      // Headings that genuinely want the condensed face ask for it with
      // DlHeading. An AppBar title is a label for where you are, which
      // is the same job as the rest of the chrome around it.
      titleLarge: b(body.titleLarge),

      // titleMedium and titleSmall are NOT. Material uses them for
      // component labels: TabBar.labelStyle falls back to titleSmall,
      // and a ListTile's title to titleMedium. Mapping them to the
      // condensed face put tab labels in Barlow Condensed, where the
      // screens that override the weight down to w600 rendered them
      // narrow and light — "slim and thin", which is condensed doing
      // what condensed does at a label size.
      //
      // The rule this encodes: Barlow Condensed is for type somebody
      // READS as a title. Anything that labels a control is body.
      titleMedium: b(body.titleMedium),
      titleSmall: b(body.titleSmall),

      bodyLarge: b(body.bodyLarge),
      bodyMedium: b(body.bodyMedium),
      bodySmall: b(body.bodySmall),
      labelLarge: b(body.labelLarge),
      labelMedium: b(body.labelMedium),
      labelSmall: b(body.labelSmall),
    );
  }
}

/// A heading: Barlow Condensed, extra bold, in capitals.
///
/// A widget rather than a style, because a TextStyle cannot change the
/// text. Uppercasing at each call site would work until somebody added
/// the next heading and forgot, and then one screen would quietly be
/// different from the rest — so the rule lives in one place and the call
/// sites pass the sentence as they would write it.
class DlHeading extends StatelessWidget {
  final String text;

  final double? fontSize;
  final FontWeight fontWeight;
  final Color? color;
  final double? height;

  /// Overrides the tracking that [DlType.heading] derives from the size.
  final double? letterSpacing;

  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const DlHeading(
    this.text, {
    super.key,
    this.fontSize,
    this.fontWeight = FontWeight.w800,
    this.color,
    this.height,
    this.letterSpacing,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      // toUpperCase and not a textTransform, because Flutter has no
      // textTransform. This is the whole mechanism.
      text.toUpperCase(),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: DlType.heading(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      ),
    );
  }
}
