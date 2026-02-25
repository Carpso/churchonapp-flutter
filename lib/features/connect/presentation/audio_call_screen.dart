import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/call_service.dart';

class AudioCallScreen extends ConsumerStatefulWidget {
  final String userName;
  final String userAvatar;
  final String? recipientId;
  final CallSession? callSession;

  const AudioCallScreen({
    super.key, 
    required this.userName, 
    required this.userAvatar,
    this.recipientId,
    this.callSession,
  });

  @override
  ConsumerState<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends ConsumerState<AudioCallScreen> {
  bool _isMuted = false;
  bool _isVideo = false;
  bool _isRecording = false;
  String _callStatus = "Ringing...";
  int _seconds = 0;
  Timer? _timer;
  CallSession? _currentSession;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    _currentSession = widget.callSession;
    _callStatus = _currentSession != null ? "Ringing..." : "Dialing...";

    if (_currentSession == null && widget.recipientId != null) {
      _initiateCall();
    } else if (_currentSession != null) {
      _listenToCallStatus();
    }
  }

  Future<void> _initiateCall() async {
    try {
      final session = await ref.read(callServiceProvider).startCall(
        widget.recipientId!, 
        'audio', 
        {'type': 'offer', 'sdp': 'mock_sdp_for_vps'} // In a real app, generate real SDP
      );
      setState(() {
        _currentSession = session;
        _callStatus = "Ringing...";
      });
      _listenToCallStatus();
    } catch (e) {
      setState(() => _callStatus = "Failed");
    }
  }

  void _listenToCallStatus() {
    if (_currentSession == null) return;
    
    // In a real app, we would use a specific stream for THIS call ID
    // For now, we simulate the status change when connected
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _callStatus = "Connected");
      _startTimer();
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  String _formatTime(int seconds) {
    int m = seconds ~/ 60;
    int s = seconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  void _endCall() async {
    setState(() => _callStatus = "Call Ended");
    _timer?.cancel();
    
    if (_currentSession != null) {
      await ref.read(callServiceProvider).endCall(_currentSession!.id);
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827), // gray-900 equivalent
      body: Stack(
        children: [
          // Background Center Info (when video off)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    shape: BoxShape.circle,
                    image: DecorationImage(image: NetworkImage(widget.userAvatar), fit: BoxFit.cover),
                    boxShadow: [
                      BoxShadow(color: Theme.of(context).primaryColor.withOpacity(0.3), blurRadius: 40, spreadRadius: 10)
                    ]
                  ),
                ),
                const SizedBox(height: 25),
                Text(widget.userName, style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_callStatus == "Connected" ? _formatTime(_seconds) : _callStatus, style: TextStyle(fontSize: 18, color: _callStatus == "Call Ended" || _callStatus == "Failed" ? Colors.red : Colors.grey[400])),
              ],
            ),
          ),

          // REC Indicator
          if (_isRecording)
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text("REC ${_formatTime(_seconds)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),

          // Top Header Info
          Positioned(
            top: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text("End-to-End Encrypted", style: TextStyle(color: Colors.white70, fontSize: 10)),
                    ],
                  )
                ],
              ),
            ),
          ),

          // Controls Bar (Glassmorphism inspired)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // REC Button
                _buildGlassButton(
                  isActive: _isRecording,
                  activeColor: Colors.red,
                  child: Container(
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      color: _isRecording ? Colors.white : Colors.transparent
                    ),
                  ),
                  onTap: () => setState(() => _isRecording = !_isRecording),
                ),
                const SizedBox(width: 20),

                // Video Toggle (Audio only for now)
                _buildGlassButton(
                  isActive: _isVideo,
                  child: Icon(_isVideo ? LucideIcons.video : LucideIcons.videoOff, color: _isVideo ? Colors.black : Colors.white),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Video disabled. Audio only active.")));
                  }
                ),
                const SizedBox(width: 20),

                // Mute Toggle
                _buildGlassButton(
                  isActive: _isMuted,
                  child: Icon(_isMuted ? LucideIcons.mic : LucideIcons.micOff, color: _isMuted ? Colors.black : Colors.white),
                  onTap: () => setState(() => _isMuted = !_isMuted),
                ),
                const SizedBox(width: 30),

                // End Call Button
                GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    width: 65, height: 65,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)]
                    ),
                    child: const Center(
                      child: Icon(LucideIcons.phoneOff, color: Colors.white, size: 28),
                    ),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildGlassButton({required Widget child, required bool isActive, required VoidCallback onTap, Color activeColor = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12),
        ),
        child: Center(child: child),
      ),
    );
  }
}

