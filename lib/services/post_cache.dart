class PostCache {
  // Singleton pattern
  static final PostCache _instance = PostCache._internal();
  factory PostCache() => _instance;
  PostCache._internal();

  // Cache storage: postId -> {data, timestamp}
  final Map<String, _CacheEntry> _cache = {};

  // Cache duration: 10 minutes
  static const Duration _cacheDuration = Duration(minutes: 10);

  /// Get post from cache if valid, null if expired/missing
  Map<String, dynamic>? get(String postId) {
    final entry = _cache[postId];

    if (entry == null) {
      return null; // Not cached
    }

    // Check if expired
    if (DateTime.now().difference(entry.timestamp) > _cacheDuration) {
      _cache.remove(postId); // Remove expired entry
      print('🗑️ Cache expired for post $postId');
      return null;
    }

    print('✅ Cache hit for post $postId');
    return entry.data;
  }

  /// Store post in cache with current timestamp
  void set(String postId, Map<String, dynamic> data) {
    _cache[postId] = _CacheEntry(data: data, timestamp: DateTime.now());
    print('💾 Cached post $postId');
  }

  /// Remove specific post from cache
  void invalidate(String postId) {
    _cache.remove(postId);
    print('🗑️ Invalidated cache for post $postId');
  }

  /// Clear all cached posts
  void clearAll() {
    _cache.clear();
    print('🗑️ Cleared all post cache');
  }

  /// Get cache stats
  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    int validCount = 0;
    int expiredCount = 0;

    for (final entry in _cache.values) {
      if (now.difference(entry.timestamp) <= _cacheDuration) {
        validCount++;
      } else {
        expiredCount++;
      }
    }

    return {
      'total': _cache.length,
      'valid': validCount,
      'expired': expiredCount,
      'cache_duration_minutes': _cacheDuration.inMinutes,
    };
  }
}

class _CacheEntry {
  final Map<String, dynamic> data;
  final DateTime timestamp;

  _CacheEntry({required this.data, required this.timestamp});
}
