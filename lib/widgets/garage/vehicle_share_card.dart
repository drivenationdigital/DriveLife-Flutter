/// A vehicle as a picture you can send someone.
///
/// ── WHY AN IMAGE AND NOT A LINK ─────────────────────────────────────
///
/// Sharing a vehicle already worked: it sent a title and a URL. The
/// trouble with a URL is that it is a promise — the person receiving it
/// has to believe there is something worth tapping through to, in a
/// thread where nothing else asks them to leave. A photograph of the
/// car, with its name and its numbers on it, IS the thing. The link
/// rides along underneath for anybody who wants it.
///
/// It is also the first real use for the performance figures. Until now
/// they sat in a form and then on a page the owner already knew the
/// contents of. On a card they are the reason somebody stops scrolling.
///
/// ── AND WHY IT IS DRAWN RATHER THAN SCREENSHOTTED ───────────────────
///
/// A screenshot of the vehicle page would carry a status bar, a back
/// button, an app bar and whatever the person's phone does to a corner.
/// This is laid out once, at one fixed size, independent of the device
/// it is made on — so the card a 5-year-old Android makes and the card
/// an iPhone makes are the same card.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:drivelife/theme/dl_type.dart';

/// The card's drawn width in logical pixels.
///
/// Captured at [_pixelRatio], so the file is 1080 across: the width
/// Instagram, WhatsApp and Messages all treat as full resolution, and
/// small enough that nothing downscales it into mush.
const double _cardWidth = 540;

const double _pixelRatio = 2;

const Color _black = Color(0xFF0B0B0B);

/// Shows the card, then offers to send it.
///
/// The preview is not decoration. A share sheet that fires straight
/// into the OS gives somebody no idea what they just put in front of
/// their friends — and this card carries a registration, a location's
/// worth of background detail, and whatever is parked behind the car.
/// Seeing it first is what makes sharing it a decision.
class VehicleShareSheet {
  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> vehicle,
    required Object garageId,
    required Color accent,
    String? photo,
  }) async {
    // What the caller has on screen wins. The vehicle page loads its
    // photographs as their own rows -- cover merged in at the front --
    // so the map alone would fall back to the cover column and send a
    // different picture than the one being looked at.
    final chosen = (photo ?? '').trim().isNotEmpty
        ? photo!.trim()
        : VehicleCardFacts.photo(vehicle);

    // Asked for before the sheet opens, so the card does not assemble
    // itself in front of somebody. A failure here is not an error: the
    // card falls back to type on black, which is a poster rather than a
    // broken image.
    if (chosen.isNotEmpty) {
      try {
        await precacheImage(NetworkImage(chosen), context);
      } catch (_) {
        // Drawn without it.
      }
    }

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ShareSheetBody(
        vehicle: vehicle,
        garageId: garageId,
        accent: accent,
        photo: chosen,
      ),
    );
  }
}

class _ShareSheetBody extends StatefulWidget {
  final Map<String, dynamic> vehicle;
  final Object garageId;
  final Color accent;
  final String photo;

  const _ShareSheetBody({
    required this.vehicle,
    required this.garageId,
    required this.accent,
    required this.photo,
  });

  @override
  State<_ShareSheetBody> createState() => _ShareSheetBodyState();
}

class _ShareSheetBodyState extends State<_ShareSheetBody> {
  final _cardKey = GlobalKey();

  bool _busy = false;

  String get _url =>
      'https://app.mydrivelife.com/vehicle/${widget.garageId}?ref=share';

  String get _title {
    final name = VehicleCardFacts.name(widget.vehicle);

    if (name.isNotEmpty) return name;

    final reg = VehicleCardFacts.text(widget.vehicle, 'registration');

    return reg.isNotEmpty ? reg : 'a vehicle';
  }

  /// Sends the card, with the link underneath it.
  ///
  /// Both, not one. The image is what gets looked at and the link is
  /// what can be followed, and which of the two matters depends
  /// entirely on where it lands.
  Future<void> _shareImage() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      final bytes = await _capture();

      if (bytes == null) {
        if (mounted) _say('Could not make the image. Sharing the link.');
        await _shareLink();
        return;
      }

      final dir = await getTemporaryDirectory();

      // Named per vehicle rather than per moment, so sharing the same
      // car twice replaces one temporary file instead of leaving a
      // trail of them in the cache directory.
      final file = File('${dir.path}/drivelife_vehicle_${widget.garageId}.png');

      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '$_title on DriveLife\n$_url',
          subject: _title,
        ),
      );
    } catch (e) {
      debugPrint('[VehicleShare] image share failed: $e');

      if (mounted) _say('Could not make the image. Sharing the link.');

      await _shareLink();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareLink() async {
    await SharePlus.instance.share(
      ShareParams(text: '$_title on DriveLife\n$_url', subject: _title),
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The card, as PNG bytes.
  ///
  /// Waits for the end of a frame first. The card is on screen, so it
  /// has almost certainly painted — but "almost certainly" is how you
  /// get a blank or half-drawn image on the one device that schedules
  /// differently, and the wait costs a sixtieth of a second.
  Future<Uint8List?> _capture() async {
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) return null;

    final object = _cardKey.currentContext?.findRenderObject();

    if (object is! RenderRepaintBoundary) return null;

    final image = await object.toImage(pixelRatio: _pixelRatio);

    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);

      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, bottom > 0 ? 8 : 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),

            // ── THE CARD, AT ITS OWN SIZE ─────────────────────────
            //
            // Drawn 540 wide whatever the phone is, and scaled down to
            // fit by the FittedBox above it. The capture reads the
            // boundary's own subtree, so what comes out is the full
            // 540 — the scaling here is how it is LOOKED at, not how
            // it is made.
            //
            // Text scaling is pinned off for the same reason. Somebody
            // with large type set should not send a card with the make
            // and model overflowing the panel.
            Flexible(
              child: FittedBox(
                fit: BoxFit.contain,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.noScaling),
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: VehicleShareCard(
                      vehicle: widget.vehicle,
                      accent: widget.accent,
                      photo: widget.photo,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : _shareImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accent,
                  disabledBackgroundColor: widget.accent.withValues(alpha: 0.5),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Share image',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),

            // Kept, deliberately. Sharing a vehicle used to send a
            // link, and somebody pasting one into a forum or a group
            // chat does not want 400KB of PNG with it.
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      Navigator.pop(context);
                      _shareLink();
                    },
              child: const Text(
                'Share link instead',
                style: TextStyle(
                  color: Color(0xFF6B6B6B),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card itself. Nothing in here knows about sharing.
///
/// Separated so it can be dropped into a preview, a capture, or
/// anywhere else, and so that what gets photographed is exactly what
/// was on screen.
class VehicleShareCard extends StatelessWidget {
  final Map<String, dynamic> vehicle;
  final Color accent;

  /// The photograph to use. Empty draws the card without one.
  final String photo;

  const VehicleShareCard({
    super.key,
    required this.vehicle,
    required this.accent,
    required this.photo,
  });

  @override
  Widget build(BuildContext context) {
    final name = VehicleCardFacts.name(vehicle);
    final handle = '${(vehicle['owner'] as Map?)?['username'] ?? ''}'.trim();

    final stats = VehicleCardFacts.stats(vehicle);

    return SizedBox(
      width: _cardWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Photo(photo: photo, accent: accent),

          // ── THE BLACK PANEL ───────────────────────────────────────
          //
          // The same block the vehicle page uses under its gallery,
          // for the same reason: the car's name and its numbers belong
          // together, on something that does not compete with the
          // photograph above them.
          ColoredBox(
            color: _black,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DlHeading(
                    name.isEmpty ? 'Vehicle' : name,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.03,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  if (handle.isNotEmpty || VehicleCardFacts.subtitle(vehicle).isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (handle.isNotEmpty)
                          Text(
                            '@$handle',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (handle.isNotEmpty && VehicleCardFacts.subtitle(vehicle).isNotEmpty)
                          Text(
                            '  ·  ',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 15,
                            ),
                          ),
                        if (VehicleCardFacts.subtitle(vehicle).isNotEmpty)
                          Text(
                            VehicleCardFacts.subtitle(vehicle),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 15,
                            ),
                          ),
                      ],
                    ),
                  ],

                  // No empty row. A car with no figures entered gets a
                  // card without a figures strip, rather than three
                  // dashes where its numbers should be — which reads
                  // as the card being broken rather than the fields
                  // being blank.
                  if (stats.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Divider(
                      color: Colors.white.withValues(alpha: 0.14),
                      height: 1,
                    ),
                    const SizedBox(height: 18),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < stats.length; i++) ...[
                            if (i > 0)
                              Container(
                                width: 1,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            Expanded(
                              child: _CardStat(
                                label: stats[i].label,
                                value: stats[i].value,
                                unit: stats[i].unit,
                                accent: accent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── THE FOOTER ────────────────────────────────────────────
          //
          // White, because the logo asset is the dark one — the same
          // file every white app bar in the app already uses. Putting
          // it on the background it was drawn for is cheaper and
          // truer than tinting it, and the strip gives the card a
          // bottom edge it would otherwise not have against a dark
          // chat background.
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Image.asset(
                  'assets/logo-dark.png',
                  height: 20,
                  // A missing asset must not take the whole card with
                  // it — the capture would fail and the share would
                  // silently become a link.
                  errorBuilder: (_, __, ___) => const Text(
                    'DRIVELIFE',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                const Text(
                  'app.mydrivelife.com',
                  style: TextStyle(
                    color: Color(0xFF8A8A8A),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The photograph, fading into the panel beneath it.
class _Photo extends StatelessWidget {
  final String photo;
  final Color accent;

  const _Photo({required this.photo, required this.accent});

  @override
  Widget build(BuildContext context) {
    // 4:3. Taller than a wide crop, because a car photographed by its
    // owner is usually a three-quarter shot with the car in the middle,
    // and a letterbox takes the wheels off it.
    const height = _cardWidth * 0.75;

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo.isNotEmpty)
            Image.network(
              photo,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _Fallback(accent: accent),
            )
          else
            _Fallback(accent: accent),

          // Into the panel, so there is no seam where one ends and the
          // other starts.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 90,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_black.withValues(alpha: 0), _black],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  final Color accent;

  const _Fallback({required this.accent});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.35), _black],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.directions_car_filled_rounded,
          size: 86,
          color: Colors.white.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color accent;

  const _CardStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: accent,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 7),
        // Baseline-aligned, so the unit sits on the number's feet
        // rather than floating beside its middle.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Reading the vehicle ─────────────────────────────────────────

/// One figure, as it is printed.
class VehicleCardStat {
  final String label;
  final String value;
  final String unit;

  const VehicleCardStat(this.label, this.value, this.unit);
}

/// What the card says about a vehicle.
///
/// Its own class because what goes on a card is a decision rather than
/// a formatting detail — this is the part that can be wrong in a way
/// somebody then sends to their friends, and the part worth checking
/// without a screen in front of it.
class VehicleCardFacts {
  const VehicleCardFacts._();

  static String text(Map<String, dynamic>? map, String key) =>
      '${map?[key] ?? ''}'.trim();

  /// "Ford Mustang Dark Horse".
  static String name(Map<String, dynamic> vehicle) => [
    text(vehicle, 'make'),
    text(vehicle, 'model'),
    text(vehicle, 'variant'),
  ].where((p) => p.isNotEmpty).join(' ');

  /// "2026 · Grey", under the handle.
  ///
  /// The registration is deliberately NOT here. It is on the car in
  /// the photograph for anybody who looks, which is a different thing
  /// from setting it in type beside the owner's name on something
  /// built to be forwarded on.
  static String subtitle(Map<String, dynamic> vehicle) => [
    text(vehicle, 'year'),
    text(vehicle, 'colour'),
  ].where((p) => p.isNotEmpty).join(' · ');

  /// Whichever of the three figures this car actually has.
  static List<VehicleCardStat> stats(Map<String, dynamic> vehicle) {
    final out = <VehicleCardStat>[];

    void add(String label, String key, String unit) {
      final value = number(vehicle[key]);

      if (value.isNotEmpty) out.add(VehicleCardStat(label, value, unit));
    }

    add('POWER', 'vehicle_bhp', 'bhp');
    add('0-62', 'vehicle_062', 'sec');
    add('TOP SPEED', 'vehicle_top_speed', 'mph');

    return out;
  }

  /// A stored figure as something to print, or '' if there is not one.
  ///
  /// Zero is not a figure. The form stores an unanswered field as 0,
  /// so "0 bhp" is what "I never filled that in" looks like coming
  /// back out of the database.
  static String number(dynamic raw) {
    final value = raw is num ? raw : num.tryParse('${raw ?? ''}');

    if (value == null || value == 0) return '';

    return value == value.roundToDouble() ? '${value.round()}' : '$value';
  }

  /// The photograph to put on the card.
  ///
  /// The cover first, then the first gallery image for a vehicle whose
  /// cover column never got filled in.
  static String photo(Map<String, dynamic> vehicle) {
    final cover = text(vehicle, 'cover_photo');

    if (cover.isNotEmpty) return cover;

    final photos = vehicle['photos'];

    if (photos is List) {
      for (final row in photos) {
        if (row is String && row.trim().isNotEmpty) return row.trim();

        if (row is Map) {
          final url = '${row['url'] ?? row['image'] ?? ''}'.trim();

          if (url.isNotEmpty) return url;
        }
      }
    }

    return '';
  }
}
