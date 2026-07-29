import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

class _AudioCallScreenState extends ConsumerState<AudioCallScreen> with SingleTickerProviderStateMixin {
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isRecording = false;
  String _callStatus = 'Dialing…';
  int _seconds = 0;
  Timer? _timer;
  CallSession? _currentSession;
  late AnimationController _pulseAnim;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  StreamSubscription? _callSubscription;
  StreamSubscription? _candidatesSubscription;
  bool _isCaller = false;
  int _iceRestartCount = 0;
  static const int _maxIceRestarts = 3;

  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {
        'urls': 'turn:turn.anyfirewall.com:3478',
        'username': '',
        'credential': '',
      },
    ],
  };

  @override
  void initState() {
    super.initState();
    _currentSession = widget.callSession;
    _isCaller = _currentSession == null && widget.recipientId != null;
    _callStatus = _currentSession != null ? 'Ringing…' : 'Dialing…';

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _initWebRTCAndCall());
  }

  Future<void> _initWebRTCAndCall() async {
    try {
      await _createPeerConnection();
      await _getLocalStream();
      if (_isCaller) {
        await _initiateCall();
      } else if (_currentSession != null) {
        await _acceptIncomingCall();
      }
    } catch (e) {
      if (mounted) setState(() => _callStatus = 'Failed to connect');
    }
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    _peerConnection!.onIceCandidate = (candidate) {
      if (_currentSession != null) {
        ref.read(callServiceProvider).addCandidate(
          _currentSession!.id,
          candidate.toMap(),
          _isCaller ? 'caller' : 'callee',
        );
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        debugPrint('ICE connection failed, attempting restart...');
        _attemptIceRestart();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        debugPrint('ICE connection disconnected, waiting for recovery...');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        debugPrint('ICE connection established');
      }
    };
  }

  Future<void> _getLocalStream() async {
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    for (final track in _localStream!.getAudioTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  Future<void> _initiateCall() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    final session = await ref.read(callServiceProvider).startCall(
      widget.recipientId!,
      'audio',
      offer.toMap(),
    );

    if (mounted) {
      setState(() {
        _currentSession = session;
        _callStatus = 'Ringing…';
      });
      _listenForRemoteAnswer(session.id);
      _listenForIceCandidates(session.id);
    }
  }

  void _listenForRemoteAnswer(String callId) {
    _callSubscription = ref.read(callServiceProvider).streamCall(callId).listen((call) {
      if (call.answer != null && _peerConnection != null) {
        final answer = RTCSessionDescription(call.answer!['sdp'], call.answer!['type']);
        _peerConnection!.setRemoteDescription(answer);
        if (mounted) {
          setState(() => _callStatus = 'Connected');
          _startTimer();
        }
      }
    });
  }

  void _listenForIceCandidates(String callId) {
    final expectedType = _isCaller ? 'callee' : 'caller';
    _candidatesSubscription = ref.read(callServiceProvider).getCandidatesStream(callId).listen((candidates) async {
      for (final c in candidates) {
        if (c['type'] != expectedType) continue;
        final candidate = RTCIceCandidate(
          c['candidate']['candidate'],
          c['candidate']['sdpMid'],
          c['candidate']['sdpMLineIndex'],
        );
        await _peerConnection?.addCandidate(candidate);
      }
    });
  }

  Future<void> _acceptIncomingCall() async {
    final offerMap = _currentSession!.offer!;
    final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
    await _peerConnection!.setRemoteDescription(offer);

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await ref.read(callServiceProvider).acceptCall(
      _currentSession!.id,
      answer.toMap(),
    );

    if (mounted) {
      setState(() => _callStatus = 'Connected');
      _startTimer();
    }

    _listenForIceCandidates(_currentSession!.id);
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  String _formatDuration(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _attemptIceRestart() async {
    if (_iceRestartCount >= _maxIceRestarts || _peerConnection == null) {
      _endCall();
      return;
    }
    _iceRestartCount++;
    if (mounted) setState(() => _callStatus = 'Reconnecting…');

    try {
      await _peerConnection!.restartIce();
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      if (_currentSession != null) {
        await ref.read(callServiceProvider).startCall(
          _currentSession!.recipientId,
          'audio',
          offer.toMap(),
        );
      }
    } catch (e) {
      debugPrint('ICE restart failed: $e');
      _endCall();
    }
  }

  void _endCall() async {
    setState(() => _callStatus = 'Call Ended');
    _timer?.cancel();
    _callSubscription?.cancel();
    _candidatesSubscription?.cancel();

    if (_currentSession != null) {
      try {
        await ref.read(callServiceProvider).endCall(_currentSession!.id);
      } catch (e) {
        debugPrint('Failed to end call session: $e');
      }
    }

    _localStream?.getAudioTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    _peerConnection?.close();
    _peerConnection = null;

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _callSubscription?.cancel();
    _candidatesSubscription?.cancel();
    _localStream?.getAudioTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _peerConnection?.close();
    _pulseAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _callStatus == 'Connected';
    final hasEnded = _callStatus == 'Call Ended' || _callStatus == 'Failed to connect';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.3),
                radius: 0.9,
                colors: [Color(0xFF1E3A5F), Color(0xFF0F172A)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.lock, color: Colors.greenAccent, size: 12),
                        SizedBox(width: 6),
                        Text('End-to-End Encrypted',
                            style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 60),
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isConnected)
                          Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF075E54)
                                  .withValues(alpha: _pulseAnim.value * 0.25),
                            ),
                          ),
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isConnected
                                  ? Colors.greenAccent.withValues(alpha: 0.6)
                                  : const Color(0xFF075E54).withValues(alpha: 0.5),
                              width: 3,
                            ),
                            image: DecorationImage(
                              image: CachedNetworkImageProvider(widget.userAvatar),
                              fit: BoxFit.cover,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isConnected
                                    ? Colors.greenAccent.withValues(alpha: _pulseAnim.value * 0.3)
                                    : Colors.transparent,
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  widget.userName,
                  style: const TextStyle(
                    fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                ),
                const SizedBox(height: 10),
                Text(
                  isConnected ? _formatDuration(_seconds) : _callStatus,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: hasEnded
                        ? Colors.red
                        : isConnected
                            ? Colors.greenAccent
                            : Colors.white54,
                  ),
                ),
                const Spacer(),
                if (_isRecording)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _BlinkingDot(),
                          const SizedBox(width: 8),
                          Text('REC ${_formatDuration(_seconds)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildGlassBtn(
                        icon: LucideIcons.circle,
                        label: _isRecording ? 'Stop' : 'Record',
                        isActive: _isRecording,
                        activeColor: Colors.red,
                        onTap: () => setState(() => _isRecording = !_isRecording),
                      ),
                      _buildGlassBtn(
                        icon: _isSpeakerOn ? LucideIcons.volume2 : LucideIcons.volumeX,
                        label: 'Speaker',
                        isActive: _isSpeakerOn,
                        activeColor: Colors.amber,
                        onTap: () async {
                          setState(() => _isSpeakerOn = !_isSpeakerOn);
                          try {
                            await Helper.setSpeakerphoneOn(_isSpeakerOn);
                          } catch (e) {
                            debugPrint('Failed to toggle speakerphone: $e');
                          }
                        },
                      ),
                      GestureDetector(
                        onTap: _endCall,
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 20)],
                          ),
                          child: const Center(child: Icon(LucideIcons.phoneOff, color: Colors.white, size: 26)),
                        ),
                      ),
                      _buildGlassBtn(
                        icon: _isMuted ? LucideIcons.micOff : LucideIcons.mic,
                        label: _isMuted ? 'Unmute' : 'Mute',
                        isActive: _isMuted,
                        activeColor: Colors.red,
                        onTap: () {
                          setState(() {
                            _isMuted = !_isMuted;
                            if (_localStream != null) {
                              for (final track in _localStream!.getAudioTracks()) {
                                track.enabled = !_isMuted;
                              }
                            }
                          });
                        },
                      ),
                      _buildGlassBtn(
                        icon: LucideIcons.grid,
                        label: 'Keypad',
                        isActive: false,
                        activeColor: Colors.white,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Keypad coming soon")),
                          );
                        },
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

  Widget _buildGlassBtn({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive ? activeColor.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? activeColor.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Center(child: Icon(icon, color: isActive ? activeColor : Colors.white, size: 22)),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: isActive ? activeColor : Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
    );
  }
}
