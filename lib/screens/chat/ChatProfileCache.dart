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
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatList.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _baseUrl = 'https://www.carevents.com/uk'; // ← update

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

// ── Updated _ConversationTile ─────────────────────────────────
// Pass wordpressJwt in and use UserProfileCache instead of
// resolveUserName callback.

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

    // Serve from cache immediately if available
    final cached = UserProfileCache.instance.getCached(otherId);
    if (cached != null) {
      if (mounted) setState(() => _profile = cached);
      return;
    }

    // Otherwise fetch
    final results = await UserProfileCache.instance.resolve([
      otherId,
    ]);
    if (mounted) setState(() => _profile = results[otherId]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    final preview = widget.preview;
    final lastMsg = preview.lastMessage;
    final hasUnread = preview.unreadCount > 0;
    final scheme = Theme.of(context).colorScheme;
    final name = _profile?.bestName ?? '...';
    final imageUrl = _profile?.imageUrl;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),

      leading: CircleAvatar(
        radius: 22,
        backgroundColor: theme.primaryColor.withOpacity(0.1),
        backgroundImage: imageUrl != null && imageUrl.isNotEmpty
            ? NetworkImage(imageUrl)
            : null,
        child: imageUrl == null || imageUrl.isEmpty
            ? Text(
                name != '...' ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              )
            : null,
      ),

      title: Text(
        name,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),

      subtitle: lastMsg != null
          ? Text(
              lastMsg.senderId == widget.myUserId
                  ? 'You: ${lastMsg.content}'
                  : lastMsg.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                color: hasUnread ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            )
          : const Text(
              'No messages yet',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),

      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (lastMsg != null)
            Text(
              _formatTime(lastMsg.createdAt),
              style: TextStyle(
                fontSize: 11,
                color: hasUnread ? theme.primaryColor : scheme.onSurfaceVariant,
              ),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                preview.unreadCount > 99 ? '99+' : '${preview.unreadCount}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),

      onTap: widget.onTap,
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}';
  }
}

// ── Usage ─────────────────────────────────────────────────────
//
// 1. In main(), before runApp():
//    await UserProfileCache.instance.loadFromDisk();
//
// 2. Replace _ConversationTile with CachedConversationTile:
//    CachedConversationTile(
//      preview:      preview,
//      myUserId:     widget.myUserId,
//      wordpressJwt: widget.wordpressJwt,  // pass your WP JWT down
//      onTap:        () => _openChat(...),
//    )
//
// 3. On inbox refresh, pre-warm the cache for all visible users:
//    final ids = _notifier.previews.map((p) => p.otherUserId).toList();
//    await UserProfileCache.instance.refresh(ids, wordpressJwt);
//
// 4. On logout:
//    await UserProfileCache.instance.clear();
