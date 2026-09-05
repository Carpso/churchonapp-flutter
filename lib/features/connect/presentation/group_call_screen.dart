import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/supabase_service.dart';

class _Participant {
  final String id;
  final String name;
  final String avatar;
  final bool isMe;
  bool isMuted;

  _Participant({
    required this.id,
    required this.name,
    required this.avatar,
    this.isMe = false,
    this.isMuted = false,
  });
}

class GroupCallScreen extends ConsumerStatefulWidget {
  final String groupName;
  final String groupAvatar;
  final String groupId;

  const GroupCallScreen({
    super.key,
    required this.groupName,
    required this.groupAvatar,
    required this.groupId,
  });

  @override
  ConsumerState<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends ConsumerState<GroupCallScreen> with TickerProviderStateMixin {
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoOn = false;
  String _callStatus = 'Connecting…';
  int _seconds = 0;
  Timer? _timer;
  late AnimationController _pulseAnim;

  MediaStream? _localStream;
  final List<_Participant> _participants = [];
  final Map<String, RTCPeerConnection> _peerConnections = {};

  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initLocalStream();
    _loadParticipants();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _callStatus = 'Connected');
        _startTimer();
      }
    });
  }

  Future<void> _initLocalStream() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googEchoCancellation': true,
          'googAutoGainControl': true,
          'googNoiseSuppression': true,
          'googHighpassFilter': true,
        },
        'video': false,
      });
      for (final t in _localStream!.getAudioTracks()) {
        t.enabled = true;
      }
      try { await Helper.setSpeakerphoneOn(_isSpeakerOn); } catch (_) {}
    } catch (e) {
      debugPrint('Failed to get local stream: $e');
      // Fallback plain audio
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
      } catch (_) {}
    }
  }

  Future<void> _loadParticipants() async {
    try {
      final client = ref.read(supabaseServiceProvider).client;
      final currentUserId = client.auth.currentUser?.id;

      // community_group_members.user_id FKs to auth.users (not profiles.id), so
      // PostgREST cannot embed profiles directly. Fetch memberships, then a
      // separate profiles query, and shape as {user_id, profiles: {...}}.
      final members = List<Map<String, dynamic>>.from(await client
          .from('community_group_members')
          .select('user_id')
          .eq('group_id', widget.groupId));

      final userIds = members.map((m) => m['user_id']?.toString()).whereType<String>().toSet().toList();
      Map<String, Map<String, dynamic>> profileMap = {};
      if (userIds.isNotEmpty) {
        try {
          final res = await client
              .from('profiles')
              .select('id, full_name, avatar_url, username')
              .inFilter('id', userIds);
          for (final row in (res as List)) {
            profileMap[row['id']?.toString() ?? ''] = Map<String, dynamic>.from(row);
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _participants.add(_Participant(
            id: currentUserId ?? '',
            name: 'You',
            avatar: '',
            isMe: true,
            isMuted: _isMuted,
          ));

          for (final m in members) {
            final userId = m['user_id'] as String?;
            if (userId != null && userId != currentUserId) {
              final profile = profileMap[userId];
              _participants.add(_Participant(
                id: userId,
                name: profile?['full_name'] ?? profile?['username'] ?? 'User',
                avatar: profile?['avatar_url'] ?? '',
                isMe: false,
              ));
            }
          }

          _setupMeshConnections();
        });
      }
    } catch (e) {
      debugPrint('Failed to load participants: $e');
    }
  }

  Future<void> _setupMeshConnections() async {
    for (final p in _participants) {
      if (p.isMe || _localStream == null) continue;
      try {
        final pc = await createPeerConnection(_iceServers);
        for (final track in _localStream!.getAudioTracks()) {
          await pc.addTrack(track, _localStream!);
        }
        pc.onIceConnectionState = (state) {
          if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
              state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
            pc.close();
          }
        };
        _peerConnections[p.id] = pc;
      } catch (e) {
        debugPrint('Failed to create peer connection for ${p.name}: $e');
      }
    }
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

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      if (_localStream != null) {
        for (final track in _localStream!.getAudioTracks()) {
          track.enabled = !_isMuted;
        }
      }
      for (final p in _participants) {
        if (p.isMe) p.isMuted = _isMuted;
      }
    });
  }

  Future<void> _toggleParticipantMute(String userId) async {
    setState(() {
      for (final p in _participants) {
        if (p.id == userId) {
          p.isMuted = !p.isMuted;
        }
      }
    });

    final pc = _peerConnections[userId];
    if (pc != null) {
      final senders = await pc.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'audio') {
          sender.track?.enabled = !_participants.firstWhere((p) => p.id == userId).isMuted;
        }
      }
    }
  }

  void _endCall() {
    _timer?.cancel();
    _localStream?.getAudioTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    for (final pc in _peerConnections.values) {
      pc.close();
    }
    _peerConnections.clear();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseAnim.dispose();
    _localStream?.getAudioTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    for (final pc in _peerConnections.values) {
      pc.close();
    }
    _peerConnections.clear();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A1628), Color(0xFF1A3A5C), Color(0xFF0A1628)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _endCall,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.groupName,
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              _callStatus == 'Connected'
                                  ? '${_participants.length} participants · ${_formatDuration(_seconds)}'
                                  : _callStatus,
                              style: TextStyle(
                                color: _callStatus == 'Connected'
                                    ? Colors.greenAccent
                                    : Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.lock, color: Colors.greenAccent, size: 10),
                            SizedBox(width: 4),
                            Text('E2E', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _participants.length <= 2 ? 1 : 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: _participants.length <= 2 ? 1.5 : 1.0,
                      ),
                      itemCount: _participants.length,
                      itemBuilder: (context, index) {
                        return _buildParticipantCard(_participants[index], size);
                      },
                    ),
                  ),
                ),
                _buildControlsBar(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantCard(_Participant participant, Size size) {
    final isSpeaking = !participant.isMuted && _callStatus == 'Connected';

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        final glowOpacity = isSpeaking ? _pulseAnim.value * 0.5 : 0.0;
        return GestureDetector(
          onLongPress: participant.isMe
              ? null
              : () => _toggleParticipantMute(participant.id),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSpeaking
                    ? Colors.greenAccent.withValues(alpha: glowOpacity + 0.3)
                    : Colors.white.withValues(alpha: 0.08),
                width: isSpeaking ? 2.5 : 1,
              ),
              color: const Color(0xFF1A2D4A),
              boxShadow: isSpeaking
                  ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: glowOpacity * 0.5), blurRadius: 15, spreadRadius: 2)]
                  : null,
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundImage: CachedNetworkImageProvider(participant.avatar),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        participant.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (isSpeaking)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('Speaking…', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                        ),
                    ],
                  ),
                ),
                if (participant.isMuted)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.9), shape: BoxShape.circle),
                      child: const Icon(LucideIcons.micOff, color: Colors.white, size: 12),
                    ),
                  ),
                if (participant.isMe)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('You',
                          style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlsBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2D4A),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildCtrlBtn(
            icon: _isMuted ? LucideIcons.micOff : LucideIcons.mic,
            label: _isMuted ? 'Unmute' : 'Mute',
            isActive: _isMuted,
            activeColor: Colors.red,
            onTap: _toggleMute,
          ),
          _buildCtrlBtn(
            icon: _isSpeakerOn ? LucideIcons.volume2 : LucideIcons.volumeX,
            label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
            isActive: _isSpeakerOn,
            activeColor: const Color(0xFF1A1A1A),
            onTap: () {
              setState(() => _isSpeakerOn = !_isSpeakerOn);
              try {
                Helper.setSpeakerphoneOn(_isSpeakerOn);
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
                boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: 2)],
              ),
              child: const Center(child: Icon(LucideIcons.phoneOff, color: Colors.white, size: 26)),
            ),
          ),
          _buildCtrlBtn(
            icon: _isVideoOn ? LucideIcons.video : LucideIcons.videoOff,
            label: 'Video',
            isActive: _isVideoOn,
            activeColor: const Color(0xFF1A1A1A),
            onTap: () {
              setState(() => _isVideoOn = !_isVideoOn);
              if (_isVideoOn) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Video coming soon — audio call active'), backgroundColor: Colors.orange),
                );
                setState(() => _isVideoOn = false);
              }
            },
          ),
          _buildCtrlBtn(
            icon: LucideIcons.userPlus,
            label: 'Add',
            isActive: false,
            activeColor: Colors.amber,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite sent to group members!'), backgroundColor: Colors.green),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCtrlBtn({
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
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isActive ? activeColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? activeColor : Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Center(child: Icon(icon, color: isActive ? activeColor : Colors.white, size: 22)),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: isActive ? activeColor : Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}
