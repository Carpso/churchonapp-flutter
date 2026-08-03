import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/home/data/live_streaming_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/unified_stream_service.dart';

class LiveStreamStudioScreen extends ConsumerStatefulWidget {
  final String? tenantId;
  const LiveStreamStudioScreen({super.key, this.tenantId});

  @override
  ConsumerState<LiveStreamStudioScreen> createState() => _LiveStreamStudioScreenState();
}

class _LiveStreamStudioScreenState extends ConsumerState<LiveStreamStudioScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  int _selectedCameraIndex = 0;
  bool _isLive = false;
  bool _isInit = false;
  bool _isLoading = false;
  String _streamStatus = "OFFLINE";
  String _streamTitle = "Sunday Celebration Live";
  int _viewers = 0;
  String? _streamId;
  String? _rtmpUrl;
  String? _streamKey;
  String? _hlsUrl;
  final List<String> _chatMessages = [];
  final _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndInit();
  }

  Future<void> _checkPermissionsAndInit() async {
    final status = await [Permission.camera, Permission.microphone].request();
    if ((status[Permission.camera]?.isGranted ?? false) && (status[Permission.microphone]?.isGranted ?? false)) {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _initCamera(_cameras![0]);
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Camera and Microphone permissions required.")),
      );
    }
  }

  Future<void> _initCamera(CameraDescription config) async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }
    _cameraController = CameraController(config, ResolutionPreset.high, enableAudio: true);
    try {
      await _cameraController!.initialize();
      if (mounted) setState(() => _isInit = true);
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  void _toggleCamera() {
    if (_cameras == null || _cameras!.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    _initCamera(_cameras![_selectedCameraIndex]);
  }

  Future<void> _startStream() async {
    final profile = ref.read(profileProvider).value;
    final tenantId = widget.tenantId ?? profile?.tenantId;
    if (tenantId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No tenant selected")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final client = Supabase.instance.client;
      final unifiedService = UnifiedStreamService(client);
      final result = await unifiedService.createLiveStream(
        tenantId: tenantId,
        title: _streamTitle,
      );

      _streamId = result.streamId;
      _rtmpUrl = result.rtmpUrl;
      _streamKey = result.streamKey;
      _hlsUrl = result.hlsUrl;

      final streamingService = ref.read(liveStreamingServiceProvider);
      await streamingService.setLiveStatus(
        tenantId,
        true,
        streamUrl: result.hlsUrl,
        title: _streamTitle,
      );

      if (mounted) {
        setState(() {
          _isLive = true;
          _streamStatus = "LIVE ON HUB";
          _viewers = 0;
          _isLoading = false;
        });
        _showStreamCredentials();
      }
    } catch (e) {
      debugPrint("Stream start error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to start stream: $e")));
      }
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
            const Text("Use these in OBS or any RTMP encoder:", style: TextStyle(fontWeight: FontWeight.bold)),
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
          _viewers = 0;
          _streamId = null;
          _rtmpUrl = null;
          _streamKey = null;
          _chatMessages.clear();
          _isLoading = false;
        });
      }

      if (mounted) {
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
    final info = _rtmpUrl != null && _streamKey != null
        ? "RTMP: $_rtmpUrl\nKey: $_streamKey\nHLS: https://live.churchonapp.com/stream/$_streamId"
        : "https://churchonapp.com/live";
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Share: $info"), backgroundColor: Colors.blue, duration: const Duration(seconds: 5)),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit || _cameraController == null) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Color(0xFFFFD700))));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cameraController!.value.previewSize?.height ?? 1,
                height: _cameraController!.value.previewSize?.width ?? 1,
                child: CameraPreview(_cameraController!),
              ),
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
                          color: _isLive ? Colors.red : Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(_isLive ? LucideIcons.radioReceiver : LucideIcons.videoOff, color: Colors.white, size: 16),
                            const SizedBox(width: 5),
                            Text(_streamStatus, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (_isLive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.eye, color: Colors.white, size: 14),
                              const SizedBox(width: 5),
                              Text("$_viewers", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      else
                        const SizedBox(width: 40),
                    ],
                  ),
                ),
                  if (!_isLive)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                      child: TextField(
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
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
                            child: Row(
                              children: [
                                const CircleAvatar(radius: 10, child: Icon(LucideIcons.user, size: 10)),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_chatMessages[_chatMessages.length - 1 - index], style: const TextStyle(color: Colors.white, fontSize: 12))),
                              ],
                            ),
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
                            icon: const Icon(LucideIcons.cast, color: Colors.white, size: 28),
                            onPressed: () {},
                          ),
                          const Text("Connect", style: TextStyle(color: Colors.white, fontSize: 10)),
                        ],
                      ),
                      if (_isLive)
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(LucideIcons.share, color: Colors.blue, size: 28),
                              onPressed: _shareStream,
                            ),
                            const Text("Share Link", style: TextStyle(color: Colors.white, fontSize: 10)),
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
                            onPressed: _toggleCamera,
                          ),
                          const Text("Flip", style: TextStyle(color: Colors.white, fontSize: 10)),
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
