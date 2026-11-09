import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// The GIF picker, shared by comments and chat.
///
/// Lifted out of comments_bottom_sheet.dart, where it was private, so
/// the two places that offer a GIF offer the SAME one. A second copy
/// would be a second API key, a second set of wording and two things to
/// fix whenever the provider changes.
///
/// ── IT IS KLIPY, NOT TENOR ───────────────────────────────────────────
///
/// The classes were called _TenorGif and _TenorGifPicker and the API is
/// api.klipy.com. The names are corrected here rather than carried
/// over; nothing outside this file ever referred to them.
///
/// ── WHAT IT RETURNS ──────────────────────────────────────────────────
///
/// A [GifPick] holding the provider's own URLs. Nothing is uploaded and
/// nothing is stored on our side: the URL IS the content, which is why
/// a GIF can be sent without touching Cloudflare at all.

class GifPick {
  final String id;
  final String url; // full-size for sending
  final String previewUrl; // smaller for thumbnails

  GifPick({required this.id, required this.url, required this.previewUrl});
}

class GifPicker extends StatefulWidget {
  const GifPicker();

  @override
  State<GifPicker> createState() => GifPickerState();
}

class GifPickerState extends State<GifPicker> {
  // Paste your KLIPY test key here — get one at https://klipy.com
  static const String _apiKey =
      '7UrnPvKjU6BCzy0guMtedUGtouNAHnbQvbjjou1S6ckPTVjvIJcF2UmLwhCVADvN';

  // KLIPY uses customer_id to track per-user recents/preferences.
  // For now use a stable anonymous value; later swap for the actual user ID.
  static const String _customerId = 'drivelife-anonymous';

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<GifPick> _gifs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        'https://api.klipy.com/api/v1/$_apiKey/gifs/trending'
        '?customer_id=$_customerId&page=1&per_page=24',
      );
      final response = await http.get(uri);
      _handleResponse(response);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load GIFs';
        });
      }
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      _loadTrending();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        'https://api.klipy.com/api/v1/$_apiKey/gifs/search'
        '?q=${Uri.encodeQueryComponent(query)}'
        '&customer_id=$_customerId&page=1&per_page=24',
      );
      final response = await http.get(uri);
      _handleResponse(response);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Search failed';
        });
      }
    }
  }

  void _handleResponse(http.Response response) {
    if (!mounted) return;

    if (response.statusCode != 200) {
      setState(() {
        _loading = false;
        _error = response.statusCode == 429
            ? 'Hit rate limit — try again in a moment'
            : 'API error (${response.statusCode})';
      });
      return;
    }

    final body = json.decode(response.body) as Map<String, dynamic>;

    // KLIPY shape: { result: true, data: { data: [...], current_page, ... } }
    final outerData = body['data'] as Map<String, dynamic>?;
    final results = (outerData?['data'] as List?) ?? [];

    final gifs = results
        .map((item) {
          final m = item as Map<String, dynamic>;
          final file = m['file'] as Map<String, dynamic>? ?? {};

          // Try to pull the largest gif URL for sending, smallest for preview
          String? extractUrl(String size) {
            final sized = file[size] as Map<String, dynamic>?;
            if (sized == null) return null;
            // KLIPY returns format-keyed map: { gif: {url}, mp4: {url}, webp: {url} }
            return sized['gif']?['url']?.toString();
          }

          final fullUrl =
              extractUrl('lg') ??
              extractUrl('md') ??
              extractUrl('sm') ??
              extractUrl('xs') ??
              '';
          final previewUrl =
              extractUrl('sm') ??
              extractUrl('xs') ??
              extractUrl('md') ??
              fullUrl;

          return GifPick(
            id: m['slug']?.toString() ?? m['id']?.toString() ?? '',
            url: fullUrl,
            previewUrl: previewUrl,
          );
        })
        .where((g) => g.url.isNotEmpty)
        .toList();

    setState(() {
      _gifs = gifs;
      _loading = false;
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    // KLIPY's attribution guideline: use "Search KLIPY"
                    hintText: 'Search KLIPY',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _loadTrending();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Color(0xFFAE9159)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFAE9159),
                        ),
                      )
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _gifs.isEmpty
                    ? Center(
                        child: Text(
                          'No GIFs found',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 1,
                            ),
                        itemCount: _gifs.length,
                        itemBuilder: (context, i) {
                          final gif = _gifs[i];
                          return GestureDetector(
                            onTap: () => Navigator.pop(context, gif),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                color: Colors.grey.shade200,
                                child: Image.network(
                                  gif.previewUrl,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    );
                                  },
                                  errorBuilder: (_, _, _) => Container(
                                    color: const Color(0xFFF0F0F0),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.grey.shade400,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // KLIPY attribution (their TOS requires this)
              Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 4,
                  top: 4,
                ),
                child: Text(
                  'Powered by KLIPY',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
