import 'dart:async';
import 'dart:math' as dart_math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Unified streaming service for Church On App
/// Cloudflare Stream (ingest + delivery) + R2 (recordings) + Supabase (metadata)
///
/// COST CONTROLS (keeps costs within bounds):
/// - Trial churches: 10 min/week, 25 viewers, 7-day retention, 1GB storage
/// - K1,500 subscribers: 8 hrs/week, 200 viewers, 90-day retention, 10GB storage
/// - Auto-delete recordings after retention period
/// - Max quality cap: 720p (saves ~60% bandwidth vs 1080p)
/// - Storage gated: churches pay K50/GB beyond free tier
///
enum StreamingBackend { cloudflare, mediamtx }

class UnifiedStreamService {
  final SupabaseClient _client;

  UnifiedStreamService(this._client);

  /// Get streaming config for a church
  Future<StreamingConfig> getStreamingConfig(String tenantId) async {
    final result = await _client
        .from('church_stream_config')
        .select()
        .eq('church_id', tenantId)
        .maybeSingle();

    if (result == null) {
      return StreamingConfig.defaultConfig(tenantId);
    }

    return StreamingConfig.fromMap(result);
  }

  /// Check if church can start a stream (cost control gate)
  Future<StreamGateResult> checkStreamGate(String tenantId) async {
    final config = await getStreamingConfig(tenantId);
    final usage = await getStreamingUsage(tenantId);

    // Check weekly minutes
    if (!config.isPaid && usage.minutesUsed >= config.maxMinutesPerWeek) {
      return StreamGateResult(
        allowed: false,
        reason: 'Weekly streaming limit reached (${config.maxMinutesPerWeek} min)',
        upgradeRequired: true,
      );
    }

    // Check concurrent streams
    final activeStreams = await _client
        .from('live_streams')
        .select('id')
        .eq('church_id', tenantId)
        .eq('status', 'live')
        .count();

    if (activeStreams.count >= config.maxConcurrentStreams) {
      return StreamGateResult(
        allowed: false,
        reason: 'Maximum concurrent streams reached (${config.maxConcurrentStreams})',
        upgradeRequired: false,
      );
    }

    // Check storage usage
    final storageUsed = await getStorageUsage(tenantId);
    if (storageUsed >= config.maxStorageGb) {
      return StreamGateResult(
        allowed: false,
        reason: 'Storage limit reached (${config.maxStorageGb}GB). Delete old recordings or upgrade.',
        upgradeRequired: true,
        storageExceeded: true,
      );
    }

    return StreamGateResult(allowed: true);
  }

  /// Get streaming usage for a church (this week)
  Future<StreamingUsage> getStreamingUsage(String tenantId) async {
    try {
      final result = await _client
          .rpc('get_streaming_usage', params: {'p_church_id': tenantId});

      if (result != null && result is Map) {
        return StreamingUsage.fromMap(result as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Failed to get streaming usage: $e');
    }

    return StreamingUsage(tenantId: tenantId);
  }

  /// Get R2 storage usage in GB
  Future<double> getStorageUsage(String tenantId) async {
    try {
      final result = await _client
          .from('live_streams')
          .select('storage_bytes')
          .eq('church_id', tenantId);

      final totalBytes = result.fold<int>(0, (sum, r) => sum + ((r['storage_bytes'] as int?) ?? 0));
      return totalBytes / (1024 * 1024 * 1024); // Convert to GB
    } catch (e) {
      return 0;
    }
  }

  /// Create a live stream using the configured backend
  Future<StreamResult> createLiveStream({
    required String tenantId,
    required String title,
    String? description,
    DateTime? scheduledAt,
  }) async {
    // Gate check: ensure church is within limits
    final gate = await checkStreamGate(tenantId);
    if (!gate.allowed) {
      throw StreamLimitException(gate.reason!);
    }

    final config = await getStreamingConfig(tenantId);

    switch (config.backend) {
      case StreamingBackend.cloudflare:
        return _createCloudflareStream(
          config: config,
          title: title,
          description: description,
          scheduledAt: scheduledAt,
        );
      case StreamingBackend.mediamtx:
        return _createMediaMTXStream(
          config: config,
          tenantId: tenantId,
          title: title,
          description: description,
          scheduledAt: scheduledAt,
        );
    }
  }

  /// Create stream via Cloudflare Stream API
  Future<StreamResult> _createCloudflareStream({
    required StreamingConfig config,
    required String title,
    String? description,
    DateTime? scheduledAt,
  }) async {
    final response = await _client.functions.invoke(
      'cloudflare-stream',
      body: {
        'action': 'create_live_input',
        'meta': {
          'name': title,
          'description': description,
          'max_duration': config.maxStreamDurationSec,
          'allowed_origins': ['*'],
        },
      },
    );

    if (response.data == null) {
      throw Exception('Failed to create Cloudflare Stream');
    }

    final data = response.data as Map<String, dynamic>;
    final streamId = data['uid'] as String? ?? '';
    final rtmps = (data['rtmps'] as Map?)?.cast<String, dynamic>() ?? {};
    final rtmpUrl = rtmps['url'] as String? ?? '';
    final streamKey = rtmps['streamKey'] as String? ?? '';
    final hlsUrl = data['hls'] as String? ?? '';
    final dashUrl = data['dash'] as String? ?? '';
    final previewUrl = data['webRTCPlayback'] is Map ? (data['webRTCPlayback'] as Map)['url'] as String? : null;

    final result = await _client
        .from('live_streams')
        .insert({
          'church_id': config.tenantId,
          'title': title,
          'description': description,
          'status': scheduledAt != null ? 'scheduled' : 'live',
          'scheduled_at': scheduledAt?.toIso8601String(),
          'started_at': scheduledAt == null ? DateTime.now().toIso8601String() : null,
          'streaming_backend': 'cloudflare',
          'cloudflare_stream_id': streamId,
          'rtmp_url': rtmpUrl,
          'stream_key': streamKey,
          'hls_url': hlsUrl,
          'dash_url': dashUrl,
          'preview_url': previewUrl,
          'created_by': _client.auth.currentUser?.id,
        })
        .select()
        .single();

    return StreamResult(
      streamId: result['id'],
      backend: StreamingBackend.cloudflare,
      rtmpUrl: rtmpUrl,
      streamKey: streamKey,
      hlsUrl: hlsUrl,
      dashUrl: dashUrl,
      previewUrl: previewUrl,
    );
  }

  /// Create stream via MediaMTX (self-hosted)
  Future<StreamResult> _createMediaMTXStream({
    required StreamingConfig config,
    required String tenantId,
    required String title,
    String? description,
    DateTime? scheduledAt,
  }) async {
    final streamKey = _generateStreamKey();
    final streamPath = '$tenantId/$streamKey';

    final rtmpUrl = 'rtmp://${config.mediamtxHost ?? "stream.churchonapp.com"}/live';
    final hlsUrl = 'https://${config.mediamtxHost ?? "stream.churchonapp.com"}/$streamPath/index.m3u8';
    final dashUrl = 'https://${config.mediamtxHost ?? "stream.churchonapp.com"}/$streamPath/index.mpd';

    final result = await _client
        .from('live_streams')
        .insert({
          'church_id': tenantId,
          'title': title,
          'description': description,
          'status': scheduledAt != null ? 'scheduled' : 'live',
          'scheduled_at': scheduledAt?.toIso8601String(),
          'started_at': scheduledAt == null ? DateTime.now().toIso8601String() : null,
          'streaming_backend': 'mediamtx',
          'rtmp_url': rtmpUrl,
          'stream_key': streamKey,
          'hls_url': hlsUrl,
          'dash_url': dashUrl,
          'created_by': _client.auth.currentUser?.id,
        })
        .select()
        .single();

    return StreamResult(
      streamId: result['id'],
      backend: StreamingBackend.mediamtx,
      rtmpUrl: rtmpUrl,
      streamKey: streamKey,
      hlsUrl: hlsUrl,
      dashUrl: dashUrl,
    );
  }

  /// End a live stream and trigger recording archival
  Future<void> endStream(String streamId) async {
    final stream = await _client
        .from('live_streams')
        .select('streaming_backend, cloudflare_stream_id, church_id, started_at')
        .eq('id', streamId)
        .single();

    // If Cloudflare, delete the live input (stops billing for ingest)
    if (stream['streaming_backend'] == 'cloudflare' && stream['cloudflare_stream_id'] != null) {
      await _client.functions.invoke(
        'cloudflare-stream',
        body: {
          'action': 'delete_live_input',
          'input_id': stream['cloudflare_stream_id'],
        },
      );
    }

    // BUG-3: Record streaming minutes for usage tracking / cost control
    if (stream['started_at'] != null && stream['church_id'] != null) {
      try {
        final startedAt = DateTime.parse(stream['started_at']);
        final minutes = DateTime.now().difference(startedAt).inMinutes;
        if (minutes > 0) {
          await _client.rpc('record_streaming_minutes', params: {
            'p_church_id': stream['church_id'],
            'p_minutes': minutes,
          });
        }
      } catch (e) {
        debugPrint('[Stream] Failed to record streaming minutes: $e');
      }
    }

    // Update status
    await _client
        .from('live_streams')
        .update({
          'status': 'ended',
          'ended_at': DateTime.now().toIso8601String(),
        })
        .eq('id', streamId);

    // Trigger auto-cleanup of old recordings (background)
    _cleanupOldRecordings(stream['church_id']);
  }

  /// Auto-delete recordings past retention period (cost control)
  Future<void> _cleanupOldRecordings(String tenantId) async {
    try {
      final config = await getStreamingConfig(tenantId);
      final retentionDays = config.retentionDays;

      // Find recordings older than retention
      final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
      final oldStreams = await _client
          .from('live_streams')
          .select('id, cloudflare_stream_id')
          .eq('church_id', tenantId)
          .eq('status', 'ended')
          .lt('ended_at', cutoff.toIso8601String())
          .not('cloudflare_stream_id', 'is', null);

      for (final stream in oldStreams) {
        // Delete from Cloudflare Stream (frees storage)
        if (stream['cloudflare_stream_id'] != null) {
          await _client.functions.invoke(
            'cloudflare-stream',
            body: {
              'action': 'delete_video',
              'video_id': stream['cloudflare_stream_id'],
            },
          );
        }

        // Mark as archived (recording deleted, metadata kept)
        await _client
            .from('live_streams')
            .update({
              'status': 'archived',
              'hls_url': null,
              'dash_url': null,
              'storage_bytes': 0,
            })
            .eq('id', stream['id']);
      }

      debugPrint('Cleaned up ${oldStreams.length} old recordings for $tenantId');
    } catch (e) {
      debugPrint('Recording cleanup failed: $e');
    }
  }

  /// Get stream analytics
  Future<StreamAnalytics> getAnalytics(String streamId) async {
    final stream = await _client
        .from('live_streams')
        .select()
        .eq('id', streamId)
        .single();

    int peakViewers = stream['viewer_count'] ?? 0;
    Duration duration = Duration.zero;

    if (stream['started_at'] != null) {
      final started = DateTime.parse(stream['started_at']);
      final ended = stream['ended_at'] != null
          ? DateTime.parse(stream['ended_at'])
          : DateTime.now();
      duration = ended.difference(started);
    }

    if (stream['streaming_backend'] == 'cloudflare' && stream['cloudflare_stream_id'] != null) {
      try {
        final response = await _client.functions.invoke(
          'cloudflare-stream',
          body: {
            'action': 'get_analytics',
            'input_id': stream['cloudflare_stream_id'],
          },
        );

        if (response.data != null) {
          final analytics = response.data as Map<String, dynamic>;
          peakViewers = analytics['peakViewers'] ?? peakViewers;
        }
      } catch (e) {
        debugPrint('Failed to fetch Cloudflare analytics: $e');
      }
    }

    return StreamAnalytics(
      peakViewers: peakViewers,
      duration: duration,
      isLive: stream['status'] == 'live',
      backend: stream['streaming_backend'] ?? 'unknown',
    );
  }

  String _generateStreamKey() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = dart_math.Random.secure();
    final random = List.generate(16, (_) => chars[rng.nextInt(chars.length)]).join();
    return 'coa_${timestamp}_$random';
  }
}

/// Streaming configuration for a church
class StreamingConfig {
  final String tenantId;
  final StreamingBackend backend;
  final String? cloudflareAccountId;
  final String? cloudflareApiToken;
  final String? mediamtxHost;
  final String? mediamtxSecret;
  final bool autoRecord;
  final bool enableChat;
  final bool enablePrayerRequests;
  final int maxConcurrentStreams;
  // Cost controls
  final bool isPaid;
  final int maxMinutesPerWeek;
  final int maxViewers;
  final int retentionDays;
  final double maxStorageGb;
  final int maxStreamDurationSec;
  final int maxQuality; // 0=auto, 480, 720, 1080

  StreamingConfig({
    required this.tenantId,
    this.backend = StreamingBackend.cloudflare,
    this.cloudflareAccountId,
    this.cloudflareApiToken,
    this.mediamtxHost,
    this.mediamtxSecret,
    this.autoRecord = true,
    this.enableChat = true,
    this.enablePrayerRequests = true,
    this.maxConcurrentStreams = 1,
    this.isPaid = false,
    this.maxMinutesPerWeek = 10,
    this.maxViewers = 25,
    this.retentionDays = 7,
    this.maxStorageGb = 1.0,
    this.maxStreamDurationSec = 3600,
    this.maxQuality = 720,
  });

  factory StreamingConfig.defaultConfig(String tenantId) {
    return StreamingConfig(
      tenantId: tenantId,
      backend: StreamingBackend.cloudflare,
      isPaid: false,
      maxMinutesPerWeek: 10,
      maxViewers: 25,
      retentionDays: 7,
      maxStorageGb: 1.0,
      maxStreamDurationSec: 3600,
      maxQuality: 720,
      autoRecord: true,
      enableChat: true,
      enablePrayerRequests: true,
    );
  }

  factory StreamingConfig.paidConfig(String tenantId) {
    return StreamingConfig(
      tenantId: tenantId,
      backend: StreamingBackend.cloudflare,
      isPaid: true,
      maxMinutesPerWeek: 480, // 8 hours
      maxViewers: 1000, // 1,000 viewers included, then K5/viewer extra
      retentionDays: 90,
      maxStorageGb: 10.0,
      maxStreamDurationSec: 14400, // 4 hours
      maxQuality: 720,
      autoRecord: true,
      enableChat: true,
      enablePrayerRequests: true,
    );
  }

  factory StreamingConfig.fromMap(Map<String, dynamic> map) {
    return StreamingConfig(
      tenantId: map['church_id'],
      backend: StreamingBackend.values.firstWhere(
        (b) => b.name == (map['backend'] ?? 'cloudflare'),
        orElse: () => StreamingBackend.cloudflare,
      ),
      cloudflareAccountId: map['cloudflare_account_id'],
      cloudflareApiToken: map['cloudflare_api_token'],
      mediamtxHost: map['mediamtx_host'],
      mediamtxSecret: map['mediamtx_secret'],
      autoRecord: map['auto_record'] ?? true,
      enableChat: map['enable_chat'] ?? true,
      enablePrayerRequests: map['enable_prayer_requests'] ?? true,
      maxConcurrentStreams: map['max_concurrent_streams'] ?? 1,
      isPaid: map['is_paid'] ?? false,
      maxMinutesPerWeek: map['max_minutes_per_week'] ?? 10,
      maxViewers: map['max_viewers'] ?? 25,
      retentionDays: map['retention_days'] ?? 7,
      maxStorageGb: (map['max_storage_gb'] ?? 1.0).toDouble(),
      maxStreamDurationSec: map['max_stream_duration_sec'] ?? 3600,
      maxQuality: map['max_quality'] ?? 720,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'church_id': tenantId,
      'backend': backend.name,
      'cloudflare_account_id': cloudflareAccountId,
      'cloudflare_api_token': cloudflareApiToken,
      'mediamtx_host': mediamtxHost,
      'mediamtx_secret': mediamtxSecret,
      'auto_record': autoRecord,
      'enable_chat': enableChat,
      'enable_prayer_requests': enablePrayerRequests,
      'max_concurrent_streams': maxConcurrentStreams,
      'is_paid': isPaid,
      'max_minutes_per_week': maxMinutesPerWeek,
      'max_viewers': maxViewers,
      'retention_days': retentionDays,
      'max_storage_gb': maxStorageGb,
      'max_stream_duration_sec': maxStreamDurationSec,
      'max_quality': maxQuality,
    };
  }
}

/// Stream creation result
class StreamResult {
  final String streamId;
  final StreamingBackend backend;
  final String rtmpUrl;
  final String streamKey;
  final String hlsUrl;
  final String? dashUrl;
  final String? previewUrl;

  StreamResult({
    required this.streamId,
    required this.backend,
    required this.rtmpUrl,
    required this.streamKey,
    required this.hlsUrl,
    this.dashUrl,
    this.previewUrl,
  });
}

/// Stream analytics
class StreamAnalytics {
  final int peakViewers;
  final Duration duration;
  final bool isLive;
  final String backend;

  StreamAnalytics({
    required this.peakViewers,
    required this.duration,
    required this.isLive,
    required this.backend,
  });
}

/// Streaming usage (weekly)
class StreamingUsage {
  final String tenantId;
  final int minutesUsed;
  final int minutesLimit;
  final int peakViewers;
  final int viewersLimit;
  final double storageUsedGb;
  final double storageLimitGb;
  final bool unlimited;

  StreamingUsage({
    required this.tenantId,
    this.minutesUsed = 0,
    this.minutesLimit = 10,
    this.peakViewers = 0,
    this.viewersLimit = 25,
    this.storageUsedGb = 0,
    this.storageLimitGb = 1.0,
    this.unlimited = false,
  });

  int get minutesRemaining => unlimited ? 999999 : (minutesLimit - minutesUsed).clamp(0, minutesLimit);
  bool get canStream => unlimited || minutesUsed < minutesLimit;
  bool get storageExceeded => storageUsedGb >= storageLimitGb;
  double get storagePercent => storageLimitGb > 0 ? (storageUsedGb / storageLimitGb).clamp(0, 1) : 0;
  double get minutesPercent => unlimited ? 0 : (minutesUsed / minutesLimit).clamp(0, 1);

  factory StreamingUsage.fromMap(Map<String, dynamic> map) {
    return StreamingUsage(
      tenantId: map['church_id'] ?? '',
      minutesUsed: map['minutes_used'] ?? 0,
      minutesLimit: map['minutes_limit'] ?? 10,
      peakViewers: map['peak_viewers'] ?? 0,
      viewersLimit: map['viewers_limit'] ?? 25,
      storageUsedGb: (map['storage_used_gb'] ?? 0).toDouble(),
      storageLimitGb: (map['storage_limit_gb'] ?? 1.0).toDouble(),
      unlimited: map['unlimited'] ?? false,
    );
  }
}

/// Gate result
class StreamGateResult {
  final bool allowed;
  final String? reason;
  final bool upgradeRequired;
  final bool storageExceeded;

  StreamGateResult({
    required this.allowed,
    this.reason,
    this.upgradeRequired = false,
    this.storageExceeded = false,
  });
}

/// Stream limit exception
class StreamLimitException implements Exception {
  final String message;
  StreamLimitException(this.message);

  @override
  String toString() => 'StreamLimitException: $message';
}

final unifiedStreamServiceProvider = Provider<UnifiedStreamService>((ref) {
  return UnifiedStreamService(Supabase.instance.client);
});
