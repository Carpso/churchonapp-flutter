import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SmartPrefetchService {
  final SupabaseClient _client;
  static const String _devotionsCacheKey = 'prefetch_devotions_v1';
  static const String _sermonsCacheKey = 'prefetch_sermons_v1';
  static const String _eventsCacheKey = 'prefetch_events_v1';
  static const String _lastPrefetchKey = 'last_prefetch_timestamp';

  SmartPrefetchService(this._client);

  /// Pre-fetches devotions, sermons, and events into SharedPreferences
  Future<void> prefetchAll({String? tenantId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      // Avoid redundant pre-fetches if ran within the last 15 minutes
      final lastPrefetchStr = prefs.getString(_lastPrefetchKey);
      if (lastPrefetchStr != null) {
        final lastPrefetch = DateTime.tryParse(lastPrefetchStr);
        if (lastPrefetch != null && now.difference(lastPrefetch).inMinutes < 15) {
          debugPrint('[SmartPrefetchService] Cache is fresh (< 15 min old). Skipping prefetch.');
          return;
        }
      }

      await Future.wait([
        _prefetchDevotions(prefs),
        _prefetchSermons(prefs),
        _prefetchEvents(prefs, tenantId),
      ]);

      await prefs.setString(_lastPrefetchKey, now.toIso8601String());
      debugPrint('[SmartPrefetchService] Prefetch completed successfully.');
    } catch (e) {
      debugPrint('[SmartPrefetchService] Error during prefetch: $e');
    }
  }

  Future<void> _prefetchDevotions(SharedPreferences prefs) async {
    try {
      final data = await _client
          .from('daily_bible_verses')
          .select()
          .order('date', ascending: false)
          .limit(14);

      if (data.isNotEmpty) {
        await prefs.setString(_devotionsCacheKey, jsonEncode(data));
      }
    } catch (e) {
      debugPrint('[SmartPrefetchService] Devotions prefetch error: $e');
    }
  }

  Future<void> _prefetchSermons(SharedPreferences prefs) async {
    try {
      final data = await _client
          .from('sermons')
          .select()
          .order('created_at', ascending: false)
          .limit(10);

      if (data.isNotEmpty) {
        await prefs.setString(_sermonsCacheKey, jsonEncode(data));
      }
    } catch (e) {
      debugPrint('[SmartPrefetchService] Sermons prefetch error: $e');
    }
  }

  Future<void> _prefetchEvents(SharedPreferences prefs, String? tenantId) async {
    try {
      var query = _client.from('events').select();
      if (tenantId != null && tenantId.isNotEmpty) {
        query = query.eq('tenant_id', tenantId);
      }
      final data = await query.order('date', ascending: true).limit(10);

      if (data.isNotEmpty) {
        await prefs.setString(_eventsCacheKey, jsonEncode(data));
      }
    } catch (e) {
      debugPrint('[SmartPrefetchService] Events prefetch error: $e');
    }
  }

  /// Get pre-cached devotions
  Future<List<Map<String, dynamic>>> getCachedDevotions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_devotionsCacheKey);
      if (str != null) {
        final List decoded = jsonDecode(str);
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('[SmartPrefetchService] Read cached devotions error: $e');
    }
    return [];
  }

  /// Get pre-cached sermons
  Future<List<Map<String, dynamic>>> getCachedSermons() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_sermonsCacheKey);
      if (str != null) {
        final List decoded = jsonDecode(str);
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('[SmartPrefetchService] Read cached sermons error: $e');
    }
    return [];
  }

  /// Get pre-cached events
  Future<List<Map<String, dynamic>>> getCachedEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_eventsCacheKey);
      if (str != null) {
        final List decoded = jsonDecode(str);
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('[SmartPrefetchService] Read cached events error: $e');
    }
    return [];
  }
}

final smartPrefetchProvider = Provider<SmartPrefetchService>((ref) {
  return SmartPrefetchService(Supabase.instance.client);
});
