import 'dart:math' as dart_math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Church On App Live Streaming — viewer/metadata service.
///
/// Architecture (single backend: Cloudflare Stream):
/// - Leaders ingest via WHIP (phone camera) or RTMPS (OBS / external camera)
///   into a Cloudflare Stream live input created by `UnifiedStreamService`.
/// - Cloudflare transcodes to adaptive HLS and auto-records (VOD).
/// - The app plays the HLS URL directly; all metadata lives in Supabase.
///
/// (The legacy self-hosted MediaMTX path was removed — no church uses it.)
class LiveStreamService {
  final SupabaseClient _client;

  static const _publicStreamColumns =
      'id,church_id,title,description,status,streaming_backend,scheduled_at,started_at,ended_at,hls_url,recording_hls_url,dash_url,preview_url,viewer_count,created_at,cloudflare_video_id,thumbnail_url,is_audio_only,archive_url,archive_status,archived_at';

  LiveStreamService(this._client);

  /// Get active live streams
  Future<List<Map<String, dynamic>>> getActiveStreams() async {
    try {
      final result = await _client
          .from('live_streams')
          .select('$_publicStreamColumns, churches(id, name, logo_url)')
          .eq('status', 'live')
          .order('started_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(result);
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('[LiveStreamService] join select failed, retrying plain: $e');
      // Schema/RLS drift on the churches join must not blank the live list.
      try {
        final fallback = await _client
            .from('live_streams')
            .select(_publicStreamColumns)
            .eq('status', 'live')
            .order('started_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(fallback);
        if (list.isNotEmpty) return list;
      } catch (e2) {
        debugPrint('[LiveStreamService] Error fetching active streams: $e2');
      }
    }

    // No fake/demo streams — show the honest empty state so the UI never
    // masquerades a placeholder (Big Buck Bunny etc.) as a live church stream.
    return [];
  }

  /// Get upcoming scheduled streams
  Future<List<Map<String, dynamic>>> getUpcomingStreams() async {
    try {
      final result = await _client
          .from('live_streams')
          .select('$_publicStreamColumns, churches(id, name, logo_url)')
          .eq('status', 'scheduled')
          .gte('scheduled_at', DateTime.now().toIso8601String())
          .order('scheduled_at');

      final list = List<Map<String, dynamic>>.from(result);
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('[LiveStreamService] join select failed, retrying plain: $e');
      try {
        final fallback = await _client
            .from('live_streams')
            .select(_publicStreamColumns)
            .eq('status', 'scheduled')
            .gte('scheduled_at', DateTime.now().toIso8601String())
            .order('scheduled_at');
        final list = List<Map<String, dynamic>>.from(fallback);
        if (list.isNotEmpty) return list;
      } catch (e2) {
        debugPrint('[LiveStreamService] Error fetching upcoming streams: $e2');
      }
    }

    // No fake/demo upcoming streams — show honest empty state.
    return [];
  }

  /// Past services with their real archive state.
  ///
  /// Ready rows play from the permanent R2 `archive_url`; rows still
  /// queued/processing (or failed) are returned too so the UI can show
  /// "Processing recording…" / a retry instead of hiding them.
  Future<List<Map<String, dynamic>>> getRecentRecordings({int limit = 12}) async {
    try {
      final result = await _client
          .from('live_streams')
          .select('$_publicStreamColumns, archive_error, churches(id, name, logo_url)')
          .inFilter('status', ['ended', 'archived'])
          .not('cloudflare_stream_id', 'is', null)
          .order('ended_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('[LiveStreamService] recent recordings failed: $e');
      return [];
    }
  }

  /// Resolves the R2 archive URL for a stream (used by the viewer as a playback
  /// fallback once the Cloudflare recording expires).
  Future<String?> getArchiveUrl(String streamId) async {
    try {
      final row = await _client
          .from('live_streams')
          .select('archive_url, archive_status')
          .eq('id', streamId)
          .maybeSingle();
      if (row == null) return null;
      if (row['archive_status'] != 'ready') return null;
      final url = row['archive_url']?.toString();
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (e) {
      debugPrint('[LiveStreamService] archive url lookup failed: $e');
      return null;
    }
  }

  /// Get stream by ID
  Future<Map<String, dynamic>?> getStream(String streamId) async {
    final result = await _client
        .from('live_streams')
        .select('$_publicStreamColumns, churches(id, name, logo_url)')
        .eq('id', streamId)
        .maybeSingle();

    return result;
  }

  /// The church's current live stream row (if any). Used by home entry points
  /// that only know the tenant — so the viewer can still resolve a streamId and
  /// repair a stale/empty playback URL instead of showing "offline".
  Future<Map<String, dynamic>?> getActiveStreamForChurch(String churchId) async {
    if (churchId.isEmpty) return null;
    try {
      return await _client
          .from('live_streams')
          .select(_publicStreamColumns)
          .eq('church_id', churchId)
          .eq('status', 'live')
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (e) {
      debugPrint('[LiveStreamService] active stream lookup failed: $e');
      return null;
    }
  }

  /// Reconciles a stale `live_streams` row with Cloudflare's REAL live-input
  /// state via the viewer-safe `refresh_live_input` Edge action. This is what
  /// lets a viewer recover when the row is `live` but its `hls_url` is empty or
  /// the live input's HLS manifest is not ready yet.
  Future<LiveStreamPlaybackInfo?> refreshPlayback(String streamId) async {
    if (streamId.isEmpty) return null;
    try {
      final token = _client.auth.currentSession?.accessToken;
      final res = await _client.functions.invoke(
        'cloudflare-stream',
        body: {'action': 'refresh_live_input', 'stream_id': streamId},
        headers: (token == null || token.isEmpty)
            ? null
            : {'Authorization': 'Bearer $token'},
      );
      final data = res.data;
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        return LiveStreamPlaybackInfo(
          success: m['success'] == true,
          hlsUrl: _asString(m['hls']),
          recordingHlsUrl: _asString(m['recording_hls']),
          cloudflareVideoId: _asString(m['cloudflare_video_id']),
          dashUrl: _asString(m['dash']),
          inputStatus: _asString(m['input_status']),
          connected: m['connected'] == true,
          enabled: m['enabled'] == true,
          reason: _asString(m['reason']),
        );
      }
    } catch (e) {
      debugPrint('[LiveStreamService] refreshPlayback failed: $e');
    }
    return null;
  }

  static String? _asString(dynamic v) {
    final s = v?.toString();
    return (s == null || s.isEmpty || s == 'null') ? null : s;
  }

  /// Create a new live stream (church admin)
  Future<Map<String, dynamic>> createStream({
    required String title,
    required String tenantId,
    String? description,
    DateTime? scheduledAt,
    String? streamKey,
    String? hlsUrl,
    String? rtmpUrl,
  }) async {
    // Generate a unique stream key if not provided
    final key = streamKey ?? _generateStreamKey();

    final result = await _client
        .from('live_streams')
        .insert({
          'title': title,
          'church_id': tenantId,
          'description': description,
          'status': scheduledAt != null ? 'scheduled' : 'live',
          'scheduled_at': scheduledAt?.toIso8601String(),
          'started_at': scheduledAt == null ? DateTime.now().toIso8601String() : null,
          'stream_key': key,
          'hls_url': hlsUrl,
          'rtmp_url': rtmpUrl,
          'created_by': _client.auth.currentUser?.id,
        })
        .select()
        .single();

    return result;
  }

  /// Start a scheduled stream (leadership-gated, server-side).
  Future<void> startStream(String streamId) async {
    try {
      final ok = await _client.rpc(
        'start_scheduled_stream',
        params: {'p_stream_id': streamId},
      );
      if (ok == true) return;
    } catch (e) {
      debugPrint('[LiveStreamService] start_scheduled_stream RPC failed: $e');
    }

    // Fallback: direct update (RLS live_streams_manage still gates leadership).
    await _client
        .from('live_streams')
        .update({
          'status': 'live',
          'started_at': DateTime.now().toIso8601String(),
          'scheduled_at': null,
        })
        .eq('id', streamId);
  }

  /// End a live stream
  Future<void> endStream(String streamId) async {
    await _client
        .from('live_streams')
        .update({
          'status': 'ended',
          'ended_at': DateTime.now().toIso8601String(),
        })
        .eq('id', streamId);
  }

  /// Update viewer count
  Future<void> updateViewerCount(String streamId, int count) async {
    await _client
        .from('live_streams')
        .update({'viewer_count': count})
        .eq('id', streamId);
  }

  /// Send a live chat message
  Future<void> sendChatMessage({
    required String streamId,
    required String message,
    String? replyToId,
  }) async {
    await _client.from('stream_chat_messages').insert({
      'stream_id': streamId,
      'user_id': _client.auth.currentUser?.id,
      'content': message,
    });
  }

  /// Get live chat messages stream
  Stream<List<Map<String, dynamic>>> chatMessagesStream(String streamId) {
    return _client
        .from('stream_chat_messages')
        .stream(primaryKey: ['id'])
        .eq('stream_id', streamId)
        .order('created_at')
        .map((events) => List<Map<String, dynamic>>.from(events));
  }

  /// Toggle prayer request during stream
  Future<void> togglePrayerRequest(String streamId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final existing = await _client
        .from('stream_prayer_requests')
        .select()
        .eq('stream_id', streamId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      await _client
          .from('stream_prayer_requests')
          .delete()
          .eq('id', existing['id']);
    } else {
      await _client.from('stream_prayer_requests').insert({
        'stream_id': streamId,
        'user_id': userId,
      });
    }
  }

  /// Get stream analytics (for church admin)
  Future<Map<String, dynamic>> getStreamAnalytics(String streamId) async {
    final result = await _client
        .from('live_streams')
        .select('viewer_count, started_at, ended_at')
        .eq('id', streamId)
        .maybeSingle();

    if (result == null) return {};

    final started = result['started_at'] != null
        ? DateTime.parse(result['started_at'])
        : null;
    final ended = result['ended_at'] != null
        ? DateTime.parse(result['ended_at'])
        : null;

    final duration = started != null
        ? (ended ?? DateTime.now()).difference(started)
        : Duration.zero;

    return {
      'peak_viewers': result['viewer_count'] ?? 0,
      'duration_minutes': duration.inMinutes,
      'is_live': ended == null && started != null,
    };
  }

  /// Generate a secure stream key
  String _generateStreamKey() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rng = dart_math.Random.secure();
    final chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = List.generate(16, (_) => chars[rng.nextInt(chars.length)]).join();
    return 'coa_${timestamp}_$random';
  }
}

final liveStreamServiceProvider = Provider<LiveStreamService>((ref) {
  return LiveStreamService(Supabase.instance.client);
});

/// Result of a `refresh_live_input` reconciliation.
class LiveStreamPlaybackInfo {
  final bool success;
  final String? hlsUrl;

  /// The finished recording's OWN HLS manifest. The live-input manifest
  /// (`hlsUrl`) returns 204 once a broadcast ends; this one stays playable.
  final String? recordingHlsUrl;

  /// Cloudflare Stream video uid of the resolved recording (if any).
  final String? cloudflareVideoId;
  final String? dashUrl;

  /// Cloudflare live-input status: connected/reconnecting/client_disconnect…
  final String? inputStatus;
  final bool connected;
  final bool enabled;

  /// `no_input` when the row has no Cloudflare live input (e.g. scheduled).
  final String? reason;

  const LiveStreamPlaybackInfo({
    required this.success,
    this.hlsUrl,
    this.recordingHlsUrl,
    this.cloudflareVideoId,
    this.dashUrl,
    this.inputStatus,
    this.connected = false,
    this.enabled = false,
    this.reason,
  });

  bool get notYetStarted =>
      !connected && (inputStatus == null || inputStatus != 'connected');
}

final activeStreamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.watch(liveStreamServiceProvider);
  return service.getActiveStreams();
});

final upcomingStreamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.watch(liveStreamServiceProvider);
  return service.getUpcomingStreams();
});

/// Past services (ready + still-archiving) — replayable once the R2 master is
/// ready. Re-polls while any recording is queued/processing so the list updates
/// on its own, then stops.
final recentRecordingsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final service = ref.watch(liveStreamServiceProvider);
  while (true) {
    final rows = await service.getRecentRecordings();
    yield rows;
    final working = rows.any((r) {
      final s = (r['archive_status'] ?? 'none').toString();
      return s == 'queued' || s == 'processing' || s == 'archiving';
    });
    if (!working) break;
    await Future<void>.delayed(const Duration(seconds: 15));
  }
});

/// The church's current live stream row (or null). Keyed by tenant id.
final churchActiveStreamProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, churchId) async {
  final service = ref.watch(liveStreamServiceProvider);
  return service.getActiveStreamForChurch(churchId);
});

