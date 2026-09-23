import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/r2_service.dart';
import 'package:church_on_app/core/services/safe_file_paths.dart';
import 'meeting_service.dart';

enum MeetingRoomState { idle, connecting, live, reconnecting, ended, error }

/// One remote participant in the mesh.
class MeetingPeer {
  final String userId;
  final bool initiator;
  String? name;
  String? avatar;
  MediaStream? stream;
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  final List<RTCIceCandidate> pendingCandidates = [];
  bool rendererReady = false;
  bool remoteReady = false;
  bool connected = false;
  bool muted = false;
  bool videoOff = false;

  MeetingPeer({required this.userId, required this.initiator});
}

/// Real WebRTC mesh for a business meeting. Signalling rides on the
/// `meeting_signaling` table (Supabase Realtime); ICE comes from the existing
/// `turn-credentials` Edge Function with a STUN-only fallback.
class MeetingRoomController extends ChangeNotifier {
  final SupabaseClient client;
  final MeetingService service;
  final String selfId;
  final String selfName;
  final String? selfAvatar;
  final bool isHost;

  MeetingRoomController({
    required this.client,
    required this.service,
    required this.selfId,
    required this.selfName,
    required this.selfAvatar,
    required this.isHost,
  });

  String? _meetingId;

  final Map<String, MeetingPeer> _peers = {};
  List<MeetingPeer> get peers => _peers.values.toList();

  MediaStream? _localStream;
  MediaStream? get localStream => _localStream;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  bool localRendererReady = false;

  MeetingRoomState _state = MeetingRoomState.idle;
  MeetingRoomState get state => _state;

  String? _error;
  String? get error => _error;

  bool _isMuted = false;
  bool get isMuted => _isMuted;
  bool _isVideoOff = false;
  bool get isVideoOff => _isVideoOff;
  bool _audioOnly = false;
  bool get audioOnly => _audioOnly;
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };
  String get iceSource => (_iceServers['iceServers'] as List?)
          ?.any((e) => (e.toString().contains('turn:')) ) ==
      true
      ? 'TURN + STUN'
      : 'STUN only';

  final Set<String> _processed = {};
  DateTime _joinedAt = DateTime.now();
  StreamSubscription<List<MeetingSignal>>? _signalSub;
  StreamSubscription<List<MeetingParticipant>>? _participantSub;
  Timer? _reconnectTimer;

  String? _recordingPath;
  MediaRecorder? _recorder;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  Future<void> init(String meetingId) async {
    _meetingId = meetingId;
    _setState(MeetingRoomState.connecting);
    try {
      await _loadIceServers();
      await _acquireLocalStream();
      await service.joinMeeting(meetingId);
      _joinedAt = DateTime.now().subtract(const Duration(seconds: 3));

      await _subscribeSignals(meetingId);
      _participantSub = service.streamParticipants(meetingId).listen((rows) {
        for (final p in rows) {
          final peer = _peers[p.userId];
          if (peer != null) {
            peer.name = p.fullName ?? peer.name;
            peer.avatar = p.avatarUrl ?? peer.avatar;
            peer.muted = p.isMuted;
            peer.videoOff = p.isVideoOff;
          }
        }
        notifyListeners();
      });

      await service.sendSignal(
        meetingId: meetingId,
        signalType: 'join',
        payload: {'name': selfName},
      );

      _setState(MeetingRoomState.live);
    } catch (e) {
      debugPrint('MeetingRoom init failed: $e');
      _error = _friendlyError(e);
      _setState(MeetingRoomState.error);
      rethrow;
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('full')) return 'This meeting is full.';
    if (s.contains('ended')) return 'This meeting has already ended.';
    if (s.contains('pro_required')) return 'This feature needs the Pro Meeting Suite.';
    if (s.toLowerCase().contains('permission') || s.toLowerCase().contains('denied')) {
      return 'Camera/microphone permission was denied. Enable it in settings and retry.';
    }
    return s.replaceFirst('Exception: ', '');
  }

  Future<void> _loadIceServers() async {
    try {
      final res = await client.functions
          .invoke('turn-credentials')
          .timeout(const Duration(seconds: 6));
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['iceServers'] != null) {
        _iceServers = Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('TURN credentials failed, STUN only: $e');
    }
  }

  Future<void> _acquireLocalStream() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': 1280,
          'height': 720,
          'frameRate': 24,
        },
      });
    } catch (e) {
      debugPrint('camera+mic failed, trying audio only: $e');
      _audioOnly = true;
      _isVideoOff = true;
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
    }
    await localRenderer.initialize();
    localRenderer.srcObject = _localStream;
    localRendererReady = true;
  }

  Future<void> _subscribeSignals(String meetingId) async {
    _signalSub = service.streamSignals(meetingId).listen((signals) {
      for (final s in signals) {
        if (!_processed.add(s.id)) continue;
        if (s.senderId == selfId) continue;
        final created = s.createdAt;
        if (created != null && created.isBefore(_joinedAt)) continue;
        if (s.receiverId != null && s.receiverId != selfId) continue;
        _handleSignal(s);
      }
    });
  }

  // ── Signalling ────────────────────────────────────────────────────────────
  void _handleSignal(MeetingSignal s) {
    switch (s.signalType) {
      case 'join':
        _onPeerJoin(s.senderId);
        break;
      case 'leave':
      case 'end':
        _removePeer(s.senderId);
        break;
      case 'offer':
        _onOffer(s);
        break;
      case 'answer':
        _onAnswer(s);
        break;
      case 'ice':
        _onIce(s);
        break;
      case 'mute':
        if (s.payload?['all'] == true) {
          _isMuted = true;
          _setAudioEnabled(false);
          notifyListeners();
        }
        break;
      case 'unmute':
        break;
      case 'video_on':
      case 'video_off':
        break;
      default:
        break;
    }
  }

  void _onPeerJoin(String userId) {
    final initiator = selfId.compareTo(userId) < 0;
    if (!initiator) return; // the other side will create the offer
    _ensurePeer(userId, initiator: true).then((peer) {
      if (peer != null) _createOffer(peer);
    });
  }

  Future<MeetingPeer?> _ensurePeer(String userId, {required bool initiator}) async {
    final existing = _peers[userId];
    if (existing != null) return existing;
    final peer = MeetingPeer(userId: userId, initiator: initiator);
    _peers[userId] = peer;
    try {
      await peer.renderer.initialize();
      peer.rendererReady = true;
      final pc = await createPeerConnection(_iceServers);
      peer.pc = pc;
      _wirePeer(peer, pc);
      for (final track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
        await pc.addTrack(track, _localStream!);
      }
      notifyListeners();
      return peer;
    } catch (e) {
      debugPrint('ensurePeer failed: $e');
      _removePeer(userId);
      return null;
    }
  }

  void _wirePeer(MeetingPeer peer, RTCPeerConnection pc) {
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      service.sendSignal(
        meetingId: _meetingId!,
        receiverId: peer.userId,
        signalType: 'ice',
        payload: candidate.toMap(),
      );
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        peer.stream = event.streams.first;
        _attachRemote(peer);
      }
    };
    pc.onAddStream = (stream) {
      peer.stream = stream;
      _attachRemote(peer);
    };
    pc.onIceConnectionState = (state) {
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          peer.connected = true;
          notifyListeners();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          peer.connected = false;
          notifyListeners();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          peer.connected = false;
          notifyListeners();
          _scheduleReconnect(peer);
          break;
        default:
          break;
      }
    };
  }

  void _attachRemote(MeetingPeer peer) {
    if (!peer.rendererReady) return;
    peer.renderer.srcObject = peer.stream;
    peer.remoteReady = true;
    peer.connected = true;
    notifyListeners();
  }

  Future<void> _onOffer(MeetingSignal s) async {
    final peer = await _ensurePeer(s.senderId, initiator: false);
    final pc = peer?.pc;
    if (peer == null || pc == null) return;
    final desc = s.payload?['sdp'];
    if (desc == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(desc.toString(), s.payload?['type']?.toString() ?? 'offer'),
    );
    await _drainCandidates(peer);
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await service.sendSignal(
      meetingId: _meetingId!,
      receiverId: peer.userId,
      signalType: 'answer',
      payload: {'sdp': answer.sdp, 'type': answer.type},
    );
  }

  Future<void> _onAnswer(MeetingSignal s) async {
    final peer = _peers[s.senderId];
    final pc = peer?.pc;
    if (peer == null || pc == null) return;
    final desc = s.payload?['sdp'];
    if (desc == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(desc.toString(), s.payload?['type']?.toString() ?? 'answer'),
    );
    await _drainCandidates(peer);
  }

  Future<void> _onIce(MeetingSignal s) async {
    final peer = _peers[s.senderId];
    if (peer == null) return;
    final map = s.payload;
    if (map == null) return;
    final candidate = RTCIceCandidate(
      map['candidate']?.toString(),
      map['sdpMid']?.toString(),
      (map['sdpMLineIndex'] as num?)?.toInt(),
    );
    final pc = peer.pc;
    if (pc == null || !peer.remoteReady) {
      peer.pendingCandidates.add(candidate);
      return;
    }
    try {
      await pc.addCandidate(candidate);
    } catch (e) {
      debugPrint('addCandidate failed: $e');
    }
  }

  Future<void> _drainCandidates(MeetingPeer peer) async {
    final pc = peer.pc;
    if (pc == null) return;
    final pending = List<RTCIceCandidate>.from(peer.pendingCandidates);
    peer.pendingCandidates.clear();
    for (final c in pending) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
  }

  Future<void> _createOffer(MeetingPeer peer) async {
    final pc = peer.pc;
    if (pc == null) return;
    try {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await service.sendSignal(
        meetingId: _meetingId!,
        receiverId: peer.userId,
        signalType: 'offer',
        payload: {'sdp': offer.sdp, 'type': offer.type},
      );
    } catch (e) {
      debugPrint('createOffer failed: $e');
    }
  }

  void _scheduleReconnect(MeetingPeer peer) {
    _setState(MeetingRoomState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      try {
        final pc = peer.pc;
        if (pc == null) return;
        await pc.restartIce();
        final offer = await pc.createOffer({'iceRestart': true});
        await pc.setLocalDescription(offer);
        await service.sendSignal(
          meetingId: _meetingId!,
          receiverId: peer.userId,
          signalType: 'offer',
          payload: {'sdp': offer.sdp, 'type': offer.type},
        );
      } catch (e) {
        debugPrint('reconnect failed: $e');
      } finally {
        if (_state == MeetingRoomState.reconnecting) {
          _setState(MeetingRoomState.live);
        }
      }
    });
  }

  void _removePeer(String userId) {
    final peer = _peers.remove(userId);
    if (peer == null) return;
    try {
      peer.pc?.close();
    } catch (_) {}
    try {
      peer.stream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    if (peer.rendererReady) {
      try {
        peer.renderer.srcObject = null;
        peer.renderer.dispose();
      } catch (_) {}
    }
    notifyListeners();
  }

  // ── Controls ──────────────────────────────────────────────────────────────
  void _setAudioEnabled(bool enabled) {
    for (final t in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = enabled;
    }
  }

  void _setVideoEnabled(bool enabled) {
    for (final t in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = enabled;
    }
  }

  Future<void> toggleMic() async {
    if (_localStream == null) return;
    _isMuted = !_isMuted;
    _setAudioEnabled(!_isMuted);
    notifyListeners();
    await _syncMediaState();
    await _broadcast(_isMuted ? 'mute' : 'unmute');
  }

  Future<void> toggleVideo() async {
    if (_localStream == null) return;
    if (_audioOnly) return;
    _isVideoOff = !_isVideoOff;
    _setVideoEnabled(!_isVideoOff);
    notifyListeners();
    await _syncMediaState();
    await _broadcast(_isVideoOff ? 'video_off' : 'video_on');
  }

  Future<void> switchCamera() async {
    if (_audioOnly) return;
    for (final t in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      try {
        await Helper.switchCamera(t);
      } catch (e) {
        debugPrint('switchCamera failed: $e');
      }
    }
  }

  Future<void> _syncMediaState() async {
    final id = _meetingId;
    if (id == null) return;
    try {
      await service.setMediaState(id, muted: _isMuted, videoOff: _isVideoOff);
    } catch (e) {
      debugPrint('setMediaState failed: $e');
    }
  }

  Future<void> _broadcast(String type) async {
    final id = _meetingId;
    if (id == null) return;
    try {
      await service.sendSignal(meetingId: id, signalType: type);
    } catch (e) {
      debugPrint('broadcast $type failed: $e');
    }
  }

  Future<void> muteAll() async {
    final id = _meetingId;
    if (id == null || !isHost) return;
    await service.muteAll(id);
  }

  // ── Recording (host, Pro, mobile) ─────────────────────────────────────────
  Future<String> startRecording() async {
    final id = _meetingId;
    if (id == null) throw MeetingException('Not in a meeting.');
    if (!isHost) throw MeetingException('Only the host can record.');
    if (kIsWeb) {
      throw MeetingException(
          'Recording is not supported in the browser. Use the mobile app.');
    }
    final ent = await service.getEntitlement();
    if (!ent.recording) {
      throw MeetingException('Recording requires the Pro Meeting Suite.');
    }
    final dirPath = await safeTemporaryDirectoryPath();
    if (dirPath == null) {
      throw MeetingException(
          'Recording is not supported in the browser. Use the mobile app.');
    }
    _recordingPath =
        '$dirPath/meeting_${id}_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final recorder = MediaRecorder();
    await recorder.start(_recordingPath!, audioChannel: RecorderAudioChannel.OUTPUT);
    _recorder = recorder;
    _isRecording = true;
    notifyListeners();
    return _recordingPath!;
  }

  Future<String?> stopRecording() async {
    final id = _meetingId;
    if (_recorder == null || _recordingPath == null || id == null) {
      _isRecording = false;
      notifyListeners();
      return null;
    }
    final path = _recordingPath!;
    try {
      await _recorder!.stop();
    } catch (e) {
      debugPrint('recorder stop failed: $e');
    }
    _recorder = null;
    _isRecording = false;
    notifyListeners();

    try {
      final bytes = await XFile(path).readAsBytes();
      if (bytes.isEmpty) return null;
      final url = await R2Service(client).uploadBytes(
        bytes,
        'meeting-recordings/meeting_${id}_${DateTime.now().millisecondsSinceEpoch}.m4a',
        contentType: 'audio/mp4',
      );
      await service.setRecording(id, url, url != null ? 'ready' : 'failed');
      return url;
    } catch (e) {
      debugPrint('recording upload failed: $e');
      try {
        await service.setRecording(id, null, 'failed');
      } catch (_) {}
      return null;
    } finally {
      _recordingPath = null;
    }
  }

  // ── Leave ─────────────────────────────────────────────────────────────────
  Future<void> leave({bool endForAll = false}) async {
    final id = _meetingId;
    _reconnectTimer?.cancel();
    if (id != null) {
      try {
        if (endForAll && isHost) {
          await service.endMeeting(id);
        } else {
          await service.sendSignal(meetingId: id, signalType: 'leave');
          await service.leaveMeeting(id);
        }
      } catch (e) {
        debugPrint('leave failed: $e');
      }
    }
    await _teardown();
    _setState(MeetingRoomState.ended);
  }

  Future<void> _teardown() async {
    await _signalSub?.cancel();
    await _participantSub?.cancel();
    _signalSub = null;
    _participantSub = null;

    if (_isRecording) {
      try {
        await _recorder?.stop();
      } catch (_) {}
      _recorder = null;
      _isRecording = false;
    }

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    if (localRendererReady) {
      try {
        localRenderer.srcObject = null;
        localRenderer.dispose();
        localRendererReady = false;
      } catch (_) {}
    }

    for (final userId in _peers.keys.toList()) {
      _removePeer(userId);
    }
    _peers.clear();
  }

  void _setState(MeetingRoomState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _signalSub?.cancel();
    _participantSub?.cancel();
    _teardown();
    super.dispose();
  }
}
