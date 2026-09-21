import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/services/unified_stream_service.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/features/home/data/live_streaming_service.dart';
import 'package:church_on_app/features/modules/live_streaming/data/live_stream_overlay_service.dart';
import 'package:church_on_app/features/modules/live_streaming/data/live_stream_service.dart';
import 'package:church_on_app/features/modules/live_streaming/data/stream_analytics_service.dart';
import 'package:church_on_app/features/modules/live_streaming/presentation/stream_projector_screen.dart';

const kKjvBooks = [
  'Genesis','Exodus','Leviticus','Numbers','Deuteronomy','Joshua','Judges',
  'Ruth','1 Samuel','2 Samuel','1 Kings','2 Kings','1 Chronicles','2 Chronicles',
  'Ezra','Nehemiah','Esther','Job','Psalms','Proverbs','Ecclesiastes',
  'Song of Solomon','Isaiah','Jeremiah','Lamentations','Ezekiel','Daniel','Hosea',
  'Joel','Amos','Obadiah','Jonah','Micah','Nahum','Habakkuk','Zephaniah','Haggai',
  'Zechariah','Malachi','Matthew','Mark','Luke','John','Acts','Romans',
  '1 Corinthians','2 Corinthians','Galatians','Ephesians','Philippians',
  'Colossians','1 Thessalonians','2 Thessalonians','1 Timothy','2 Timothy',
  'Titus','Philemon','Hebrews','James','1 Peter','2 Peter','1 John','2 John',
  '3 John','Jude','Revelation',
];

class LiveStreamStudioScreen extends ConsumerStatefulWidget {
  final String? tenantId;
  const LiveStreamStudioScreen({super.key, this.tenantId});

  @override
  ConsumerState<LiveStreamStudioScreen> createState() => _LiveStreamStudioScreenState();
}

class _LiveStreamStudioScreenState extends ConsumerState<LiveStreamStudioScreen> {
  webrtc.MediaStream? _localStream;
  webrtc.RTCPeerConnection? _pc;
  webrtc.RTCVideoRenderer? _renderer;
  Timer? _heartbeatTimer;
  bool _isLive = false;
  bool _isLoading = false;
  bool _permissionDenied = false;
  bool _fillPreview = false;
  bool _audioOnly = false;
  String _streamStatus = "OFFLINE";
  String _streamTitle = "Sunday Celebration Live";
  String _streamDescription = '';
  String? _streamId;
  String? _rtmpUrl;
  String? _streamKey;
  String? _hlsUrl;
  String? _whipUrl;
  String? _verseText;
  String? _verseRef;
  String? _logoUrl;
  String? _posterUrl;
  bool _uploadingPoster = false;
  int _viewerCount = 0;
  int _peakViewers = 0;
  String? _tickerMessage;
  int _tickerSpeed = 40;
  bool _tickerEnabled = true;
  String? _speakerName;
  String? _speakerTitle;
  String? _speakerChurch;
  String? _caption;
  bool _publishingOverlay = false;
  late final StreamAnalyticsService _analytics;
  late final LiveStreamOverlayService _overlays;
  int _cameraFacing = 1; // 0 = front (user), 1 = back (environment)
  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  /// Best-effort STUN/TURN fetch (mirrors audio_call_screen). WHIP needs usable
  /// ICE candidates to reach Cloudflare's publish endpoint; a bare empty
  /// iceServers list leaves most phone networks unable to connect and the
  /// stream never actually goes live.
  Future<void> _loadTurnCredentials() async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke('turn-credentials')
          .timeout(const Duration(seconds: 6));
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['iceServers'] != null) {
        _iceServers = Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('TURN credentials fetch failed, using STUN-only: $e');
    }
  }
  final _titleController = TextEditingController();

  /// Pick + upload a stream poster/thumbnail to R2. Bytes-based so it works on
  /// web as well as mobile (no temp-file dance).
  Future<void> _pickPoster({VoidCallback? onChanged}) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1280,
        maxHeight: 720,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Poster must be under 5 MB')),
          );
        }
        return;
      }
      setState(() => _uploadingPoster = true);
      final url = await R2Service(Supabase.instance.client).uploadBytes(
        bytes,
        'stream-posters/poster_${DateTime.now().millisecondsSinceEpoch}.jpg',
        contentType: 'image/jpeg',
      );
      if (!mounted) return;
      setState(() {
        _uploadingPoster = false;
        if (url != null) _posterUrl = url;
      });
      onChanged?.call();
      if (url == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not upload the poster — try again.')),
        );
      }
    } catch (e) {
      debugPrint('Poster pick error: $e');
      if (mounted) setState(() => _uploadingPoster = false);
      onChanged?.call();
    }
  }

  /// Ask the server to recompute presence for this broadcast. The RPC expires
  /// silent viewers, republishes `live_streams.viewer_count` and returns the
  /// current count + all-time peak — so the streamer's badge finally moves.
  Future<void> _refreshViewerCount() async {
    final id = _streamId;
    if (id == null || !mounted) return;
    final res = await _analytics.refreshViewerCount(id);
    if (res == null || !mounted) return;
    setState(() {
      _viewerCount = res.count;
      if (res.peak > _peakViewers) _peakViewers = res.peak;
    });
  }

  @override
  void initState() {
    super.initState();
    _analytics = ref.read(streamAnalyticsServiceProvider);
    _overlays = ref.read(liveStreamOverlayServiceProvider);
    _initPreview();
  }

  Future<void> _initPreview() async {
    try {
      // Release the previous tracks before re-acquiring (e.g. when toggling
      // audio-only) so we don't leak a camera/mic.
      try {
        _localStream?.getTracks().forEach((t) => t.stop());
      } catch (_) {}
      final stream = await webrtc.navigator.mediaDevices.getUserMedia(
        _audioOnly
            ? {'audio': true, 'video': false}
            : {
                'audio': true,
                'video': {
                  'facingMode': _cameraFacing == 0 ? 'user' : 'environment',
                  'width': 1280,
                  'height': 720,
                  'frameRate': 24,
                },
              },
      );
      if (!mounted) {
        stream.getTracks().forEach((t) => t.stop());
        return;
      }
      final renderer = webrtc.RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;
      setState(() {
        _localStream = stream;
        _renderer = renderer;
        _permissionDenied = false;
      });
      _loadChurchLogo();
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) setState(() => _permissionDenied = true);
    }
  }

  Future<void> _loadChurchLogo() async {
    try {
      final tenantId = widget.tenantId ?? ref.read(profileProvider).value?.tenantId;
      if (tenantId == null) return;
      final church = await Supabase.instance.client
          .from('churches')
          .select('logo_url')
          .eq('id', tenantId)
          .maybeSingle();
      final logo = church?['logo_url'] as String?;
      if (logo != null && logo.isNotEmpty && mounted) {
        setState(() => _logoUrl = logo);
      }
    } catch (e) {
      debugPrint('Logo load error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_audioOnly) return; // no video track to switch
    setState(() => _cameraFacing = _cameraFacing == 0 ? 1 : 0);
    final tracks = _localStream?.getVideoTracks() ?? const [];
    for (final t in tracks) {
      try {
        await webrtc.Helper.switchCamera(t);
      } catch (e) {
        debugPrint('switchCamera error: $e');
      }
    }
    if (tracks.isEmpty) {
      _localStream?.getTracks().forEach((t) => t.stop());
      _localStream = null;
      await _initPreview();
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickVerse() async {
    String book = 'Psalms';
    int chapter = 23;
    int verse = 1;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> loadVerse() async {
            try {
              final row = await Supabase.instance.client
                  .from('bible_verses')
                  .select('text')
                  .eq('translation', 'kjv')
                  .eq('book', book)
                  .eq('chapter', chapter)
                  .eq('verse', verse)
                  .maybeSingle();
              if (row == null || !ctx.mounted) return;
              setSheetState(() {
                _verseText = row['text'] as String?;
                _verseRef = '$book $chapter:$verse';
              });
            } catch (e) {
              debugPrint('Verse load error: $e');
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Select Scripture Verse', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: book,
                    decoration: const InputDecoration(labelText: 'Book', border: OutlineInputBorder()),
                    items: kKjvBooks.map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) { setSheetState(() => book = v ?? 'Psalms'); loadVerse(); },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Chapter', border: OutlineInputBorder()),
                          onChanged: (v) { chapter = int.tryParse(v) ?? chapter; loadVerse(); },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Verse', border: OutlineInputBorder()),
                          onChanged: (v) { verse = int.tryParse(v) ?? verse; loadVerse(); },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_verseText != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '"$_verseText" — $_verseRef',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(LucideIcons.check),
                    label: const Text('USE THIS VERSE'),
                  ),
                  if (_verseText == null)
                    TextButton(onPressed: loadVerse, child: const Text('Load verse preview')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSetupSheet() async {
    final descriptionCtrl = TextEditingController(text: _streamDescription);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: Text('Broadcast Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Broadcast title', border: OutlineInputBorder()),
                onChanged: (v) => _streamTitle = v,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
                onChanged: (v) => _streamDescription = v,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(_audioOnly ? LucideIcons.mic : LucideIcons.video),
                title: const Text('Audio-only broadcast'),
                subtitle: const Text(
                    'On = stream sound only (no camera). Off = video + audio.'),
                value: _audioOnly,
                onChanged: (v) async {
                  setState(() => _audioOnly = v);
                  // Re-acquire the local media with the new track set so the WHIP
                  // offer is genuinely audio-only / audio+video.
                  await _initPreview();
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fill screen preview (crop)'),
                subtitle: const Text('Off = fit whole frame, On = fill the screen'),
                value: _fillPreview,
                onChanged: (v) => setState(() => _fillPreview = v),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.bookOpen),
                title: const Text('Overlay verse'),
                subtitle: Text(_verseRef ?? 'No verse selected'),
                trailing: TextButton(onPressed: _pickVerse, child: const Text('Choose')),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.image),
                title: const Text('Tenant logo'),
                subtitle: Text(_logoUrl == null ? 'No church logo found' : 'Using church logo'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: (_posterUrl != null && _posterUrl!.isNotEmpty)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: AppImage(_posterUrl!, width: 40, height: 40, fit: BoxFit.cover),
                      )
                    : const Icon(LucideIcons.imagePlus),
                title: const Text('Stream poster'),
                subtitle: Text(
                  _uploadingPoster
                      ? 'Uploading…'
                      : (_posterUrl == null
                          ? 'Optional thumbnail shown to viewers'
                          : 'Poster set'),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_posterUrl != null)
                      IconButton(
                        tooltip: 'Remove poster',
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () {
                          setState(() => _posterUrl = null);
                          setSheetState(() {});
                        },
                      ),
                    TextButton(
                      onPressed: _uploadingPoster
                          ? null
                          : () => _pickPoster(onChanged: () => setSheetState(() {})),
                      child: Text(_posterUrl == null ? 'Choose' : 'Change'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final tid = widget.tenantId ?? ref.read(profileProvider).value?.tenantId;
                        Navigator.pop(ctx);
                        if (tid != null) context.push('/streaming-config/$tid');
                      },
                      icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
                      label: const Text('Stream Config'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final tid = widget.tenantId ?? ref.read(profileProvider).value?.tenantId;
                        Navigator.pop(ctx);
                        if (tid != null) context.push('/stream-admin/$tid');
                      },
                      icon: const Icon(LucideIcons.shield, size: 16),
                      label: const Text('Admin'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(LucideIcons.check),
                label: const Text('SAVE SETTINGS'),
              ),
            ],
          ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _startStream() async {
    final profile = ref.read(profileProvider).value;
    final tenantId = widget.tenantId ?? profile?.tenantId;
    if (tenantId == null || tenantId.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select a church first")));
      return;
    }
    if (_localStream == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Camera not ready")));
      return;
    }

    setState(() {
      _isLoading = true;
      _streamStatus = "CONNECTING";
    });

    try {
      final client = Supabase.instance.client;
      final unifiedService = UnifiedStreamService(client);
      final result = await unifiedService.createLiveStream(
        tenantId: tenantId,
        title: _streamTitle,
        description: _streamDescription,
        audioOnly: _audioOnly,
        thumbnailUrl: _posterUrl,
      );

      _streamId = result.streamId;

      if (_verseText != null || _verseRef != null || _logoUrl != null ||
          _tickerMessage != null || _speakerName != null ||
          _speakerTitle != null || _speakerChurch != null ||
          _caption != null) {
        await client.from('live_streams').update({
          if (_verseText != null) 'overlay_verse': _verseText,
          if (_verseRef != null) 'overlay_verse_ref': _verseRef,
          if (_logoUrl != null) 'overlay_logo_url': _logoUrl,
          'ticker_message': _tickerMessage,
          'ticker_speed': _tickerSpeed,
          'ticker_enabled': _tickerEnabled,
        }).eq('id', result.streamId);
        await _publishOverlay(tenantId: tenantId, silent: true);
      }

      _startHeartbeat();
      _rtmpUrl = result.rtmpUrl;
      _streamKey = result.streamKey;
      _hlsUrl = result.hlsUrl;
      _whipUrl = result.whipUrl;

      // Repair a missing HLS URL immediately. A freshly-created Cloudflare live
      // input can take a few seconds to expose its manifest, so the row may be
      // stored with an empty hls_url — the viewer's automatic refresh path uses
      // this. Credentials stay valid throughout, so the streamer is never
      // blocked by "playback not ready".
      if ((_hlsUrl == null || _hlsUrl!.isEmpty) && result.streamId.isNotEmpty) {
        try {
          final info = await ref
              .read(liveStreamServiceProvider)
              .refreshPlayback(result.streamId);
          final repaired = info?.hlsUrl;
          if (repaired != null && repaired.isNotEmpty) _hlsUrl = repaired;
        } catch (e) {
          debugPrint('HLS repair after create failed: $e');
        }
      }

      // Mark the church LIVE so viewers can discover it from the home screen
      // LIVE indicator (church_live_status), not just by opening the studio.
      try {
        await LiveStreamingService(client).setLiveStatus(
          tenantId,
          true,
          streamUrl: _hlsUrl,
          title: _streamTitle,
        );
      } catch (e) {
        debugPrint('Failed to set live status: $e');
      }

      // Try WebRTC WHIP ingest first (phone streams live to Cloudflare).
      final broadcastStarted = _whipUrl != null && await _startWhipIngest(_whipUrl!);

      if (broadcastStarted) {
        if (mounted) {
          setState(() {
            _isLive = true;
            _streamStatus = "LIVE";
            _isLoading = false;
          });
        }
      } else {
        // WHIP unavailable / failed — the row is armed for OBS but NOTHING is
        // publishing yet. Never claim "LIVE": the streamer must see at a glance
        // that the feed has not connected (otherwise a failed publish looks
        // successful and viewers wait on "Stream is starting" forever).
        if (mounted) {
          setState(() {
            _isLive = true;
            _streamStatus = _whipError != null
                ? "PHONE FEED FAILED"
                : "WAITING FOR OBS";
            _isLoading = false;
          });
          _showStreamCredentials();
        }
      }
    } catch (e) {
      debugPrint("Stream start error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _streamStatus = "OFFLINE";
        });
        final raw = e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to start stream: ${_friendlyStreamError(raw)}")));
      }
    }
  }

  String _friendlyStreamError(String raw) {
    final status = RegExp(r'status: (\d+)').firstMatch(raw)?.group(1);
    if (raw.contains('Insufficient role')) {
      return 'Only church leadership (pastor, bishop, admin, COA team) can go live.';
    }
    if (raw.contains('meta.church_id is required')) {
      return 'Select your church first, then retry.';
    }
    if (raw.contains('Missing authorization header') || raw.contains('"error": "Unauthorized"') || raw.contains('{error: Unauthorized}')) {
      return 'Your session expired — sign out and sign in again, then retry.';
    }
    if (raw.contains('Live input does not expose a WebRTC')) {
      return 'This stream is not WebRTC-ready — use the OBS/RTMP credentials instead.';
    }
    if (raw.contains('WHIP offer failed')) {
      final m = RegExp(r'WHIP offer failed: (.+)').firstMatch(raw);
      final detail = m?.group(1)?.trim();
      return detail != null && detail.isNotEmpty && detail != 'null'
          ? 'Stream did not accept the phone feed ($detail).'
          : 'Stream did not accept the phone feed.';
    }
    final detailsMatch = RegExp(r'details: \{(.+)\}, reasonPhrase').firstMatch(raw);
    if (detailsMatch != null) {
      final body = detailsMatch.group(1)!;
      final em = RegExp(r'error: (.+)').firstMatch(body);
      if (em != null) {
        final msg = em.group(1)!.trim();
        if (msg.isNotEmpty && msg != 'null') {
          return 'Streaming service error${status != null ? ' ($status)' : ''}: $msg';
        }
      }
    }
    final cleanedRaw = raw.replaceAll('Exception: ', '');
    if (cleanedRaw.isNotEmpty && cleanedRaw != 'null') {
      return cleanedRaw;
    }
    return 'Streaming service error${status != null ? ' ($status)' : ''}.';
  }

  /// Ping the live row every 30s so expire_stale_live_streams() (called by
  /// checkStreamGate on every start attempt) never mistakes an active broadcast
  /// for an abandoned one. Abandoned rows are auto-ended on the next attempt.
  void _startHeartbeat() {
    _stopHeartbeat();
    final client = Supabase.instance.client;
    final unifiedService = UnifiedStreamService(client);
    void ping() {
      final id = _streamId;
      if (id == null) return;
      unawaited(unifiedService.sendHeartbeat(id));
      unawaited(_refreshViewerCount());
    }

    ping();
    // 15 s so the live viewer badge tracks the audience closely.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) => ping());
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  String? _whipError;

  Future<bool> _startWhipIngest(String whipUrl) async {
    _whipError = null;
    try {
      await _loadTurnCredentials();

      // Validate the ICE servers — a malformed `turn-credentials` reply must
      // not break phone streaming. Fall back to plain STUN.
      var servers = <Map<String, dynamic>>[
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ];
      try {
        final raw = _iceServers['iceServers'];
        if (raw is List &&
            raw.isNotEmpty &&
            raw.every((e) => e is Map && e['urls'] != null)) {
          servers = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}

      final iceConfig = <String, dynamic>{
        'iceServers': servers,
        'sdpSemantics': 'unified-plan',
      };

      _pc = await webrtc.createPeerConnection(
        iceConfig,
        {'trickle': false},
      );

      for (final track in _localStream!.getTracks()) {
        _pc!.addTrack(track, _localStream!);
      }

      var candidates = 0;
      _pc!.onIceCandidate = (c) {
        if ((c.candidate ?? '').isNotEmpty) candidates++;
      };

      _pc!.onConnectionState = (webrtc.RTCPeerConnectionState state) {
        debugPrint('WHIP connection state: $state');
        if (mounted && _streamId != null) {
          setState(() {
            _isLive = state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected;
            _streamStatus = state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected
                ? "LIVE"
                : "CONNECTING";
            if (state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
              _streamStatus = "RECONNECTING";
            }
          });
        }
      };

      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': false,
        'offerToReceiveVideo': false,
      });
      await _pc!.setLocalDescription(offer);

      // WHIP requires a full (non-trickle) offer. Prefer "complete", but accept
      // a settled candidate set — several phones never report `complete` and
      // previously produced a candidate-less offer, which Cloudflare rejects.
      var waited = 0;
      while (waited < 12000) {
        if (_pc!.iceGatheringState ==
            webrtc.RTCIceGatheringState.RTCIceGatheringStateComplete) {
          break;
        }
        if (candidates > 0 && waited >= 2000) break;
        await Future.delayed(const Duration(milliseconds: 200));
        waited += 200;
      }

      final ld = await _pc!.getLocalDescription();
      final sdp = ld?.sdp;
      if (sdp == null) {
        debugPrint('WHIP: no local SDP after gathering');
        _whipError = 'Could not build a media offer from this phone.';
        return false;
      }

      // Retry once — the first WHIP POST occasionally races ICE on mobile.
      http.Response? res;
      for (var attempt = 0; attempt < 2; attempt++) {
        res = await http.post(
          Uri.parse(whipUrl),
          headers: {'Content-Type': 'application/sdp'},
          body: sdp,
        );
        if (res.statusCode >= 200 && res.statusCode < 300) break;
        debugPrint(
            'WHIP offer rejected (attempt ${attempt + 1}): ${res.statusCode} ${res.body}');
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }

      if (res == null || res.statusCode < 200 || res.statusCode >= 300) {
        final body = (res?.body ?? '');
        _whipError =
            'Phone streaming was not accepted (${res?.statusCode ?? 'no response'})'
            '${body.isEmpty ? '' : ': ${body.substring(0, body.length.clamp(0, 160))}'}';
        return false;
      }

      // The answer body MUST be a valid SDP. A JSON/HTML error body must never
      // be handed to setRemoteDescription (it throws inside the platform
      // channel, e.g. `No enum constant …Type.V=0`). Normalise line endings,
      // guarantee the mandatory leading `v=0`, and pass the SDP TYPE explicitly
      // ('answer') — the type must never be inferred from the body.
      final answerSdp = _normaliseSdpAnswer(res);
      if (answerSdp == null) {
        final body = res.body.trim();
        _whipError = 'Phone streaming failed: the service sent an invalid response'
            '${body.isEmpty ? '.' : ' — ${body.substring(0, body.length.clamp(0, 140))}'}';
        return false;
      }

      await _pc!.setRemoteDescription(
        webrtc.RTCSessionDescription(answerSdp, 'answer'),
      );
      return true;
    } catch (e) {
      debugPrint('WHIP ingest error: $e');
      _whipError = e.toString();
      return false;
    }
  }

  /// Turn a WHIP POST response into a valid SDP answer, or `null` if the body
  /// is not SDP (e.g. a JSON error envelope).
  ///
  /// Rules:
  ///  - never strip/replace the first line — only *ensure* it starts with `v=`;
  ///  - prepend `v=0\r\n` when the mandatory version line is missing;
  ///  - normalise every line ending to `\r\n` and ensure a trailing newline.
  String? _normaliseSdpAnswer(http.Response res) {
    final contentType = (res.headers['content-type'] ?? '').toLowerCase();
    final raw = res.body.trim();
    if (raw.isEmpty) return null;
    if (contentType.contains('json') || contentType.contains('html')) return null;
    if (raw.startsWith('{') || raw.startsWith('<') || raw.startsWith('[')) return null;

    var sdp = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    sdp = sdp.split('\n').map((l) => l.trimRight()).join('\r\n');
    if (!sdp.startsWith('v=')) sdp = 'v=0\r\n$sdp';
    if (!sdp.endsWith('\r\n')) sdp = '$sdp\r\n';
    return sdp;
  }

  Widget _credRow(BuildContext ctx, String label, String value) {
    final hasValue = value.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
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
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6))),
                SelectableText(
                  hasValue ? value : 'Creating…',
                  style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.copy, size: 18),
            onPressed: hasValue
                ? () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('$label copied')),
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }

  void _showStreamCredentials() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Connect an encoder or drone"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _whipError == null
                    ? "Phone streaming is unavailable right now. Any RTMP source works — OBS, Wirecast, vMix, a drone controller or a hardware encoder. Paste these credentials and start streaming:"
                    : "Phone streaming failed: $_whipError\n\nAny RTMP source works — OBS, Wirecast, vMix, a drone or a hardware encoder:",
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 14),
              _credRow(ctx, 'RTMP / RTMPS server', _rtmpUrl ?? ''),
              const SizedBox(height: 8),
              _credRow(ctx, 'Stream key', _streamKey ?? ''),
              const SizedBox(height: 8),
              _credRow(ctx, 'Viewer playback (HLS)', _hlsUrl ?? ''),
              const SizedBox(height: 12),
              const Text(
                'Recommended: 1920×1080 · 6000 Kbps CBR · 2 s keyframe. '
                'Your stream is converted to adaptive quality automatically.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openProjector();
            },
            child: const Text("PROJECTOR"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showShareQr();
            },
            child: const Text("SHARE / QR"),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("DISMISS")),
        ],
      ),
    );
  }

  Future<void> _stopStream() async {
    setState(() => _isLoading = true);
    _stopHeartbeat();

    try {
      // Tear down WebRTC ingest first so the input stops receiving media.
      if (_pc != null) {
        try {
          await _pc!.close();
        } catch (e) {
          debugPrint('Peer close error: $e');
        }
        _pc = null;
      }

      final tenantId = widget.tenantId ?? ref.read(profileProvider).value?.tenantId;

      if (_streamId != null) {
        final client = Supabase.instance.client;
        final unifiedService = UnifiedStreamService(client);
        await unifiedService.endStream(_streamId!);
      }

      if (tenantId != null) {
        // Isolate the live-status write: it is a best-effort "viewers can stop
        // seeing the LIVE pill" cleanup and must never block the local teardown.
        try {
          final streamingService = ref.read(liveStreamingServiceProvider);
          await streamingService.setLiveStatus(tenantId, false);
        } catch (e) {
          debugPrint('Failed to clear live status (non-fatal): $e');
        }
      }

      if (mounted) {
        final peak = _peakViewers;
        setState(() {
          _isLive = false;
          _streamStatus = "OFFLINE";
          _streamId = null;
          _rtmpUrl = null;
          _streamKey = null;
          _whipUrl = null;
          _viewerCount = 0;
          _peakViewers = 0;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(peak > 0
                ? "Stream Ended · Peak $peak viewers"
                : "Stream Ended."),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Stream stop error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not end the stream: ${_friendlyEndError(e)}")),
        );
      }
    }
  }

  /// Human-readable message for an end-stream failure — never surface a raw
  /// PostgrestException to the operator.
  String _friendlyEndError(Object e) {
    final raw = e.toString();
    if (raw.contains('23505') || raw.contains('duplicate key')) {
      return 'the stream was already marked as ended. Pull to refresh and try again.';
    }
    if (raw.contains('Unauthorized') || raw.contains('401') || raw.contains('session')) {
      return 'your session expired. Sign out and sign in again, then retry.';
    }
    if (raw.contains('SocketException') || raw.contains('Failed host lookup')) {
      return 'you appear to be offline. Check your connection and try again.';
    }
    return 'something went wrong. Please try again.';
  }

  /// Push the verse / speaker / caption / ticker to every viewer in realtime.
  Future<void> _publishOverlay({
    String? tenantId,
    bool silent = false,
    bool clearVerse = false,
    bool clearSpeaker = false,
    bool clearCaption = false,
  }) async {
    final streamId = _streamId;
    if (streamId == null) return;
    final tid = tenantId ??
        widget.tenantId ??
        ref.read(profileProvider).value?.tenantId;

    if (clearVerse) {
      _verseText = null;
      _verseRef = null;
    }
    if (clearSpeaker) {
      _speakerName = null;
      _speakerTitle = null;
      _speakerChurch = null;
    }
    if (clearCaption) {
      _caption = null;
    }

    if (mounted) setState(() => _publishingOverlay = true);
    try {
      await _overlays.publishOverlay(
        streamId: streamId,
        tenantId: tid,
        clearVerse: clearVerse,
        verseText: _verseText,
        verseRef: _verseRef,
        tickerMessage: _tickerMessage,
        tickerSpeed: _tickerSpeed,
        tickerEnabled: _tickerEnabled,
        logoUrl: _logoUrl,
        clearSpeaker: clearSpeaker,
        speakerName: _speakerName,
        speakerTitle: _speakerTitle,
        speakerChurch: _speakerChurch,
        clearCaption: clearCaption,
        caption: _caption,
      );
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('On-air overlay updated'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('publish overlay failed: $e');
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update overlay: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _publishingOverlay = false);
    }
  }

  /// Live control of the verse of the moment + scrolling ticker.
  Future<void> _showOverlayControls() async {
    final tickerCtrl = TextEditingController(text: _tickerMessage ?? '');
    final speakerNameCtrl = TextEditingController(text: _speakerName ?? '');
    final speakerTitleCtrl = TextEditingController(text: _speakerTitle ?? '');
    final speakerChurchCtrl = TextEditingController(text: _speakerChurch ?? '');
    final captionCtrl = TextEditingController(text: _caption ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text('On-air Overlay & Ticker',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  // ---- Speaker details (lower-third) ----
                  Row(
                    children: [
                      const Icon(LucideIcons.mic, size: 18),
                      const SizedBox(width: 8),
                      const Text('Speaker details',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (_speakerName != null ||
                          _speakerTitle != null ||
                          _speakerChurch != null)
                        IconButton(
                          tooltip: 'Clear speaker',
                          icon: const Icon(LucideIcons.x, size: 18),
                          onPressed: () async {
                            speakerNameCtrl.clear();
                            speakerTitleCtrl.clear();
                            speakerChurchCtrl.clear();
                            await _publishOverlay(clearSpeaker: true);
                            setSheet(() {});
                          },
                        ),
                    ],
                  ),
                  TextField(
                    controller: speakerNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Speaker name',
                      hintText: 'e.g. Pastor John Phiri',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _speakerName = v.trim().isEmpty ? null : v.trim(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: speakerTitleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Role / title',
                      hintText: 'e.g. Senior Pastor',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _speakerTitle = v.trim().isEmpty ? null : v.trim(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: speakerChurchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Church',
                      hintText: 'e.g. Rock of Ages, Kabulonga',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _speakerChurch = v.trim().isEmpty ? null : v.trim(),
                  ),
                  const SizedBox(height: 12),
                  // ---- Caption / title ----
                  TextField(
                    controller: captionCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'On-air caption / title',
                      hintText: 'e.g. Sunday Celebration — Faith That Moves',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _caption = v.trim().isEmpty ? null : v.trim(),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(LucideIcons.bookOpen),
                    title: const Text('Verse of the moment'),
                    subtitle: Text(_verseRef ?? 'No verse on screen'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_verseRef != null)
                          IconButton(
                            tooltip: 'Clear verse',
                            icon: const Icon(LucideIcons.x, size: 18),
                            onPressed: () async {
                              await _publishOverlay(clearVerse: true);
                              setSheet(() {});
                            },
                          ),
                        TextButton(
                          onPressed: () async {
                            await _pickVerse();
                            if (_streamId != null) {
                              await _publishOverlay();
                            }
                            setSheet(() {});
                          },
                          child: Text(_verseRef == null ? 'Choose' : 'Change'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: tickerCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Scrolling message (theme / announcement)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _tickerMessage = v,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show ticker'),
                    value: _tickerEnabled,
                    onChanged: (v) => setSheet(() => _tickerEnabled = v),
                  ),
                  Row(
                    children: [
                      const Icon(LucideIcons.gauge, size: 18),
                      const SizedBox(width: 8),
                      const Text('Speed'),
                      Expanded(
                        child: Slider(
                          min: 10,
                          max: 120,
                          divisions: 11,
                          value: _tickerSpeed.toDouble(),
                          label: '$_tickerSpeed',
                          onChanged: (v) =>
                              setSheet(() => _tickerSpeed = v.round()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _publishingOverlay
                        ? null
                        : () async {
                            await _publishOverlay();
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                    icon: const Icon(LucideIcons.send),
                    label: const Text('PUBLISH TO VIEWERS'),
                  ),
                  if (_speakerName != null || _speakerTitle != null || _caption != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        [
                          if (_speakerName != null) _speakerName!,
                          if (_speakerTitle != null) _speakerTitle!,
                          if (_speakerChurch != null) _speakerChurch!,
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openProjector() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StreamProjectorScreen(
          title: _streamTitle,
          hlsUrl: _hlsUrl,
          streamId: _streamId,
          logoUrl: _logoUrl,
        ),
      ),
    );
  }

  void _showShareQr() {
    const link = 'https://churchonapp.com/live-streaming';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share the live link',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(link,
                style: TextStyle(fontSize: 12, fontFamily: 'monospace')),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: link));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Live link copied')),
                  );
                }
              },
              icon: const Icon(LucideIcons.copy, size: 16),
              label: const Text('COPY LINK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareStream() async {
    // Share an APP link (opens the streaming hub in-app / on web) rather than
    // the raw HLS manifest, and actually copy it — the old code showed
    // "copied" without copying anything and pointed at the non-existent /live.
    const link = 'https://churchonapp.com/live-streaming';
    await Clipboard.setData(const ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Live link copied — share it so members can watch."),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _stopHeartbeat();
    // A force-close, route pop, or OS kill must not leave a stream marked live.
    final abandonedId = _isLive ? _streamId : null;
    if (abandonedId != null) {
      unawaited(Supabase.instance.client.from('live_streams').update({
        'status': 'ended',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', abandonedId));
    }
    _titleController.dispose();
    _pc?.dispose();
    _renderer?.dispose();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    super.dispose();
  }

  Widget _bottomAction(IconData icon, String label, VoidCallback onTap,
      {Color color = Colors.white}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: Icon(icon, color: color, size: 26), onPressed: onTap),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.cameraOff, color: Colors.white54, size: 64),
                const SizedBox(height: 16),
                const Text("Camera & Microphone Access Required",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text("Grant permissions to go live.", style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() => _permissionDenied = false);
                    _initPreview();
                  },
                  icon: const Icon(LucideIcons.refreshCw),
                  label: const Text("GRANT ACCESS"),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_localStream == null) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))));
    }

    final statusColor = _streamStatus == "LIVE"
        ? Colors.red
        : _streamStatus == "CONNECTING" ||
                _streamStatus == "RECONNECTING" ||
                _streamStatus == "WAITING FOR OBS"
            ? Colors.amber
            : _streamStatus == "PHONE FEED FAILED"
                ? Colors.redAccent
                : Colors.black54;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _audioOnly
                ? const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.mic,
                              color: Color(0xFFFFD700), size: 56),
                          SizedBox(height: 12),
                          Text('AUDIO-ONLY BROADCAST',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 1.5)),
                        ],
                      ),
                    ),
                  )
                : _renderer == null
                    ? const ColoredBox(color: Colors.black)
                    : webrtc.RTCVideoView(
                        _renderer!,
                        mirror: _cameraFacing == 0,
                        objectFit: _fillPreview
                            ? webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                            : webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      ),
          ),
          if (_isLoading)
            Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))),
          // Live preview of the on-air overlays (speaker lower-third + caption)
          // so the streamer sees exactly what viewers see.
          if (_isLive && (_speakerName != null || _speakerTitle != null || _speakerChurch != null || _caption != null))
            Positioned(
              left: 16,
              right: 16,
              bottom: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_caption != null && _caption!.trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _caption!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                        ),
                      ),
                    ),
                  if (_speakerName != null || _speakerTitle != null || _speakerChurch != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(color: const Color(0xFFFFD700), width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_speakerName != null)
                            Text(
                              _speakerName!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                              ),
                            ),
                          if (_speakerTitle != null || _speakerChurch != null)
                            Text(
                              [_speakerTitle, _speakerChurch]
                                  .whereType<String>()
                                  .join(' · '),
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
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                            decoration: BoxDecoration(
                              color: statusColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _streamStatus == "LIVE" ? LucideIcons.radioReceiver : LucideIcons.videoOff,
                                  color: Colors.white, size: 16,
                                ),
                                const SizedBox(width: 5),
                                Text(_streamStatus, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          ),
                          if (_isLive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  const Icon(LucideIcons.eye, color: Colors.white, size: 14),
                                  const SizedBox(width: 4),
                                  Text('$_viewerCount',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.settings, color: Colors.white),
                        onPressed: _isLive ? null : _showSetupSheet,
                      ),
                    ],
                  ),
                ),
                if (!_isLive)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextField(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                        ),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          hintText: "Enter Broadcast Title",
                          hintStyle: TextStyle(color: Colors.white70),
                          border: InputBorder.none,
                        ),
                        onChanged: (v) => _streamTitle = v,
                        controller: _titleController,
                      ),
                    ),
                  ),
                if (!_isLive && (_verseRef != null || _logoUrl != null || _posterUrl != null))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (_verseRef != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                            child: Text('📖 $_verseRef', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        if (_logoUrl != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                            child: const Text('🏛 Church logo', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        if (_posterUrl != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                            child: const Text('🖼 Poster set', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.only(bottom: 30, top: 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (!_isLive)
                        _bottomAction(LucideIcons.maximize,
                            _fillPreview ? "Fill" : "Fit",
                            () => setState(() => _fillPreview = !_fillPreview))
                      else
                        _bottomAction(LucideIcons.columns, "Overlay", _showOverlayControls,
                            color: Colors.amber),
                      if (_isLive)
                        _bottomAction(LucideIcons.monitor, "Projector", _openProjector),
                      GestureDetector(
                        onTap: _isLoading ? null : (_isLive ? _stopStream : _startStream),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: Center(
                            child: Container(
                              width: _isLive ? 30 : 65,
                              height: _isLive ? 30 : 65,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(_isLive ? 5 : 40),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_isLive)
                        _bottomAction(LucideIcons.share2, "Share / QR", _showShareQr,
                            color: Colors.amber)
                      else
                        _bottomAction(LucideIcons.share, "Share", _shareStream,
                            color: Colors.amber),
                      _bottomAction(
                          LucideIcons.refreshCcw, "Flip", _switchCamera),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
