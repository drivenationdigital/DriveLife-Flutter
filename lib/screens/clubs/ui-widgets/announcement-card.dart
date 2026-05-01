import 'package:flutter/material.dart';

const Color _gold = Color(0xFFC4A062);
const Color _ink = Color(0xFF0B0B0B);
const Color _muted = Color(0xFF8A8A8A);

class AnnouncementCard extends StatelessWidget {
  final String authorName;
  final String posted;
  final String content;
  final String? logoUrl;

  const AnnouncementCard({
    super.key,
    required this.authorName,
    required this.posted,
    required this.content,
    this.logoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: _ink,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: logoUrl != null
                      ? Image.network(
                          logoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _logoFallback(),
                        )
                      : _logoFallback(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 14, color: _gold),
                        ],
                      ),
                      if (posted.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          posted,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              content,
              style: const TextStyle(color: _ink, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoFallback() => Container(
    color: _ink,
    alignment: Alignment.center,
    child: const Text(
      '⫽',
      style: TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.w900),
    ),
  );
}
