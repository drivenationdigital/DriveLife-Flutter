import 'dart:convert';

import 'package:drivelife/config/app_environment.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Putting an image on Cloudflare and getting a URL back.
///
/// The app already does this in three places — profile pictures, cover
/// photos, post media — each with its own private copy of the same two
/// steps, because each then hands the id to a different WordPress
/// endpoint to be saved.
///
/// This one is for the callers that have nowhere in WordPress to save it.
/// A group chat lives in Supabase, which has no access to
/// get_cloudflare_media_url, so it needs a finished URL rather than a
/// bare id.
class CloudflareImages {
  /// The account's delivery host.
  ///
  /// Matches get_cloudflare_media_url in php-api/endpoints/posts.php. If
  /// Cloudflare ever reissues the account hash, every URL already stored
  /// in Supabase breaks and this constant is not enough to fix them —
  /// see the note on [uploadAndGetUrl].
  static const _delivery =
      'https://imagedelivery.net'
      '/3UkXrQaSXZJl7XH5FuIHDg';

  /// The variant group avatars are stored at.
  ///
  /// 'thumbnail' is 400x400 — a SQUARE, which crops anything that is not
  /// already one. For an avatar that is exactly right: it is drawn in a
  /// circle at 56 points, so a square source is what it wants.
  ///
  /// It is wrong for anything else, which is what [photo] is for.
  static const _variant = 'thumbnail';

  /// The variant photographs are stored at.
  ///
  /// 'public' keeps the aspect ratio. Measured rather than assumed: the
  /// same source image comes back 400x400 through 'thumbnail' and at
  /// its own 399x332 through this one.
  ///
  /// Chat photographs were going up as 'thumbnail', so a portrait
  /// picture arrived in the thread already square — nothing in the UI
  /// was cropping it, the stored image WAS the crop.
  static const photo = 'public';

  /// Rewrite a stored delivery URL to a different variant.
  ///
  /// Every chat photograph sent before [photo] existed has a
  /// /thumbnail URL written into its Supabase row, and those rows
  /// cannot be rebuilt from here — see the note on [uploadAndGetUrl].
  /// The variant is the last path segment though, so an old URL can be
  /// pointed at the uncropped rendition of the SAME upload as it is
  /// displayed. Cloudflare still holds the original; only the
  /// rendition asked for was square.
  ///
  /// Anything that is not one of this account's delivery URLs is
  /// returned untouched.
  static String? asVariant(String? url, String variant) {
    if (url == null || url.isEmpty) return url;
    if (!url.startsWith(_delivery)) return url;

    final cut = url.lastIndexOf('/');
    if (cut <= _delivery.length) return url;

    return '${url.substring(0, cut)}/$variant';
  }

  /// The delivery URL for an image id.
  static String urlFor(String imageId, {String variant = _variant}) =>
      '$_delivery/$imageId/$variant';

  /// Upload [bytes] and return a URL that can be stored anywhere.
  ///
  /// Two steps, as everywhere else in the app: WordPress mints a
  /// one-time direct-upload URL, then the bytes go straight to
  /// Cloudflare without passing through the server.
  ///
  /// A NOTE ON STORING THE URL RATHER THAN THE ID. Everything else in
  /// this codebase stores the bare id and builds the URL at render time,
  /// which means the variant and the account hash can both be changed
  /// later in one place. A stored URL cannot: it fixes the variant at
  /// upload time, so moving group avatars to a larger one would mean a
  /// migration over the rows. That is the deliberate trade for a
  /// Supabase table that has no way to call the PHP helper, and at this
  /// size the variant is unlikely to want changing.
  ///
  /// Returns null if the upload fails.
  static Future<String?> uploadAndGetUrl({
    required Uint8List bytes,
    required String fileName,
    String variant = _variant,
  }) async {
    final id = await uploadAndGetId(bytes: bytes, fileName: fileName);
    return id == null ? null : urlFor(id, variant: variant);
  }

  /// Upload [bytes] and return the Cloudflare image id.
  ///
  /// What most of this codebase wants: the id is stored and the URL is
  /// built at render time, so the variant stays a decision. Only callers
  /// writing into somewhere that cannot build a URL — a Supabase row —
  /// want [uploadAndGetUrl].
  ///
  /// Returns null if the upload fails.
  static Future<String?> uploadAndGetId({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final ticket = await http.post(
        Uri.parse(
          '${AppEnvironment.wordpressBase}/wp-json/app/v2/create-image-upload',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (ticket.statusCode != 200) {
        debugPrint('[CF] upload URL failed: ${ticket.statusCode}');
        return null;
      }

      final uploadUrl = jsonDecode(ticket.body)['upload_url'];
      if (uploadUrl == null) return null;

      final request = http.MultipartRequest('POST', Uri.parse('$uploadUrl'))
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        );

      final response = await http.Response.fromStream(await request.send());

      if (response.statusCode != 200) {
        debugPrint('[CF] upload failed: ${response.statusCode}');
        return null;
      }

      final id = jsonDecode(response.body)['result']?['id']?.toString();

      // The quiet failure this is here for: a 200 from Cloudflare whose
      // body is not the shape expected leaves the image uploaded and
      // the caller holding null — which looks from the outside like an
      // upload that never happened.
      if (id == null || id.isEmpty) {
        debugPrint('[CF] uploaded, but no id in: ${response.body}');
        return null;
      }

      debugPrint('[CF] uploaded id=$id');
      return id;
    } catch (e) {
      debugPrint('[CF] upload threw: $e');
      return null;
    }
  }
}
