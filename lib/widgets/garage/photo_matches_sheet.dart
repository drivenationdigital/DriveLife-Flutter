import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/garage_api.dart';
import 'package:flutter/material.dart';

/// "We found 12 photos of your car."
///
/// Shown after a vehicle is added. The scan records every plate it reads
/// whether or not a garage matched at the time, so by the time somebody adds
/// their car the site often already knows about photos of it — and nothing
/// ever looked back for them.
///
/// Opens only when there is something to say: [show] does the lookup first and
/// returns without a sheet when the count is zero, so adding a car nobody has
/// photographed is silent rather than a disappointment.
class PhotoMatchesSheet extends StatefulWidget {
  final int garageId;
  final String registration;
  final List<Map<String, dynamic>> photos;

  const PhotoMatchesSheet({
    super.key,
    required this.garageId,
    required this.registration,
    required this.photos,
  });

  /// Looks for matches and shows the sheet if there are any.
  static Future<void> show(BuildContext context, int garageId) async {
    final result = await GarageAPI.fetchPhotoMatches(garageId: garageId);
    if (!context.mounted) return;

    final total = int.tryParse('${result['total']}') ?? 0;
    if (total <= 0) return;

    final photos = (result['photos'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PhotoMatchesSheet(
        garageId: garageId,
        registration: '${result['registration'] ?? ''}',
        photos: photos,
      ),
    );
  }

  @override
  State<PhotoMatchesSheet> createState() => _PhotoMatchesSheetState();
}

class _PhotoMatchesSheetState extends State<PhotoMatchesSheet> {
  static const Color _ink = Color(0xFF0B0B0B);
  static const Color _muted = Color(0xFF8A8A8A);
  static const Color _gold = Color(0xFFAE9159);

  bool _claiming = false;

  Future<void> _claim() async {
    setState(() => _claiming = true);

    try {
      final claimed = await GarageAPI.claimPhotoMatches(
        garageId: widget.garageId,
      );

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$claimed photo${claimed == 1 ? '' : 's'} added to your vehicle',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _claiming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.photos.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text(
              'We found $count photo${count == 1 ? '' : 's'} of your car',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              // "Galleries" was true when only galleries were searched. Posts
              // are where most photos of most cars actually are.
              widget.registration.isEmpty
                  ? 'Spotted in posts and galleries other members have '
                        'uploaded.'
                  : '${widget.registration} was spotted in posts and galleries '
                        'other members have uploaded.',
              style: const TextStyle(fontSize: 14, color: _muted, height: 1.45),
            ),
            const SizedBox(height: 18),

            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final thumb = '${widget.photos[index]['thumb'] ?? ''}';

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: thumb.isEmpty
                          ? ColoredBox(color: Colors.grey.shade200)
                          : CachedNetworkImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              placeholder: (_, _) =>
                                  ColoredBox(color: Colors.grey.shade200),
                              errorWidget: (_, _, _) =>
                                  ColoredBox(color: Colors.grey.shade200),
                            ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _claiming ? null : _claim,
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: _claiming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Add them to my vehicle',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),

            Center(
              child: TextButton(
                onPressed: _claiming ? null : () => Navigator.pop(context),
                child: const Text(
                  'Not now',
                  style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
