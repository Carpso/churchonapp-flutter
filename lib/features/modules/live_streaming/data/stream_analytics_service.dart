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

  /// Keeps a viewing session alive so it is not expired as a stale viewer.
  Future<void> heartbeatSession(String sessionId) async {
    try {
      await _client.rpc('stream_viewer_heartbeat', params: {
        'p_session_id': sessionId,
      });
    } catch (e) {
      debugPrint('stream_viewer_heartbeat failed (non-fatal): $e');
    }
  }

  /// Read-only viewer count/peak for a stream. Viewers poll this (cheap) while
  /// the streamer (or a session open/close) performs the server-side refresh.
  Future<({int count, int peak})?> getViewerCount(String streamId) async {
    try {
      final row = await _client
          .from('live_streams')
          .select('viewer_count, peak_viewer_count')
          .eq('id', streamId)
          .maybeSingle();
      if (row == null) return null;
      return (
        count: (row['viewer_count'] as num?)?.toInt() ?? 0,
        peak: (row['peak_viewer_count'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('getViewerCount failed (non-fatal): $e');
      return null;
    }
  }

  /// Recomputes the published live viewer count for a stream (server-side).
  /// Returns `(count, peak)` — the current audience and the all-time high.
  Future<({int count, int peak})?> refreshViewerCount(String streamId) async {
    try {
      final res = await _client.rpc('stream_refresh_viewer_count', params: {
        'p_stream_id': streamId,
      });
      if (res is Map) {
        final row = Map<String, dynamic>.from(res);
        return (
          count: (row['count'] as num?)?.toInt() ?? 0,
          peak: (row['peak'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (e) {
      debugPrint('stream_refresh_viewer_count failed (non-fatal): $e');
    }
    return null;
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
