import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:church_on_app/core/services/tenant_service.dart';
import '../../finance/presentation/giving_screen.dart';
import 'package:church_on_app/features/admin/data/reporting_service.dart';
import 'package:church_on_app/features/modules/live_streaming/data/stream_analytics_service.dart';
import 'package:church_on_app/features/modules/live_streaming/data/live_stream_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/live_chat_service.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/widgets/app_image.dart';
import 'dart:async';

class LiveStreamScreen extends ConsumerStatefulWidget {
  final String streamUrl;
  final String title;
  /// `live_streams.id` — used to record a viewing session for analytics.
  /// Optional so older call sites keep compiling.
  final String? streamId;

  /// Audio-only broadcast (no camera on the publisher side).
  final bool isAudioOnly;

  /// Poster/thumbnail shown before playback starts.
  final String? thumbnailUrl;

  const LiveStreamScreen({
    super.key, 
    required this.streamUrl,
    required this.title,
    this.streamId,
    this.isAudioOnly = false,
    this.thumbnailUrl,
  });

  @override
  ConsumerState<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends ConsumerState<LiveStreamScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _hasError = false;
  /// True once playback has fallen back to the R2 archive of a finished stream.
  bool _isReplay = false;
  int _viewerCount = 0;
  Timer? _viewerTimer;
  /// Guards the archive fallback so it is attempted at most once per stream.
  String? _archiveTriedFor;
  /// R2 master URL once the archive fallback has resolved.
  String? _archiveUrl;
  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Viewing-session analytics.
  String? _sessionId;
  DateTime? _joinedAt;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _startSession();
    _startViewerCount();
  }

  Future<void> _startSession() async {
    final streamId = widget.streamId;
    if (streamId == null || streamId.isEmpty) return;
    _joinedAt = DateTime.now();
    _sessionId = await ref
        .read(streamAnalyticsServiceProvider)
        .startSession(streamId);
    // Heartbeat so a killed app still records partial watch time.
    _heartbeat = Timer.periodic(const Duration(minutes: 1), (_) => _flushSession());
  }

  int get _watchedSeconds =>
      _joinedAt == null ? 0 : DateTime.now().difference(_joinedAt!).inSeconds;

  /// Live viewer count — polled while the stream is open so the badge reflects
  /// the real audience without extra realtime wiring.
  void _startViewerCount() {
    final id = widget.streamId;
    if (id == null || id.isEmpty) return;
    Future<void> poll() async {
      try {
        final row = await Supabase.instance.client
            .from('live_streams')
            .select('viewer_count')
            .eq('id', id)
            .maybeSingle();
        final c = (row?['viewer_count'] as num?)?.toInt() ?? 0;
        if (mounted && c != _viewerCount) setState(() => _viewerCount = c);
      } catch (_) {}
    }

    poll();
    _viewerTimer = Timer.periodic(const Duration(seconds: 30), (_) => poll());
  }

  Future<void> _flushSession() async {
    final id = _sessionId;
    if (id == null) return;
    await ref.read(streamAnalyticsServiceProvider).endSession(id, _watchedSeconds);
  }

  Future<void> _initializePlayer({String? overrideUrl}) async {
    final url = (overrideUrl ?? _archiveUrl ?? widget.streamUrl).trim();
    final invalid = url.isEmpty ||
        url.contains('/null/') ||
        (!url.startsWith('http://') && !url.startsWith('https://'));
    if (invalid) {
      debugPrint('LiveStream: refusing invalid stream URL: "$url"');
      // The Cloudflare recording may be gone (retention expired) but the R2
      // master may still be playable — prefer it, then surface RETRY.
      if (overrideUrl == null && await _tryArchiveFallback()) return;
      if (mounted) setState(() => _hasError = true);
      return;
    }
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        isLive: !_isReplay,
        aspectRatio: _videoPlayerController!.value.aspectRatio == 0
            ? 16 / 9
            : _videoPlayerController!.value.aspectRatio,
        placeholder: (widget.thumbnailUrl != null &&
                widget.thumbnailUrl!.isNotEmpty)
            ? AppImage(widget.thumbnailUrl!, fit: BoxFit.cover)
            : Container(color: Colors.black),
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFFFFD700),
          handleColor: const Color(0xFFFFD700),
          backgroundColor: Colors.grey,
          bufferedColor: Colors.white.withValues(alpha: 0.3),
        ),
      );
      if (mounted) setState(() => _hasError = false);
    } catch (e) {
      debugPrint('LiveStream init error: $e');
      if (overrideUrl == null && await _tryArchiveFallback()) return;
      if (mounted) setState(() => _hasError = true);
    }
  }

  /// Resolves and plays the R2 master archive for this stream. Returns true if
  /// an archive was found and playback restarted from it.
  Future<bool> _tryArchiveFallback() async {
    final id = widget.streamId;
    if (id == null || id.isEmpty || _archiveTriedFor == id) return false;
    _archiveTriedFor = id;
    try {
      final archive = await ref.read(liveStreamServiceProvider).getArchiveUrl(id);
      if (archive == null || archive.isEmpty) return false;
      if (!mounted) return false;
      _archiveUrl = archive;
      setState(() {
        _isReplay = true;
        _hasError = false;
      });
      await _initializePlayer(overrideUrl: archive);
      return true;
    } catch (e) {
      debugPrint('LiveStream archive fallback failed: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _viewerTimer?.cancel();
    _flushSession();
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Widget _buildErrorState() {
    return Container(
      color: Colors.black87,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.videoOff, color: Colors.redAccent, size: 36),
          const SizedBox(height: 12),
          const Text(
            'Stream unavailable',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'This stream is offline or the broadcast link is invalid.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _hasError = false;
                _archiveTriedFor = null;
              });
              _videoPlayerController?.dispose();
              _videoPlayerController = null;
              _chewieController?.dispose();
              _chewieController = null;
              _initializePlayer();
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

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);

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
          if (!_hasError) ...[
            if (_viewerCount > 0 && !_isReplay)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.eye, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text('$_viewerCount',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  ],
                ),
              ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _isReplay ? Colors.black54 : Colors.red,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Center(
                child: Text(
                  _isReplay ? "REPLAY" : "LIVE",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _hasError
                ? _buildErrorState()
                : (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                    ? Chewie(controller: _chewieController!)
                    : const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                    children: [
                       ClipOval(child: AppImage(tenant?.logoUrl ?? '', width: 40, height: 40, fit: BoxFit.cover)),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tenant?.name ?? "Church", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Text(
                            _isReplay
                                ? "Recorded service"
                                : (_viewerCount > 0
                                    ? '$_viewerCount watching · Join the community'
                                    : "Join the community"),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                          ),
                        ],
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const GivingScreen()));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text("GIVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildannouncementTicker(tenant),
                  const SizedBox(height: 20),
                  const Text("LIVE CHAT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
                  const SizedBox(height: 15),
                  Expanded(
                    child: _buildChatMessages(tenant),
                  ),
                  _buildChatInput(tenant),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildannouncementTicker(Tenant? tenant) {
    if (tenant == null) return const SizedBox.shrink();
    final reportsAsync = ref.watch(reportsStreamProvider(tenant.id));

    return reportsAsync.when(
      data: (reports) {
        final announcements = reports.where((r) => r.type == 'announcement').toList();
        if (announcements.isEmpty) return const SizedBox.shrink();
        
        final latest = announcements.first;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.megaphone, color: Colors.amber, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("LATEST ANNOUNCEMENT", style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                    Text(latest.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildChatMessages(Tenant? tenant) {
    if (tenant == null) return const Center(child: Text("Select a church to chat", style: TextStyle(color: Colors.white54)));

    final chatAsync = ref.watch(liveChatStreamProvider(tenant.id));

    return chatAsync.when(
      data: (messages) {
        if (messages.isEmpty) {
          return const Center(child: Text("No messages yet. Be the first to chat!", style: TextStyle(color: Colors.white24, fontSize: 12)));
        }
        
        // Auto scroll to bottom on new messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });

        return ListView.builder(
          controller: _scrollCtrl,
          itemCount: messages.length,
          itemBuilder: (context, index) => _buildChatMessage(messages[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))),
      error: (e, _) => Center(child: Text("Chat unavailable", style: const TextStyle(color: Colors.red, fontSize: 11))),
    );
  }

  Widget _buildChatMessage(LiveChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(child: AppImage(msg.senderPhoto ?? '', width: 16, height: 16, fit: BoxFit.cover)),
          const SizedBox(width: 8),
          Flexible(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, height: 1.4),
                children: [
                  TextSpan(
                    text: '${msg.senderName}: ',
                    style: const TextStyle(
                        color: Color(0xFFFFD700), fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: msg.text,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput(Tenant? tenant) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Expanded(
            // Theme override forces white text/cursor regardless of tenant
            // theming or system dark-mode — typed text was invisible on some
            // devices where the app theme's bodyLarge colour leaked through.
            child: Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: const TextSelectionThemeData(
                  cursorColor: Color(0xFFFFD700),
                  selectionColor: Color(0x33FFD700),
                ),
              ),
              child: TextField(
                controller: _chatCtrl,
                cursorColor: const Color(0xFFFFD700),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
                decoration: const InputDecoration(
                  hintText: "Say something...",
                  hintStyle: TextStyle(color: Colors.white24),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 20),
                ),
                onSubmitted: (_) => _handleSendMessage(tenant),
              ),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to send message")));
      }
    }
  }
}

