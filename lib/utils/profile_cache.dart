/// Optimized profile cache with LRU eviction and time-based expiration
class ProfileCache {
  static const int _maxCacheSize = 50; // Max 50 profiles
  static const Duration _cacheExpiration = Duration(minutes: 5);

  static final Map<int, _CachedProfile> _cache = {};
  static final List<int> _accessOrder = []; // For LRU tracking

  /// Get profile from cache (null if expired or not found)
  static Map<String, dynamic>? get(int userId) {
    final cached = _cache[userId];

    if (cached == null) return null;

    // Check if expired
    if (DateTime.now().difference(cached.timestamp) > _cacheExpiration) {
      _cache.remove(userId);
      _accessOrder.remove(userId);
      print('🕐 [ProfileCache] Profile $userId expired, removed');
      return null;
    }

    // Update access order (move to end = most recently used)
    _accessOrder.remove(userId);
    _accessOrder.add(userId);

    print('✅ [ProfileCache] Cache hit for user $userId');
    return cached.data;
  }

  /// Put profile in cache
  static void put(int userId, Map<String, dynamic> data) {
    // Remove oldest if cache is full
    if (_cache.length >= _maxCacheSize && !_cache.containsKey(userId)) {
      final oldestUserId = _accessOrder.first;
      _cache.remove(oldestUserId);
      _accessOrder.removeAt(0);
      print('🗑️ [ProfileCache] Evicted user $oldestUserId (LRU)');
    }

    _cache[userId] = _CachedProfile(data);
    _accessOrder.remove(userId); // Remove if exists
    _accessOrder.add(userId); // Add to end

    print(
      '💾 [ProfileCache] Cached user $userId (${_cache.length}/$_maxCacheSize)',
    );
  }

  /// Remove specific profile from cache
  static void remove(int userId) {
    _cache.remove(userId);
    _accessOrder.remove(userId);
    print('🗑️ [ProfileCache] Removed user $userId from cache');
  }

  /// Clear all cache
  static void clearAll() {
    _cache.clear();
    _accessOrder.clear();
    print('🗑️ [ProfileCache] Cleared all cache');
  }

  /// Get cache stats
  static Map<String, dynamic> getStats() {
    return {
      'size': _cache.length,
      'max_size': _maxCacheSize,
      'cached_users': _cache.keys.toList(),
    };
  }
}

class _CachedProfile {
  final Map<String, dynamic> data;
  final DateTime timestamp;

  _CachedProfile(this.data) : timestamp = DateTime.now();
}
