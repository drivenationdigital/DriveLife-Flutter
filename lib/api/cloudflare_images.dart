import 'dart:convert';
import 'dart:typed_data';

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
  static const _delivery = 'https://imagedelivery.net'
      '/3UkXrQaSXZJl7XH5FuIHDg';

  /// The variant group avatars are stored at.
  ///
  /// 'thumbnail' is 400px on its longest side. The avatar is drawn at 56
  /// points, so 168 physical pixels on a 3x phone — 400 is comfortable
  /// and it is the smallest variant that is.
  static const _variant = 'thumbnail';

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
      if (id == null || id.isEmpty) return null;

      return urlFor(id);
    } catch (e) {
      debugPrint('[CF] upload threw: $e');
      return null;
    }
  }
}
