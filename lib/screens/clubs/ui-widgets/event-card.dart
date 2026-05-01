import 'package:flutter/material.dart';

const Color _gold = Color(0xFFC4A062);
const Color _ink = Color(0xFF0B0B0B);
const Color _muted = Color(0xFF8A8A8A);
const Color _panelBg = Color(0xFFF7F7F7);

class EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback onTap;
  const EventCard({super.key, required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final coverImage = event['cover_image'];
    final title = (event['name'] ?? '') as String;
    final startDate = (event['start_date'] ?? '') as String;
    final location = (event['location'] ?? 'TBA') as String;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _panelBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: coverImage != null
                  ? Image.network(
                      coverImage,
                      width: 78,
                      height: 78,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _eventPlaceholder(),
                    )
                  : _eventPlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (startDate.isNotEmpty)
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: _gold,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatEventDate(startDate),
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 12,
                        color: _gold,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: const BorderSide(color: _gold, width: 1.2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                minimumSize: const Size(0, 32),
              ),
              child: const Text(
                'View',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventPlaceholder() {
    return Container(
      width: 78,
      height: 78,
      color: Colors.grey.shade200,
      child: Icon(Icons.event, color: Colors.grey.shade400, size: 28),
    );
  }

  String _formatEventDate(String date) {
    try {
      final parts = date.split(' ');
      if (parts.isEmpty) return date;
      final dateParts = parts[0].split('/');
      if (dateParts.length != 3) return date;
      final month = int.parse(dateParts[0]);
      final day = int.parse(dateParts[1]);
      final year = int.parse(dateParts[2]);
      const monthNames = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${monthNames[month]} $day, $year';
    } catch (e) {
      return date;
    }
  }
}
