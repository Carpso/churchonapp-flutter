import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

class LiveStreamStudioScreen extends StatefulWidget {
  const LiveStreamStudioScreen({super.key});

  @override
  State<LiveStreamStudioScreen> createState() => _LiveStreamStudioScreenState();
}

class _LiveStreamStudioScreenState extends State<LiveStreamStudioScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  int _selectedCameraIndex = 0;
  bool _isLive = false;
  bool _isInit = false;
  String _streamStatus = "OFFLINE";
  String _streamTitle = "Sunday Celebration Live";
  int _viewers = 0;
  List<String> _chatMessages = [];

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndInit();
  }

  Future<void> _checkPermissionsAndInit() async {
    final status = await [Permission.camera, Permission.microphone].request();
    if (status[Permission.camera]!.isGranted && status[Permission.microphone]!.isGranted) {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _initCamera(_cameras![0]);
      }
    } else {
      // Handle permission denied
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

  void _startStream() {
    setState(() {
      _isLive = true;
      _streamStatus = "HUB -> R2 HSL STREAM";
    });

    // Simulate HUB Handshake and WebRTC SDP Offer creation
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _streamStatus = "LIVE ON HUB";
        _viewers = 14;
      });
      // Mock viewers joining
      _simulateViewers();
    });
  }

  void _stopStream() {
    setState(() {
      _isLive = false;
      _streamStatus = "OFFLINE";
      _viewers = 0;
      _chatMessages.clear();
    });
    
    // Simulate R2 Archive Processing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Stream Ended. Saving directly to Cloudflare R2..."), backgroundColor: Colors.green),
    );
  }

  void _shareStream() {
    String churchSlug = "grace-church"; // using a sample slug
    String streamId = "live_${DateTime.now().millisecondsSinceEpoch}";
    String streamUrl = "https://live.churchonapp.com/$churchSlug/$streamId";
    
    // In a real app we'd use 'share_plus' or 'clipboard' here
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Church URL Copied: $streamUrl"), backgroundColor: Colors.blue),
    );
  }

  void _simulateViewers() {
    if (!_isLive) return;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLive) {
        setState(() {
          _viewers += 5;
          _chatMessages.add("Amen! powerful word.");
        });
        _simulateViewers();
      }
    });
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
          // Camera Background
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

          // Safe Area UI Overlay
          SafeArea(
            child: Column(
              children: [
                // Top Bar
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

                // Title Overlay
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
                      controller: TextEditingController(text: _streamTitle),
                    ),
                  ),

                const Spacer(),

                // Live Chat Feed (Bottom Left)
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

                // Controls Bar
                Container(
                  padding: const EdgeInsets.only(bottom: 30, top: 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Projection / Cast
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.cast, color: Colors.white, size: 28),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Searching for AirPlay/Chromecast / Wireless IP Cameras...")));
                            },
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

                      // Go Live / Stop Button
                      GestureDetector(
                        onTap: _isLive ? _stopStream : _startStream,
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

                      // Flip Camera
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

