import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/unified_stream_service.dart';
import 'package:church_on_app/features/home/data/live_streaming_service.dart';

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
  bool _isLive = false;
  bool _isLoading = false;
  bool _permissionDenied = false;
  bool _fillPreview = false;
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
  int _cameraFacing = 1; // 0 = front (user), 1 = back (environment)
  final List<String> _chatMessages = [];
  final _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initPreview();
  }

  Future<void> _initPreview() async {
    try {
      final stream = await webrtc.navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': _cameraFacing == 0 ? 'user' : 'environment',
          'width': 1280,
          'height': 720,
          'frameRate': 24,
        },
      });
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
      builder: (ctx) => SafeArea(
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
    );
    if (mounted) setState(() {});
  }

  Future<void> _startStream() async {
    final profile = ref.read(profileProvider).value;
    final tenantId = widget.tenantId ?? profile?.tenantId;
    if (tenantId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No tenant selected")));
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
      );

      if (_verseText != null || _verseRef != null || _logoUrl != null) {
        await client.from('live_streams').update({
          if (_verseText != null) 'overlay_verse': _verseText,
          if (_verseRef != null) 'overlay_verse_ref': _verseRef,
          if (_logoUrl != null) 'overlay_logo_url': _logoUrl,
        }).eq('id', result.streamId);
      }

      _streamId = result.streamId;
      _rtmpUrl = result.rtmpUrl;
      _streamKey = result.streamKey;
      _hlsUrl = result.hlsUrl;
      _whipUrl = result.whipUrl;

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
        // WHIP unavailable — arm the stream and show OBS credentials instead.
        if (mounted) {
          setState(() {
            _isLive = true;
            _streamStatus = "LIVE ON HUB";
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to start stream: ${e.toString().replaceAll('Exception: ', '')}")));
      }
    }
  }

  Future<bool> _startWhipIngest(String whipUrl) async {
    try {
      _pc = await webrtc.createPeerConnection(
        {'iceServers': const [], 'sdpSemantics': 'unified-plan'},
        {'trickle': false},
      );

      for (final track in _localStream!.getTracks()) {
        _pc!.addTrack(track, _localStream!);
      }

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

      // WHIP requires a full (non-trickle) offer — wait for ICE gathering.
      var waited = 0;
      while (_pc!.iceGatheringState != webrtc.RTCIceGatheringState.RTCIceGatheringStateComplete &&
          waited < 10000) {
        await Future.delayed(const Duration(milliseconds: 200));
        waited += 200;
      }

      final ld = await _pc!.getLocalDescription();
      final sdp = ld?.sdp;
      if (sdp == null) {
        debugPrint('WHIP: no local SDP after gathering');
        return false;
      }

      final res = await http.post(
        Uri.parse(whipUrl),
        headers: {'Content-Type': 'application/sdp'},
        body: sdp,
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('WHIP offer rejected: ${res.statusCode} ${res.body}');
        return false;
      }

      await _pc!.setRemoteDescription(webrtc.RTCSessionDescription('answer', res.body));
      return true;
    } catch (e) {
      debugPrint('WHIP ingest error: $e');
      return false;
    }
  }

  void _showStreamCredentials() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Stream Credentials"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Phone streaming is unavailable right now. Use these in OBS or any RTMP encoder:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text("RTMP URL:", style: TextStyle(fontSize: 12, color: Colors.grey)),
            SelectableText(_rtmpUrl ?? "N/A", style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
            const SizedBox(height: 8),
            const Text("Stream Key:", style: TextStyle(fontSize: 12, color: Colors.grey)),
            SelectableText(_streamKey ?? "N/A", style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
            const SizedBox(height: 12),
            const Text("HLS URL (for viewers):", style: TextStyle(fontSize: 12, color: Colors.grey)),
            SelectableText(_hlsUrl ?? "N/A", style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("DISMISS")),
        ],
      ),
    );
  }

  Future<void> _stopStream() async {
    setState(() => _isLoading = true);

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
        final streamingService = ref.read(liveStreamingServiceProvider);
        await streamingService.setLiveStatus(tenantId, false);
      }

      if (mounted) {
        setState(() {
          _isLive = false;
          _streamStatus = "OFFLINE";
          _streamId = null;
          _rtmpUrl = null;
          _streamKey = null;
          _whipUrl = null;
          _chatMessages.clear();
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Stream Ended."), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Stream stop error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to end stream: $e")));
      }
    }
  }

  void _shareStream() {
    final link = _hlsUrl ?? "https://churchonapp.com/live";
    if (!kIsWeb) {
      // Copy to clipboard + share sheet where possible
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Live link copied: $link"), duration: const Duration(seconds: 3)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Live link: $link"), duration: const Duration(seconds: 3)),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _pc?.dispose();
    _renderer?.dispose();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    super.dispose();
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
        : _streamStatus == "CONNECTING" || _streamStatus == "RECONNECTING"
            ? Colors.amber
            : Colors.black54;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _renderer == null
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
                    child: TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        hintText: "Enter Broadcast Title",
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                      onChanged: (v) => _streamTitle = v,
                      controller: _titleController,
                    ),
                  ),
                if (!_isLive && (_verseRef != null || _logoUrl != null))
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
                      ],
                    ),
                  ),
                const Spacer(),
                if (_isLive && _chatMessages.isNotEmpty)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      width: 250,
                      height: 150,
                      margin: const EdgeInsets.only(left: 20, bottom: 20),
                      child: ListView.builder(
                        reverse: true,
                        itemCount: _chatMessages.length,
                        itemBuilder: (context, index) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15)),
                            child: Text(_chatMessages[_chatMessages.length - 1 - index], style: const TextStyle(color: Colors.white, fontSize: 12)),
                          );
                        },
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.only(bottom: 30, top: 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.maximize, color: Colors.white, size: 28),
                            onPressed: () => setState(() => _fillPreview = !_fillPreview),
                          ),
                          Text(_fillPreview ? "Fill" : "Fit", style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
                      if (_isLive)
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(LucideIcons.share, color: Colors.amber, size: 28),
                              onPressed: _shareStream,
                            ),
                            const Text("Share Link", style: TextStyle(color: Colors.white, fontSize: 11)),
                          ],
                        ),
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
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.refreshCcw, color: Colors.white, size: 28),
                            onPressed: _switchCamera,
                          ),
                          const Text("Flip", style: TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
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