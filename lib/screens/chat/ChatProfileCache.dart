// ============================================================
// USER PROFILE CACHE
// ============================================================
// Resolves WP user IDs → display name + avatar.
// - Batches multiple IDs into a single API call
// - Caches in memory for the app session
// - Persists to SharedPreferences across restarts
// - Only re-fetches on explicit refresh() call
// ============================================================

import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatList.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivelife/config/app_environment.dart';

// ── Model ─────────────────────────────────────────────────────

class UserProfile {
  final String id;
  final String username;
  final String displayName;
  final String firstName;
  final String lastName;
  final String? imageUrl;

  UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.firstName,
    required this.lastName,
    this.imageUrl,
  });

  /// Best available name — full name if set, otherwise display name
  String get bestName {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : displayName;
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      username: map['username'] as String? ?? '',
      displayName: map['display_name'] as String? ?? '',
      firstName: map['first_name'] as String? ?? '',
      lastName: map['last_name'] as String? ?? '',
      imageUrl: map['image'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'first_name': firstName,
    'last_name': lastName,
    'image': imageUrl,
  };
}

// ── Cache Service (Singleton) ─────────────────────────────────

class UserProfileCache {
  UserProfileCache._();
  static final UserProfileCache instance = UserProfileCache._();
  static final AuthService _authService = AuthService();

  static const _prefKey = 'user_profile_cache';
  static String get _baseUrl => AppEnvironment.wordpressBase;

  // In-memory cache: userId → UserProfile
  final Map<String, UserProfile> _cache = {};
  bool _loaded = false;

  // ── Setup ──

  /// Call once at app start to restore persisted cache.
  Future<void> loadFromDisk() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) {
        final Map<String, dynamic> data = json.decode(raw);
        data.forEach((id, val) {
          _cache[id] = UserProfile.fromMap(Map<String, dynamic>.from(val));
        });
      }
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _cache.map((id, p) => MapEntry(id, p.toMap()));
      await prefs.setString(_prefKey, json.encode(data));
    } catch (_) {}
  }

  // ── Resolve ──

  /// Get a single profile. Returns null if not cached yet.
  UserProfile? getCached(String userId) => _cache[userId];

  /// Resolve a list of user IDs.
  /// - Returns cached profiles immediately for known IDs
  /// - Fetches unknown IDs from the API in one batch call
  Future<Map<String, UserProfile>> resolve(
    List<String> userIds, {
    bool forceRefresh = false,
  }) async {
    if (userIds.isEmpty) return {};

    final needed = forceRefresh
        ? userIds
        : userIds.where((id) => !_cache.containsKey(id)).toList();

    if (needed.isNotEmpty) {
      final token = await _authService.getToken();
      if (token == null) {
        return {
          for (final id in userIds)
            if (_cache.containsKey(id)) id: _cache[id]!,
        };
      }

      await _fetchBatch(needed, token);
    }

    return {
      for (final id in userIds)
        if (_cache.containsKey(id)) id: _cache[id]!,
    };
  }

  /// Force re-fetch specific IDs (call on inbox refresh).
  Future<void> refresh(List<String> userIds) async {
    final token = await _authService.getToken();
    if (token == null) {
      return;
    }

    await _fetchBatch(userIds, token);
  }

  /// Clear everything (call on logout).
  Future<void> clear() async {
    _cache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  // ── Internal ──

  Future<void> _fetchBatch(List<String> ids, String jwt) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/wp-json/myapp/v1/users/resolve'),
        headers: {
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
        },
        body: json.encode({'ids': ids}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        data.forEach((id, val) {
          _cache[id] = UserProfile.fromMap(Map<String, dynamic>.from(val));
        });
        await _saveToDisk();
      }
    } catch (e) {
      debugPrint('[UserProfileCache] Fetch error: $e');
    }
  }
}

// ── Avatar Widget ─────────────────────────────────────────────
// Drop-in replacement for CircleAvatar that resolves from cache.

class UserAvatar extends StatelessWidget {
  final String userId;
  final String wordpressJwt;
  final double radius;

  const UserAvatar({
    super.key,
    required this.userId,
    required this.wordpressJwt,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final cached = UserProfileCache.instance.getCached(userId);

    if (cached == null) {
      // Trigger a fetch and show placeholder
      UserProfileCache.instance.resolve([userId]);
      return _placeholder(context, null);
    }

    return _avatar(context, cached);
  }

  Widget _avatar(BuildContext context, UserProfile profile) {
    final scheme = Theme.of(context).colorScheme;
    final url = profile.imageUrl;

    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
      child: url == null || url.isEmpty
          ? Text(
              profile.bestName.isNotEmpty
                  ? profile.bestName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.7,
                color: scheme.onPrimaryContainer,
              ),
            )
          : null,
    );
  }

  Widget _placeholder(BuildContext context, _) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.surfaceContainerHighest,
      child: Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant),
    );
  }
}

class CachedConversationTile extends StatefulWidget {
  final ConversationPreview preview;
  final String myUserId;
  final VoidCallback onTap;

  const CachedConversationTile({
    super.key,
    required this.preview,
    required this.myUserId,
    required this.onTap,
  });

  @override
  State<CachedConversationTile> createState() => _CachedConversationTileState();
}

class _CachedConversationTileState extends State<CachedConversationTile> {
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final otherId = widget.preview.otherUserId;
    if (otherId == null) return; // ← guard for group chats

    // Serve from cache immediately if available
    final cached = UserProfileCache.instance.getCached(otherId);
    if (cached != null) {
      if (mounted) setState(() => _profile = cached);
      return;
    }

    // Otherwise fetch
    final results = await UserProfileCache.instance.resolve([otherId]);
    if (mounted) setState(() => _profile = results[otherId]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    final preview = widget.preview;
    final lastMsg = preview.lastMessage;
    final hasUnread = preview.unreadCount > 0;
    final isGroup = preview.isGroup;

    final name = isGroup
        ? (preview.conversation.groupName ?? 'Group')
        : (_profile?.bestName ?? '…');

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              _avatar(theme, name, isGroup),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.25,
                        fontWeight: hasUnread
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: const Color(0xFF111111),
                      ),
                    ),
                    const SizedBox(height: 2),
                    _subtitle(lastMsg, hasUnread),
                  ],
                ),
              ),

              // The unread mark. A dot, not a number: the count that
              // matters is the total, and that is on the Messages tab.
              if (hasUnread) ...[
                const SizedBox(width: 12),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "Nice one · 2h" — the preview and the time on one line.
  ///
  /// One line rather than a right-hand column, so a long message gets the
  /// width instead of reserving space for a timestamp that is four
  /// characters at most.
  Widget _subtitle(ChatMessage? lastMsg, bool hasUnread) {
    final style = TextStyle(
      fontSize: 13,
      height: 1.3,
      fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
      color: hasUnread ? const Color(0xFF111111) : Colors.grey.shade500,
    );

    if (lastMsg == null) {
      return Text(
        'No messages yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: Colors.grey.shade400),
      );
    }

    final mine = lastMsg.senderId == widget.myUserId;

    return Row(
      children: [
        Flexible(
          child: Text(
            mine ? 'You: ${lastMsg.content}' : lastMsg.content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        Text(
          '  ·  ${_relativeTime(lastMsg.createdAt)}',
          // Never bold, never black. The time is reference, not content,
          // and letting it go bold with the rest made every unread row
          // shout twice.
          style: style.copyWith(
            fontWeight: FontWeight.w400,
            color: Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  Widget _avatar(ThemeProvider theme, String name, bool isGroup) {
    final imageUrl = isGroup ? null : _profile?.imageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    final initial = name.isNotEmpty && name != '…'
        ? name.characters.first.toUpperCase()
        : '?';

    return ClipOval(
      child: SizedBox(
        width: 56,
        height: 56,
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                // Decoded at the size it is drawn, not the source's.
                memCacheWidth: (56 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                placeholder: (_, __) => ColoredBox(color: Colors.grey.shade100),
                errorWidget: (_, __, ___) =>
                    _initialAvatar(theme, initial, isGroup),
              )
            : _initialAvatar(theme, initial, isGroup),
      ),
    );
  }

  Widget _initialAvatar(ThemeProvider theme, String initial, bool isGroup) {
    return ColoredBox(
      color: const Color(0xFFEFEFEF),
      child: Center(
        child: isGroup
            ? Icon(Icons.group_rounded, size: 24, color: Colors.grey.shade600)
            : Text(
                initial,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
      ),
    );
  }

  /// How long ago, the way a messaging app says it.
  ///
  /// A clock time is only useful for today; after that the day, and after
  /// a week the date. "09:14" on something from March says nothing.
  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24 && now.day == dt.day) return '${diff.inHours}h';

    final startOfToday = DateTime(now.year, now.month, now.day);
    final daysBack = startOfToday
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;

    if (daysBack == 1) return '1d';
    if (daysBack < 7) return '${daysBack}d';
    if (daysBack < 365) return '${(daysBack / 7).floor()}w';

    return '${(daysBack / 365).floor()}y';
  }
}
