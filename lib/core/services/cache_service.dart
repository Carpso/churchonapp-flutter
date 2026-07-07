import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final cacheServiceProvider = Provider<CacheService>((ref) => CacheService());

class CacheService {
  static const String _prefix = 'coa_cache_';
  static const String _keysIndex = '${_prefix}keys';

  Future<void> cacheData(String key, dynamic data, {Duration? expiry}) async {
    final prefs = await SharedPreferences.getInstance();
    final entry = {
      'data': data,
      'cached_at': DateTime.now().toIso8601String(),
      'expires_at': expiry != null
          ? DateTime.now().add(expiry).toIso8601String()
          : null,
    };
    await prefs.setString('$_prefix$key', jsonEncode(entry));

    final keys = prefs.getStringList(_keysIndex) ?? [];
    if (!keys.contains(key)) {
      keys.add(key);
      await prefs.setStringList(_keysIndex, keys);
    }
  }

  Future<T?> getCachedData<T>(String key,
      {T Function(dynamic)? fromJson, bool ignoreExpiry = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;

    try {
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      if (!ignoreExpiry && entry['expires_at'] != null) {
        final expiresAt = DateTime.parse(entry['expires_at'] as String);
        if (DateTime.now().isAfter(expiresAt)) {
          await prefs.remove('$_prefix$key');
          return null;
        }
      }
      final data = entry['data'];
      if (fromJson != null) return fromJson(data);
      return data as T;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList(_keysIndex) ?? [];
    for (final key in keys) {
      await prefs.remove('$_prefix$key');
    }
    await prefs.remove(_keysIndex);
  }

  Future<void> clearKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
    final keys = prefs.getStringList(_keysIndex) ?? [];
    keys.remove(key);
    await prefs.setStringList(_keysIndex, keys);
  }

  Future<bool> hasCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_prefix$key');
  }
}

class CacheKeys {
  static const String sermons = 'sermons';
  static const String events = 'events';
  static const String bibleVerses = 'bible_verses';
  static const String products = 'products';
  static const String prayers = 'prayers';
  static const String jobs = 'jobs';
  static const String news = 'news';
  static const String profile = 'profile';
  static const String announcements = 'announcements';
  static const String transactions = 'transactions';
  static const String groups = 'groups';
  static const String communities = 'communities';
  static const String members = 'members';
  static const String studyPlans = 'study_plans';
}
