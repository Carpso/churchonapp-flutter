import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Offline caching service for Church On App
/// Critical for Zambian internet conditions where connectivity is intermittent
class OfflineCacheService {
  static const String _prefix = 'offline_cache_';
  final Connectivity _connectivity = Connectivity();

  OfflineCacheService();

  /// Cache data locally for offline access
  Future<void> cacheData(String key, dynamic data, {Duration? ttl}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheEntry = {
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'ttl': ttl?.inMilliseconds ?? const Duration(hours: 1).inMilliseconds,
    };
    await prefs.setString('$_prefix$key', jsonEncode(cacheEntry));
  }

  /// Get cached data, returns null if expired or not found
  Future<T?> getCachedData<T>(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('$_prefix$key');
    if (cached == null) return null;

    try {
      final entry = jsonDecode(cached) as Map<String, dynamic>;
      final timestamp = entry['timestamp'] as int;
      final ttl = entry['ttl'] as int;

      if (DateTime.now().millisecondsSinceEpoch - timestamp > ttl) {
        // Cache expired
        await prefs.remove('$_prefix$key');
        return null;
      }

      return entry['data'] as T;
    } catch (e) {
      debugPrint('Cache read error for $key: $e');
      return null;
    }
  }

  /// Clear all cached data
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Clear expired cache entries
  Future<void> clearExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));

    for (final key in keys) {
      final cached = prefs.getString(key);
      if (cached == null) continue;

      try {
        final entry = jsonDecode(cached) as Map<String, dynamic>;
        final timestamp = entry['timestamp'] as int;
        final ttl = entry['ttl'] as int;

        if (DateTime.now().millisecondsSinceEpoch - timestamp > ttl) {
          await prefs.remove(key);
        }
      } catch (e) {
        await prefs.remove(key);
      }
    }
  }

  /// Get cache size in bytes
  Future<int> getCacheSize() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    int totalSize = 0;

    for (final key in keys) {
      final cached = prefs.getString(key);
      if (cached != null) {
        totalSize += cached.length * 2; // UTF-16 encoding
      }
    }

    return totalSize;
  }

  /// Check if device is online
  Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }

  /// Stream connection status
  Stream<bool> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged.map((result) {
      return result.any((r) => r != ConnectivityResult.none);
    });
  }
}

/// Offline-aware data fetcher
/// Tries network first, falls back to cache
class OfflineDataFetcher {
  final OfflineCacheService _cache;

  OfflineDataFetcher(this._cache);

  /// Fetch data with offline fallback
  Future<T?> fetchWithCache<T>(
    String key,
    Future<T> Function() networkFetcher, {
    Duration cacheTtl = const Duration(hours: 1),
    bool forceRefresh = false,
  }) async {
    // Try network first if online
    if (!forceRefresh && await _cache.isOnline()) {
      try {
        final data = await networkFetcher();
        await _cache.cacheData(key, data, ttl: cacheTtl);
        return data;
      } catch (e) {
        debugPrint('Network fetch failed for $key: $e');
        // Fall through to cache
      }
    }

    // Try cache
    final cached = await _cache.getCachedData<T>(key);
    if (cached != null) {
      return cached;
    }

    // Last resort: try network even if offline (might be intermittent)
    try {
      final data = await networkFetcher();
      await _cache.cacheData(key, data, ttl: cacheTtl);
      return data;
    } catch (e) {
      debugPrint('Final network attempt failed for $key: $e');
      return null;
    }
  }
}

/// Critical data to cache for offline access
class CriticalDataCache {
  final OfflineCacheService _cache;
  final SupabaseClient _client;

  CriticalDataCache(this._cache, this._client);

  /// Cache user profile
  Future<void> cacheUserProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      await _cache.cacheData('user_profile', profile, ttl: const Duration(hours: 24));
    } catch (e) {
      debugPrint('Failed to cache user profile: $e');
    }
  }

  /// Cache church data
  Future<void> cacheChurchData(String tenantId) async {
    try {
      final church = await _client
          .from('churches')
          .select()
          .eq('id', tenantId)
          .single();

      await _cache.cacheData('church_$tenantId', church, ttl: const Duration(hours: 12));
    } catch (e) {
      debugPrint('Failed to cache church data: $e');
    }
  }

  /// Cache Bible chapters for offline reading
  Future<void> cacheBibleChapter(String book, int chapter) async {
    try {
      final verses = await _client
          .from('bible_verses')
          .select()
          .eq('book', book)
          .eq('chapter', chapter)
          .order('verse');

      await _cache.cacheData(
        'bible_${book}_$chapter',
        verses,
        ttl: const Duration(days: 30), // Bible doesn't change
      );
    } catch (e) {
      debugPrint('Failed to cache Bible chapter: $e');
    }
  }

  /// Cache recent sermons
  Future<void> cacheRecentSermons() async {
    try {
      final sermons = await _client
          .from('sermons')
          .select()
          .order('created_at', ascending: false)
          .limit(20);

      await _cache.cacheData('recent_sermons', sermons, ttl: const Duration(hours: 6));
    } catch (e) {
      debugPrint('Failed to cache recent sermons: $e');
    }
  }

  /// Cache events
  Future<void> cacheEvents(String tenantId) async {
    try {
      final events = await _client
          .from('events')
          .select()
          .eq('church_id', tenantId)
          .gte('event_date', DateTime.now().toIso8601String())
          .order('event_date')
          .limit(20);

      await _cache.cacheData('events_$tenantId', events, ttl: const Duration(hours: 12));
    } catch (e) {
      debugPrint('Failed to cache events: $e');
    }
  }

  /// Cache prayers
  Future<void> cachePrayers() async {
    try {
      final prayers = await _client
          .from('prayers')
          .select()
          .order('created_at', ascending: false)
          .limit(50);

      await _cache.cacheData('prayers', prayers, ttl: const Duration(hours: 6));
    } catch (e) {
      debugPrint('Failed to cache prayers: $e');
    }
  }

  /// Cache all critical data
  Future<void> cacheAllCriticalData() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    // Get user's church (tenant_id, not church_id)
    final profile = await _client
        .from('profiles')
        .select('tenant_id')
        .eq('id', userId)
        .maybeSingle();

    final tenantId = profile?['tenant_id'];

    await Future.wait([
      cacheUserProfile(),
      if (tenantId != null) cacheChurchData(tenantId),
      cacheRecentSermons(),
      if (tenantId != null) cacheEvents(tenantId),
      cachePrayers(),
    ]);
  }

  /// Get cached data with fallback
  Future<T?> getCached<T>(String key) async {
    return await _cache.getCachedData<T>(key);
  }
}

/// Offline indicator widget
class OfflineIndicator extends StatefulWidget {
  final Widget child;

  const OfflineIndicator({super.key, required this.child});

  @override
  State<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends State<OfflineIndicator> {
  bool _isOnline = true;
  late StreamSubscription _subscription;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _subscription = Connectivity().onConnectivityChanged.listen((result) {
      setState(() => _isOnline = result.any((r) => r != ConnectivityResult.none));
    });
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() => _isOnline = result.any((r) => r != ConnectivityResult.none));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!_isOnline)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.orange,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'You\'re offline. Showing cached data.',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
