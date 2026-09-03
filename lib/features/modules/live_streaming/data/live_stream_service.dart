import 'dart:async';
import 'package:universal_io/io.dart';
import 'dart:math' as dart_math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

/// Church On App Live Streaming Service
///
/// Architecture:
/// - Churches stream via OBS → RTMP to MediaMTX server ($5/mo VPS)
/// - MediaMTX converts RTMP → HLS automatically
/// - App plays HLS directly (Flutter video_player supports natively)
/// - Streams recorded to Cloudflare R2 for VOD
/// - All metadata stored in Supabase
///
/// This is the cheapest reliable option:
/// - MediaMTX: free, open-source, runs on any VPS
/// - HLS: adaptive bitrate, works on slow connections
/// - R2: $0.015/GB storage, free egress
/// - No per-minute charges like Cloudflare Stream
class LiveStreamService {
  final SupabaseClient _client;

  LiveStreamService(this._client);

  /// Get active live streams
  Future<List<Map<String, dynamic>>> getActiveStreams() async {
    try {
      final result = await _client
          .from('live_streams')
          .select('*, churches(id, name, logo_url)')
          .eq('status', 'live')
          .order('started_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(result);
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('[LiveStreamService] Error fetching active streams: $e');
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
          .select('*, churches(id, name, logo_url)')
          .eq('status', 'scheduled')
          .gte('scheduled_at', DateTime.now().toIso8601String())
          .order('scheduled_at');

      final list = List<Map<String, dynamic>>.from(result);
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('[LiveStreamService] Error fetching upcoming streams: $e');
    }

    return [
      {
        'id': 'demo_upcoming_stream_1',
        'title': 'Mid-Week Prayer & Revival Night',
        'description': 'Intercession and prophetic worship for Zambia.',
        'status': 'scheduled',
        'scheduled_at': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        'churches': {
          'id': '00000000-0000-0000-0000-000000000001',
          'name': 'Grace City Church',
          'logo_url': 'https://i.imgur.com/8N6v6yG.png',
        },
      },
    ];
  }

  /// Get stream by ID
  Future<Map<String, dynamic>?> getStream(String streamId) async {
    final result = await _client
        .from('live_streams')
        .select('*, churches(id, name, logo_url)')
        .eq('id', streamId)
        .maybeSingle();

    return result;
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
          'rtmp_url': rtmpUrl ?? 'rtmp://stream.churchonapp.com/live',
          'created_by': _client.auth.currentUser?.id,
        })
        .select()
        .single();

    return result;
  }

  /// Start a scheduled stream
  Future<void> startStream(String streamId) async {
    await _client
        .from('live_streams')
        .update({
          'status': 'live',
          'started_at': DateTime.now().toIso8601String(),
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

final activeStreamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.watch(liveStreamServiceProvider);
  return service.getActiveStreams();
});

final upcomingStreamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.watch(liveStreamServiceProvider);
  return service.getUpcomingStreams();
});

/// Adaptive quality player - adjusts based on connection speed
class AdaptiveStreamPlayer extends StatefulWidget {
  final String hlsUrl;
  final bool autoPlay;
  final VoidCallback? onLive;

  const AdaptiveStreamPlayer({
    super.key,
    required this.hlsUrl,
    this.autoPlay = true,
    this.onLive,
  });

  @override
  State<AdaptiveStreamPlayer> createState() => _AdaptiveStreamPlayerState();
}

class _AdaptiveStreamPlayerState extends State<AdaptiveStreamPlayer> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _error;
  bool _isRetrying = false;
  int _retryCount = 0;
  static const int _maxRetries = 5;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.hlsUrl),
        httpHeaders: {
          'Connection': 'keep-alive',
        },
      );

      await _videoController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: widget.autoPlay,
        looping: false,
        showControls: true,
        allowFullScreen: true,
        allowMuting: true,
        // Adaptive quality - let the player handle it
        allowPlaybackSpeedChanging: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.red,
          handleColor: Colors.redAccent,
          bufferedColor: Colors.grey[300]!,
        ),
      );

      // Listen for live status
      _videoController.addListener(_onVideoProgress);

      setState(() {
        _isLoading = false;
        _retryCount = 0;
      });

      widget.onLive?.call();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });

      // Auto-retry on network errors (common in Zambia)
      if (_retryCount < _maxRetries && !_isRetrying) {
        _scheduleRetry();
      }
    }
  }

  void _scheduleRetry() {
    _isRetrying = true;
    _retryCount++;

    // Exponential backoff: 2s, 4s, 8s, 16s, 32s
    final delay = Duration(seconds: 2 * (1 << (_retryCount - 1)));

    Future.delayed(delay, () {
      if (mounted) {
        _isRetrying = false;
        _initPlayer();
      }
    });
  }

  void _onVideoProgress() {
    // Check if stream is live (near the end)
    if (_videoController.value.isInitialized) {
      final position = _videoController.value.position;
      final duration = _videoController.value.duration;

      // If we're within 10 seconds of the end, it's live
      if (duration - position < Duration(seconds: 10)) {
        widget.onLive?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Connecting to stream...',
              style: TextStyle(color: Colors.white70),
            ),
            if (_retryCount > 0)
              Text(
                'Retry $_retryCount/$_maxRetries',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red[300], size: 48),
            SizedBox(height: 16),
            Text(
              'Stream unavailable',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'Check your connection and try again',
              style: TextStyle(color: Colors.white54),
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _retryCount = 0;
                _initPlayer();
              },
              icon: Icon(Icons.refresh),
              label: Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_chewieController == null) {
      return Center(child: Text('Player not ready'));
    }

    return Chewie(controller: _chewieController!);
  }

  @override
  void dispose() {
    _videoController.removeListener(_onVideoProgress);
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }
}

/// Connection quality indicator for low-bandwidth users
class ConnectionQualityIndicator extends StatefulWidget {
  final String hlsUrl;

  const ConnectionQualityIndicator({super.key, required this.hlsUrl});

  @override
  State<ConnectionQualityIndicator> createState() => _ConnectionQualityIndicatorState();
}

class _ConnectionQualityIndicatorState extends State<ConnectionQualityIndicator> {
  String _quality = 'checking';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _timer = Timer.periodic(Duration(seconds: 30), (_) => _checkConnection());
  }

  Future<void> _checkConnection() async {
    try {
      final start = DateTime.now();
      final request = await HttpClient().getUrl(Uri.parse(widget.hlsUrl));
      await request.close();
      final duration = DateTime.now().difference(start).inMilliseconds;

      if (!mounted) return;

      setState(() {
        if (duration < 500) {
          _quality = 'excellent';
        } else if (duration < 1500) {
          _quality = 'good';
        } else if (duration < 3000) {
          _quality = 'fair';
        } else {
          _quality = 'poor';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _quality = 'offline');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getColor().withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIcon(),
            size: 14,
            color: _getColor(),
          ),
          SizedBox(width: 4),
          Text(
            _getLabel(),
            style: TextStyle(
              fontSize: 11,
              color: _getColor(),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor() {
    switch (_quality) {
      case 'excellent':
        return Colors.green;
      case 'good':
        return Colors.blue;
      case 'fair':
        return Colors.orange;
      case 'poor':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getIcon() {
    switch (_quality) {
      case 'excellent':
        return Icons.signal_cellular_4_bar;
      case 'good':
        return Icons.signal_cellular_alt;
      case 'fair':
        return Icons.signal_cellular_alt_2_bar;
      case 'poor':
        return Icons.signal_cellular_alt_1_bar;
      default:
        return Icons.signal_cellular_off;
    }
  }

  String _getLabel() {
    switch (_quality) {
      case 'excellent':
        return 'HD';
      case 'good':
        return 'SD';
      case 'fair':
        return 'Low';
      case 'poor':
        return 'Very Low';
      default:
        return 'Checking...';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
