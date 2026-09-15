import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/supabase_service.dart';

/// Client for the streaming analytics backend (`stream_view_sessions` +
/// `stream_analytics_daily`).
///
/// - Viewers open/close a session while watching (peak/unique viewers,
///   watch-time + retention).
/// - Church leadership reads a tenant-scoped roll-up.
/// - COA staff read a platform-wide roll-up with per-church cost attribution.
class StreamAnalyticsService {
  final SupabaseClient _client;
  StreamAnalyticsService(this._client);

  /// Opens a viewing session. Returns the session id (or null on failure).
  Future<String?> startSession(String streamId) async {
    try {
      if (_client.auth.currentUser == null) return null;
      final res = await _client.rpc('stream_start_session', params: {
        'p_stream_id': streamId,
      });
      return res?.toString();
    } catch (e) {
      debugPrint('stream_start_session failed (non-fatal): $e');
      return null;
    }
  }

  /// Closes a viewing session with the total watched seconds.
  Future<void> endSession(String sessionId, int watchedSeconds) async {
    try {
      await _client.rpc('stream_end_session', params: {
        'p_session_id': sessionId,
        'p_watched_seconds': watchedSeconds,
      });
    } catch (e) {
      debugPrint('stream_end_session failed (non-fatal): $e');
    }
  }

  Future<Map<String, dynamic>?> getTenantAnalytics(
    String tenantId, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final res = await _client.rpc('get_tenant_stream_analytics', params: {
        'p_tenant_id': tenantId,
        'p_from': _d(from),
        'p_to': _d(to),
      });
      return (res as Map?)?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('get_tenant_stream_analytics failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPlatformAnalytics({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final res = await _client.rpc('get_platform_stream_analytics', params: {
        'p_from': _d(from),
        'p_to': _d(to),
      });
      return (res as Map?)?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('get_platform_stream_analytics failed: $e');
      return null;
    }
  }

  static String _d(DateTime? dt) {
    final d = dt ?? DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}

final streamAnalyticsServiceProvider = Provider((ref) {
  return StreamAnalyticsService(ref.watch(supabaseServiceProvider).client);
});

/// Default reporting window (last 30 days). A record gives value equality so
/// the family caches correctly (never key a family with a Map/List).
typedef AnalyticsWindow = ({String tenantId, int days, bool platform});

final streamAnalyticsProvider =
    FutureProvider.family<Map<String, dynamic>?, AnalyticsWindow>((ref, w) async {
  final svc = ref.watch(streamAnalyticsServiceProvider);
  final to = DateTime.now();
  final from = to.subtract(Duration(days: w.days));
  if (w.platform) {
    return svc.getPlatformAnalytics(from: from, to: to);
  }
  return svc.getTenantAnalytics(w.tenantId, from: from, to: to);
});
