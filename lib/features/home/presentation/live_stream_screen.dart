import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';

import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/branded_stream_poster.dart';
import 'package:church_on_app/core/widgets/marquee_ticker.dart';
import '../../finance/presentation/giving_screen.dart';
import 'package:church_on_app/features/media/data/transcript_service.dart';
import 'package:church_on_app/features/media/presentation/transcribe_action.dart';
import 'package:church_on_app/features/media/presentation/widgets/captions_overlay.dart';
import 'package:church_on_app/features/admin/data/reporting_service.dart';
import 'package:church_on_app/features/modules/live_streaming/data/stream_analytics_service.dart';
import 'package:church_on_app/features/modules/live_streaming/data/live_stream_overlay_service.dart';
import 'package:church_on_app/features/modules/live_streaming/data/live_stream_service.dart';
import 'package:church_on_app/features/modules/live_streaming/presentation/stream_projector_screen.dart';
import '../data/live_chat_service.dart';
import '../../../core/providers/profile_provider.dart';

/// Why the player has (or has not) reached playback. A single explicit state
/// removes the "spinner forever" class of bug: the UI can only show the spinner
/// while `loading`, and every exit path (initialized, invalid URL, thrown error,
/// or watchdog timeout) moves to `ready` or `error`.
enum _PlayerPhase { loading, ready, error }

class LiveStreamScreen extends ConsumerStatefulWidget {
  final String streamUrl;
  final String title;
  /// `live_streams.id` — used for viewer counting, overlays and analytics.
  final String? streamId;

  /// Tenant id — lets the viewer resolve the live row when the caller only had
  /// a (possibly stale/empty) `church_live_status.stream_url`.
  final String? churchId;

  /// Audio-only broadcast (no camera on the publisher side).
  final bool isAudioOnly;

  /// Poster/thumbnail shown before playback starts.
  final String? thumbnailUrl;

  const LiveStreamScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.streamId,
    this.churchId,
    this.isAudioOnly = false,
    this.thumbnailUrl,
  });

  @override
  ConsumerState<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends ConsumerState<LiveStreamScreen> {
  static const _initTimeout = Duration(seconds: 20);
  static const _shareUrl = 'https://churchonapp.com/live-streaming';

  /// How many times the player silently re-attempts before RETRY is offered.
  static const _maxAutoRetries = 2;

  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  _PlayerPhase _phase = _PlayerPhase.loading;
  Timer? _initWatchdog;
  Timer? _retryTimer;
  bool _isReplay = false;
  bool _reconnecting = false;
  String? _resolvedPlaybackUrl;

  /// Mutable ids — resolved from `churchId` when the caller had no streamId.
  String? _effectiveStreamId;

  /// Real server-side state, used to distinguish "starting" from "offline".
  String? _rowStatus;
  bool _inputConnected = false;

  /// Auto-retry bookkeeping.
  int _autoRetries = 0;
  int _totalFailures = 0;
  String? _statusNote;

  int _viewerCount = 0;
  int _peakViewers = 0;
  Timer? _viewerTimer;

  /// Viewer-side toggle: hide all on-screen overlays (verse/speaker/caption).
  bool _overlaysHidden = false;

  /// Guards the archive fallback so it is attempted at most once per stream.
  String? _archiveTriedFor;

  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Viewing-session analytics.
  late final StreamAnalyticsService _analytics;
  String? _sessionId;
  DateTime? _joinedAt;
  Timer? _heartbeat;
  bool _sessionEnded = false;

  @override
  void initState() {
    super.initState();
    _analytics = ref.read(streamAnalyticsServiceProvider);
    _resolveAndInitialize();
  }

  bool _isValidUrl(String url) =>
      url.isNotEmpty &&
      !url.contains('/null/') &&
      (url.startsWith('http://') || url.startsWith('https://'));

  /// The viewer may be opened with a stale/empty URL (e.g. a push notification
  /// or a home card carrying only the tenant). Resolve the real playback URL
  /// from the row before handing it to the player.
  Future<void> _resolveAndInitialize() async {
    _effectiveStreamId ??=
        (widget.streamId != null && widget.streamId!.isNotEmpty)
            ? widget.streamId
            : null;

    var url = widget.streamUrl.trim();
    if (_effectiveStreamId == null || !_isValidUrl(url)) {
      // Repair path runs AUTOMATICALLY on open (not only after a failure): ask
      // Cloudflare for the live input's real status + a fresh HLS URL so a
      // newly-created stream (whose row predates the manifest) still plays.
      await _loadRow(allowHttpRefresh: true);
      url = _resolvedPlaybackUrl ?? url;
    }
    if (!mounted) return;
    _startSession();
    _startViewerCount();
    await _initializePlayer(overrideUrl: url);
  }

  /// Loads/refreshes the `live_streams` row for this stream, updating the row
  /// status + resolved playback URL. When [allowHttpRefresh] is set it also
  /// asks the Edge Function to repair a stale/empty `hls_url` from Cloudflare
  /// and reports whether the live input is actually connected.
  Future<void> _loadRow({required bool allowHttpRefresh}) async {
    final service = ref.read(liveStreamServiceProvider);
    try {
      if ((_effectiveStreamId == null || _effectiveStreamId!.isEmpty) &&
          widget.churchId != null &&
          widget.churchId!.isNotEmpty) {
        final row = await service.getActiveStreamForChurch(widget.churchId!);
        final id = row?['id']?.toString();
        if (id != null && id.isNotEmpty) _effectiveStreamId = id;
        _applyRow(row);
      } else if (_effectiveStreamId != null && _effectiveStreamId!.isNotEmpty) {
        _applyRow(await service.getStream(_effectiveStreamId!));
      }

      if (allowHttpRefresh &&
          _effectiveStreamId != null &&
          _effectiveStreamId!.isNotEmpty) {
        final info = await service.refreshPlayback(_effectiveStreamId!);
        if (info != null && info.success) {
          _inputConnected = info.connected;
          final hls = info.hlsUrl;
          if (hls != null && _isValidUrl(hls)) _resolvedPlaybackUrl = hls;
        }
      }
    } catch (e) {
      debugPrint('LiveStream: could not resolve stream row: $e');
    }
  }

  void _applyRow(Map<String, dynamic>? row) {
    if (row == null) return;
    _rowStatus = row['status']?.toString();
    final hls = row['hls_url']?.toString() ?? '';
    final archive = row['archive_url']?.toString() ?? '';
    if (_isValidUrl(hls)) {
      _resolvedPlaybackUrl = hls;
    } else if (_isValidUrl(archive)) {
      _resolvedPlaybackUrl = archive;
      _isReplay = true;
    }
  }

  bool get _isLiveRow => _rowStatus == 'live';

  Future<void> _initializePlayer({String? overrideUrl}) async {
    final url =
        (overrideUrl ?? _resolvedPlaybackUrl ?? widget.streamUrl).trim();

    if (!_isValidUrl(url)) {
      debugPrint('LiveStream: refusing invalid stream URL: "$url"');
      await _handlePlaybackFailure();
      return;
    }

    _initWatchdog?.cancel();
    if (mounted) {
      setState(() {
        _phase = _PlayerPhase.loading;
        _reconnecting = false;
      });
    }

    // Tear down any previous attempt before starting a new one.
    final oldChewie = _chewieController;
    final oldVideo = _videoPlayerController;
    _chewieController = null;
    _videoPlayerController = null;
    _retryTimer?.cancel();
    try {
      oldChewie?.dispose();
    } catch (_) {}
    try {
      oldVideo?.removeListener(_onPlayerChanged);
      oldVideo?.dispose();
    } catch (_) {}

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoPlayerController = controller;
      _resolvedPlaybackUrl = url;
      controller.addListener(_onPlayerChanged);

      _startWatchdog();

      await controller.initialize();
      _initWatchdog?.cancel();
      if (!mounted) return;

      // Some platforms resolve `initialize()` without throwing but never reach
      // `isInitialized` (404/empty HLS/manifest). This was the silent spinner.
      if (!controller.value.isInitialized) {
        debugPrint('LiveStream: initialize() completed but isInitialized=false');
        await _handlePlaybackFailure();
        return;
      }

      _buildChewie(controller, url);
    } catch (e) {
      _initWatchdog?.cancel();
      debugPrint('LiveStream init error: $e');
      await _handlePlaybackFailure();
    }
  }

  /// Called whenever playback cannot start. Re-resolves the row + asks
  /// Cloudflare for the real state, retries silently a couple of times with
  /// backoff, and only then surfaces the RETRY state — with copy that matches
  /// the actual server-side state (scheduled / starting / genuinely offline).
  Future<void> _handlePlaybackFailure() async {
    if (!mounted || _phase == _PlayerPhase.ready) return;
    _totalFailures++;
    if (_totalFailures > 8) {
      // A live row must NEVER be given up on: the input may simply not have
      // connected yet. Reconcile once more, then keep retrying slowly and keep
      // the "starting" copy. Only a genuinely ended/unknown row (no URL at all)
      // gets the terminal error state.
      await _loadRow(allowHttpRefresh: true);
      if (!mounted) return;
      final canRetry = _isLiveRow ||
          (_rowStatus == null && _resolvedPlaybackUrl != null);
      if (canRetry) {
        setState(() {
          _phase = _PlayerPhase.loading;
          _statusNote = 'Stream is starting — reconnecting…';
        });
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 30), () {
          if (!mounted) return;
          _initializePlayer(overrideUrl: _resolvedPlaybackUrl);
        });
        return;
      }
      setState(() => _phase = _PlayerPhase.error);
      return;
    }

    // 1) Reconcile with the server (repairs a stale/empty hls_url + real state).
    final previousUrl = _resolvedPlaybackUrl;
    await _loadRow(allowHttpRefresh: true);
    if (!mounted) return;

    final fresh = _resolvedPlaybackUrl;
    if (fresh != null && _isValidUrl(fresh) && fresh != previousUrl) {
      _autoRetries = 0;
      await _initializePlayer(overrideUrl: fresh);
      return;
    }

    // 2) Archive fallback for finished services.
    if (await _tryArchiveFallback()) return;
    if (!mounted) return;

    // 3) Silent auto-retry with backoff before ever exposing RETRY.
    if (_autoRetries < _maxAutoRetries) {
      _autoRetries++;
      final delay = Duration(seconds: 3 * _autoRetries);
      if (mounted) {
        setState(() {
          _phase = _PlayerPhase.loading;
          _statusNote = _isLiveRow
              ? 'Stream is starting — reconnecting…'
              : 'Reconnecting…';
        });
      }
      _retryTimer?.cancel();
      _retryTimer = Timer(delay, () {
        if (!mounted) return;
        _initializePlayer(overrideUrl: _resolvedPlaybackUrl);
      });
      return;
    }

    // 4) Give up → state-specific error copy (never "offline" while live).
    if (mounted) setState(() => _phase = _PlayerPhase.error);
  }

  void _buildChewie(VideoPlayerController controller, String url) {
    _resolvedPlaybackUrl = url;
    _chewieController = ChewieController(
      videoPlayerController: controller,
      autoPlay: true,
      looping: false,
      isLive: !_isReplay,
      aspectRatio: controller.value.aspectRatio == 0
          ? 16 / 9
          : controller.value.aspectRatio,
      placeholder: SmartStreamPoster(
        url: widget.thumbnailUrl,
        seed: widget.streamId ?? widget.title,
        fit: BoxFit.cover,
      ),
      materialProgressColors: ChewieProgressColors(
        playedColor: const Color(0xFFFFD700),
        handleColor: const Color(0xFFFFD700),
        backgroundColor: Colors.grey,
        bufferedColor: Colors.white.withValues(alpha: 0.3),
      ),
    );
    if (mounted) {
      setState(() {
        _phase = _PlayerPhase.ready;
        _reconnecting = false;
        _autoRetries = 0;
        _totalFailures = 0;
        _statusNote = null;
      });
    }
  }

  /// Watchdog: guarantees the loading spinner can never spin forever. If the
  /// controller is actually initialized we promote to ready; otherwise we
  /// reconcile with the server + retry, and finally surface the error state.
  void _startWatchdog() {
    _initWatchdog?.cancel();
    _initWatchdog = Timer(_initTimeout, () async {
      if (!mounted || _phase != _PlayerPhase.loading) return;
      final controller = _videoPlayerController;
      if (controller != null && controller.value.isInitialized) {
        _buildChewie(controller, _resolvedPlaybackUrl ?? '');
        return;
      }
      debugPrint('LiveStream: init watchdog fired after ${_initTimeout.inSeconds}s');
      await _handlePlaybackFailure();
    });
  }

  void _onPlayerChanged() {
    final controller = _videoPlayerController;
    if (controller == null || !mounted || _phase != _PlayerPhase.ready) return;
    final value = controller.value;
    if (value.hasError) {
      if (!_reconnecting) setState(() => _reconnecting = true);
    } else if (_reconnecting && value.isInitialized) {
      setState(() => _reconnecting = false);
    }
  }

  /// Resolves and plays the R2 master archive for this stream. Returns true if
  /// an archive was found and playback restarted from it.
  Future<bool> _tryArchiveFallback() async {
    final id = _effectiveStreamId;
    if (id == null || id.isEmpty || _archiveTriedFor == id) return false;
    _archiveTriedFor = id;
    try {
      final archive = await ref.read(liveStreamServiceProvider).getArchiveUrl(id);
      if (archive == null || archive.isEmpty) return false;
      if (!mounted) return false;
      setState(() {
        _isReplay = true;
        _phase = _PlayerPhase.loading;
      });
      await _initializePlayer(overrideUrl: archive);
      return true;
    } catch (e) {
      debugPrint('LiveStream archive fallback failed: $e');
      return false;
    }
  }

  Future<void> _startSession() async {
    final streamId = _effectiveStreamId;
    if (streamId == null || streamId.isEmpty || _sessionId != null) return;
    _joinedAt = DateTime.now();
    _sessionId = await _analytics.startSession(streamId);
    if (_sessionId == null) return;
    // Heartbeat so a killed/backgrounded app still records partial watch time
    // and is not mistaken for a stale viewer.
    _heartbeat = Timer.periodic(const Duration(seconds: 45), (_) async {
      final id = _sessionId;
      if (id == null) return;
      await _analytics.heartbeatSession(id);
    });
  }

  int get _watchedSeconds =>
      _joinedAt == null ? 0 : DateTime.now().difference(_joinedAt!).inSeconds;

  Future<void> _flushSession() async {
    final id = _sessionId;
    if (id == null || _sessionEnded) return;
    _sessionEnded = true;
    await _analytics.endSession(id, _watchedSeconds);
  }

  /// Live viewer count — the RPC recomputes presence server-side and returns
  /// both the current audience and the peak.
  void _startViewerCount() {
    final id = _effectiveStreamId;
    if (id == null || id.isEmpty) return;
    _viewerTimer?.cancel();

    Future<void> poll() async {
      // Read-only: the streamer + each session open/close republish the count.
      final res = await _analytics.getViewerCount(id);
      if (res == null || !mounted) return;
      setState(() {
        _viewerCount = res.count;
        if (res.peak > _peakViewers) _peakViewers = res.peak;
      });
    }

    poll();
    _viewerTimer = Timer.periodic(const Duration(seconds: 15), (_) => poll());
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _viewerTimer?.cancel();
    _initWatchdog?.cancel();
    _retryTimer?.cancel();
    unawaited(_flushSession());
    _videoPlayerController?.removeListener(_onPlayerChanged);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tenant = ref.watch(currentTenantProvider);
    final overlay = _watchOverlay();
    final reports = (tenant == null
            ? const <ServiceReport>[]
            : (ref.watch(reportsStreamProvider(tenant.id)).value ?? const <ServiceReport>[]))
        .where((r) => r.type == 'announcement')
        .toList();
    final tickerItems = _tickerItems(overlay, reports);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
          ),
        ),
        actions: [
          if (_phase != _PlayerPhase.error) ...[
            if (_viewerCount > 0 && !_isReplay)
              _pill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.eye, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text('$_viewerCount',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  ],
                ),
              ),
            _pill(
              color: _isReplay ? Colors.black54 : Colors.red,
              child: Text(
                _isReplay ? "REPLAY" : "LIVE",
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            IconButton(
              tooltip: _overlaysHidden ? 'Show overlays' : 'Hide overlays',
              icon: Icon(
                _overlaysHidden ? LucideIcons.eyeOff : LucideIcons.eye,
                color: Colors.white,
              ),
              onPressed: () => setState(() => _overlaysHidden = !_overlaysHidden),
            ),
            IconButton(
              tooltip: 'Projector / Big screen',
              icon: const Icon(LucideIcons.monitor, color: Colors.white),
              onPressed: () => _openProjector(tenant),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildVideoArea(overlay, tickerItems),
          ),
          Expanded(child: _buildInfoPanel(theme, tenant, overlay, reports)),
        ],
      ),
    );
  }

  Widget _pill({required Widget child, Color color = const Color(0x8C000000)}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Center(child: child),
    );
  }

  Widget _buildVideoArea(LiveStreamOverlay? overlay, List<String> tickerItems) {
    final ready = _phase == _PlayerPhase.ready;
    final showOverlays = ready && !_overlaysHidden;
    final showTicker = tickerItems.isNotEmpty && ready && !_overlaysHidden;
    final showSpeaker = showOverlays &&
        overlay != null &&
        (overlay.hasSpeaker || overlay.hasCaption);
    final showVerse = showOverlays && overlay != null && overlay.hasVerse;
    final streamId = _effectiveStreamId;
    final transcript = (streamId != null && streamId.isNotEmpty)
        ? ref.watch(liveStreamTranscriptProvider(streamId)).value
        : null;
    final captionsOn = ref.watch(captionsEnabledProvider);
    final position = _videoPlayerController?.value.position ?? Duration.zero;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildVideoStage(),
        if (ready)
          Positioned(top: 8, left: 8, child: _healthChip()),
        // Auto-captions from the Whisper transcript (CC toggle persisted).
        CaptionsOverlay(
          transcript: transcript,
          position: position,
          enabled: captionsOn,
          bottomInset: showTicker ? 44 : 10,
        ),
        if (showOverlays)
          Positioned(
            bottom: 6,
            right: 6,
            child: Row(
              children: [
                const CcToggleButton(),
                if (streamId != null && streamId.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  TranscribeAction(liveStreamId: streamId),
                ],
              ],
            ),
          ),
        if (showVerse)
          Positioned(
            left: 10,
            right: 10,
            bottom: showTicker ? 34 : 10,
            child: _verseOverlayCard(overlay),
          ),
        if (showSpeaker)
          Positioned(
            left: 10,
            right: 10,
            top: 40,
            child: _speakerOverlayCard(overlay),
          ),
        if (showTicker)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MarqueeTicker(
              items: tickerItems,
              pixelsPerSecond: (overlay?.tickerSpeed ?? 40).toDouble(),
            ),
          ),
      ],
    );
  }

  /// Speaker lower-third + editable caption. Always rendered over a dark,
  /// shadowed backdrop so it is legible on any video (never white-on-white).
  Widget _speakerOverlayCard(LiveStreamOverlay overlay) {
    final name = overlay.speakerName?.trim() ?? '';
    final title = overlay.speakerTitle?.trim() ?? '';
    final church = overlay.speakerChurch?.trim() ?? '';
    final caption = overlay.caption?.trim() ?? '';
    final subtitle =
        [title, church].where((e) => e.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (caption.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
            ),
          ),
        if (name.isNotEmpty || subtitle.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(12),
              border: const Border(
                left: BorderSide(color: Color(0xFFFFD700), width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (name.isNotEmpty)
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                    ),
                  ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildVideoStage() {
    switch (_phase) {
      case _PlayerPhase.error:
        return _buildErrorState();
      case _PlayerPhase.ready:
        final chewie = _chewieController;
        if (chewie != null && chewie.videoPlayerController.value.isInitialized) {
          return Chewie(controller: chewie);
        }
        return _buildErrorState();
      case _PlayerPhase.loading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFFFD700)),
              if (_statusNote != null) ...[
                const SizedBox(height: 14),
                Text(
                  _statusNote!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }

  Widget _healthChip() {
    if (_reconnecting) {
      return _chip('RECONNECTING…', Colors.orangeAccent);
    }
    final value = _videoPlayerController?.value;
    if (value == null) return _chip('CONNECTING…', Colors.white70);
    final h = value.size.height.round();
    final res = h > 0 ? '${value.size.width.round()}×$h' : 'AUTO';
    return _chip(value.isBuffering ? 'BUFFERING · $res' : 'LIVE · $res', Colors.white70);
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _verseOverlayCard(LiveStreamOverlay overlay) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.bookOpen, color: Color(0xFFFFD700), size: 13),
              const SizedBox(width: 6),
              if ((overlay.verseRef ?? '').trim().isNotEmpty)
                Expanded(
                  child: Text(
                    overlay.verseRef!.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
          if ((overlay.verseText ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '"${overlay.verseText}"',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.35,
                fontStyle: FontStyle.italic,
                shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    // Copy must reflect the REAL server-side state — never claim "offline"
    // while the stream row is actually live.
    final scheduled = _rowStatus == 'scheduled';
    final live = _isLiveRow;
    final starting = live && !_inputConnected;

    final IconData icon;
    final String title;
    final String message;
    if (scheduled) {
      icon = LucideIcons.calendarClock;
      title = "Stream hasn't started";
      message = 'This service is scheduled and has not gone live yet. '
          'Please check back when the broadcast begins.';
    } else if (starting) {
      icon = LucideIcons.radioReceiver;
      title = 'Stream is starting…';
      message = 'The church is live, but the video feed is still connecting. '
          'Hang tight — we will reconnect automatically.';
    } else if (live) {
      icon = LucideIcons.wifiOff;
      title = 'Playback problem';
      message = 'This service is live, but the video could not load on your '
          'connection. Tap retry.';
    } else if (_rowStatus == null && _resolvedPlaybackUrl != null) {
      // We have a playback URL but the row state could not be read — this is a
      // transient playback problem, never an "invalid link".
      icon = LucideIcons.wifiOff;
      title = 'Playback problem';
      message = 'The video could not load yet. Check your connection and tap '
          'retry — we reconnect automatically.';
    } else {
      icon = LucideIcons.videoOff;
      title = 'Stream has ended';
      message = 'This broadcast is over. Check the recordings or join the next '
          'live service.';
    }

    return Container(
      color: Colors.black87,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.redAccent, size: 36),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _phase = _PlayerPhase.loading;
                _archiveTriedFor = null;
                _reconnecting = false;
                _autoRetries = 0;
                _totalFailures = 0;
                _statusNote = null;
              });
              _resolveAndInitialize();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFFFD700)),
            ),
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(
    ThemeData theme,
    Tenant? tenant,
    LiveStreamOverlay? overlay,
    List<ServiceReport> announcements,
  ) {
    final scheme = theme.colorScheme;
    final onSurface = scheme.onSurface;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child: AppImage(tenant?.logoUrl ?? '',
                    width: 40, height: 40, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tenant?.name ?? "Church",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: onSurface, fontWeight: FontWeight.bold)),
                    Text(
                      _isReplay
                          ? "Recorded service"
                          : (_viewerCount > 0
                              ? '$_viewerCount watching · Join the community'
                              : "Join the community"),
                      style: TextStyle(
                          color: onSurface.withValues(alpha: 0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cast to a TV',
                icon: Icon(LucideIcons.cast, color: onSurface.withValues(alpha: 0.8)),
                onPressed: () => _showCastPanel(context),
              ),
              IconButton(
                tooltip: 'Share',
                icon: Icon(LucideIcons.share2, color: onSurface.withValues(alpha: 0.8)),
                onPressed: _showShareSheet,
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (context) => const GivingScreen()));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("GIVE",
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 11)),
              ),
            ],
          ),
          if (announcements.isNotEmpty) ...[
            const SizedBox(height: 14),
            _announcementStrip(theme, announcements.first),
          ],
          const SizedBox(height: 14),
          Text("LIVE CHAT",
              style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontSize: 12)),
          const SizedBox(height: 10),
          Expanded(child: _buildChatMessages(theme, tenant)),
          _buildChatInput(theme, tenant),
        ],
      ),
    );
  }

  Widget _announcementStrip(ThemeData theme, ServiceReport latest) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.megaphone, color: Color(0xFFB8860B), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("LATEST ANNOUNCEMENT",
                    style: TextStyle(
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF7A5C00),
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
                Text(latest.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Chat — theme-aware palette (readable in light AND dark themes)
  // ---------------------------------------------------------------------------

  Widget _buildChatMessages(ThemeData theme, Tenant? tenant) {
    if (tenant == null) {
      return Center(
          child: Text("Select a church to chat",
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))));
    }

    final chatAsync = ref.watch(liveChatStreamProvider(tenant.id));

    return chatAsync.when(
      data: (messages) {
        if (messages.isEmpty) {
          return Center(
            child: Text("No messages yet. Be the first to chat!",
                style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    fontSize: 12)),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });

        return ListView.builder(
          controller: _scrollCtrl,
          itemCount: messages.length,
          itemBuilder: (context, index) => _buildChatMessage(theme, messages[index]),
        );
      },
      loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD700))),
      error: (e, _) => Center(
          child: Text("Chat unavailable",
              style: TextStyle(color: theme.colorScheme.error, fontSize: 11))),
    );
  }

  Widget _buildChatMessage(ThemeData theme, LiveChatMessage msg) {
    // Explicit, high-contrast palette (independent of a mis-tuned ColorScheme)
    // so chat text can never render white-on-white in either theme.
    final isDark = theme.brightness == Brightness.dark;
    final bubble = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final senderColor = isDark ? const Color(0xFFFFD700) : const Color(0xFF7A5C00);
    final timeColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final time = DateFormat('HH:mm').format(msg.createdAt.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: border),
            ),
            child: ClipOval(
              child: AppImage(msg.senderPhoto ?? '',
                  width: 22, height: 22, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: bubble,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          msg.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: senderColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        time,
                        style: TextStyle(
                          color: timeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    msg.text,
                    style: TextStyle(color: textColor, fontSize: 13, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput(ThemeData theme, Tenant? tenant) {
    final isDark = theme.brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final hintColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatCtrl,
              cursorColor: const Color(0xFFFFD700),
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: "Say something...",
                hintStyle: TextStyle(color: hintColor),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onSubmitted: (_) => _handleSendMessage(tenant),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.send, color: Color(0xFFFFD700), size: 20),
            onPressed: () => _handleSendMessage(tenant),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSendMessage(Tenant? tenant) async {
    if (tenant == null || _chatCtrl.text.trim().isEmpty) return;

    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    final message = _chatCtrl.text.trim();
    _chatCtrl.clear();

    try {
      await ref.read(liveChatServiceProvider).sendLiveMessage(
            tenantId: tenant.id,
            content: message,
            userName: profile.name,
            userPhoto: profile.avatarUrl ?? '',
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Failed to send message")));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Overlays / ticker
  // ---------------------------------------------------------------------------

  LiveStreamOverlay? _watchOverlay() {
    final id = _effectiveStreamId;
    if (id == null || id.isEmpty) return null;
    return ref.watch(liveStreamOverlayProvider(id)).value;
  }

  List<String> _tickerItems(
      LiveStreamOverlay? overlay, List<ServiceReport> announcements) {
    final items = <String>[];
    if (overlay != null &&
        overlay.tickerEnabled &&
        (overlay.tickerMessage ?? '').trim().isNotEmpty) {
      items.add(overlay.tickerMessage!.trim());
    }
    if (overlay != null && overlay.hasVerse) {
      final verse = [overlay.verseRef, overlay.verseText]
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' — ');
      if (verse.isNotEmpty) items.add('📖 $verse');
    }
    if (overlay != null && overlay.hasSpeaker) {
      final speaker = [
        overlay.speakerName,
        overlay.speakerTitle,
        overlay.speakerChurch,
      ]
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' · ');
      if (speaker.isNotEmpty) items.add('🎤 $speaker');
    }
    for (final a in announcements.take(3)) {
      if (a.title.trim().isNotEmpty) items.add('📣 ${a.title.trim()}');
    }
    return items;
  }

  // ---------------------------------------------------------------------------
  // Streaming extras (provider-neutral)
  // ---------------------------------------------------------------------------

  void _openProjector(Tenant? tenant) {
    final id = _effectiveStreamId;
    // `ref.read` (not watch) — this runs from a callback, outside build.
    final overlay = (id == null || id.isEmpty)
        ? null
        : ref.read(liveStreamOverlayProvider(id)).value;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StreamProjectorScreen(
          title: widget.title,
          hlsUrl: _resolvedPlaybackUrl,
          streamId: _effectiveStreamId,
          tenantName: tenant?.name,
          logoUrl: overlay?.logoUrl ?? tenant?.logoUrl,
        ),
      ),
    );
  }

  /// Chromecast/AirPlay: no cast package is bundled, so we surface the public
  /// HLS link + clear OS/browser cast guidance (never vendor-locked).
  void _showCastPanel(BuildContext context) {
    final url = _resolvedPlaybackUrl ?? widget.streamUrl;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cast to your TV',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Open the playback link below in Chrome (Cast), Safari (AirPlay) or '
              'your phone/OS screen-mirror, then pick your TV or projector. Any HLS '
              'player works — no account or app lock-in.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 16),
            _copyRow(ctx, 'Playback (HLS) link', url),
            const SizedBox(height: 12),
            _copyRow(ctx, 'Share link', _shareUrl),
          ],
        ),
      ),
    );
  }

  void _showShareSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this service',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: _shareUrl,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(_shareUrl, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: _shareUrl));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share link copied')),
                  );
                }
              },
              icon: const Icon(LucideIcons.copy, size: 16),
              label: const Text('COPY SHARE LINK'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _copyRow(BuildContext context, String label, String value) {
    final hasValue = value.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                SelectableText(
                  hasValue ? value : 'Wait for the stream to go live…',
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.copy, size: 18),
            onPressed: hasValue
                ? () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$label copied')),
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
