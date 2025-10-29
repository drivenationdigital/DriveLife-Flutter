import 'dart:convert';
import 'package:http/http.dart' as http;

class ReelsAPI {
  static const String _baseUrl = "https://www.carevents.com/uk";

  static Future<List<Map<String, dynamic>>> getReels({
    required int userId,
    int page = 1,
    int limit = 20,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/wp-json/app/v2/get-posts?user_id=$userId&following_only=0&page=$page&limit=$limit',
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) return [];

    final json = jsonDecode(response.body);
    final posts = (json["data"] as List).cast<Map<String, dynamic>>();

    // Keep only posts where at least 1 media item is a video
    final reels = posts.toList();
    return reels;
  }
}
