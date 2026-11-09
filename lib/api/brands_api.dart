import 'dart:convert';

import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One marque somebody can say they are into.
class Brand {
  final int id;
  final String name;
  final String slug;

  /// The group's logo, or null — then the chip draws an initial.
  final String? logo;

  const Brand({
    required this.id,
    required this.name,
    required this.slug,
    this.logo,
  });

  factory Brand.fromMap(Map<String, dynamic> map) => Brand(
    id: int.tryParse('${map['id']}') ?? 0,
    name: '${map['name'] ?? ''}'.trim(),
    slug: '${map['slug'] ?? ''}'.trim(),
    logo: (map['logo']?.toString().trim().isNotEmpty ?? false)
        ? map['logo'].toString()
        : null,
  );
}

/// The list, plus this person's answer to it.
class BrandOptions {
  final List<Brand> brands;
  final Set<int> selected;

  /// Whether they have ever been asked.
  ///
  /// Separate from [selected] being empty, which is ambiguous: somebody
  /// who looked and picked none has answered, and must not be asked
  /// again.
  final bool answered;

  const BrandOptions({
    required this.brands,
    required this.selected,
    required this.answered,
  });

  static const empty = BrandOptions(
    brands: <Brand>[],
    selected: <int>{},
    answered: true,
  );
}

/// The marques somebody follows.
///
/// Backed by the curated marque global groups rather than a list of its
/// own — see the note in php-api/endpoints/interests.php. Adding a
/// marque in the groups admin adds it here.
class BrandsAPI {
  static final AuthService _auth = AuthService();

  static String get _base => '${AppEnvironment.wordpressBase}/wp-json/app/v2';

  static Future<Map<String, String>?> _headers() async {
    final token = await _auth.getToken();
    if (token == null) return null;

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// The pickable brands and the caller's current answer, in one call.
  ///
  /// Returns [BrandOptions.empty] on any failure, whose `answered` is
  /// TRUE — so a server that cannot be reached never triggers the
  /// prompt. Being asked to pick brands because the network blipped is
  /// worse than not being asked.
  static Future<BrandOptions> load() async {
    try {
      final headers = await _headers();
      if (headers == null) return BrandOptions.empty;

      final response = await http.get(
        Uri.parse('$_base/interests/brands'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        debugPrint('[Brands] load failed: ${response.statusCode}');
        return BrandOptions.empty;
      }

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) return BrandOptions.empty;

      final rows = (body['brands'] as List<dynamic>?) ?? const [];

      return BrandOptions(
        brands: rows
            .whereType<Map<String, dynamic>>()
            .map(Brand.fromMap)
            .where((b) => b.id > 0 && b.name.isNotEmpty)
            .toList(),
        selected: ((body['selected'] as List<dynamic>?) ?? const [])
            .map((v) => int.tryParse('$v') ?? 0)
            .where((v) => v > 0)
            .toSet(),
        answered: body['answered'] == true,
      );
    } catch (e) {
      debugPrint('[Brands] load threw: $e');
      return BrandOptions.empty;
    }
  }

  /// Replace this person's chosen brands.
  ///
  /// A replace, not a merge — unticking has to stick. Returns false on
  /// any failure so the caller can keep the sheet open rather than
  /// claim a save that did not happen.
  ///
  /// An empty list is a valid answer and is sent as one: it records
  /// that they were asked.
  static Future<bool> save(Set<int> ids) async {
    try {
      final headers = await _headers();
      if (headers == null) return false;

      final response = await http.post(
        Uri.parse('$_base/interests/brands'),
        headers: headers,
        body: jsonEncode({'brands': ids.toList()}),
      );

      if (response.statusCode != 200) {
        debugPrint('[Brands] save failed: ${response.statusCode}');
        return false;
      }

      final body = jsonDecode(response.body);

      return body is Map && body['success'] == true;
    } catch (e) {
      debugPrint('[Brands] save threw: $e');
      return false;
    }
  }
}
