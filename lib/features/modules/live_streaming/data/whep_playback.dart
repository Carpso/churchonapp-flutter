import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Plays a Cloudflare Stream WebRTC (WHEP) broadcast.
///
/// WHY this exists: Cloudflare Stream does not record or emit HLS/DASH for a
/// broadcast published over WHIP (WebRTC). A WHIP-ingested service therefore
/// never produces a playable HLS manifest — `…/<input_uid>/manifest/video.m3u8`
/// answers HTTP 204 for the whole broadcast, which is why viewers were stuck on
/// "Stream is starting…". The playable URL for a phone-camera broadcast is its
/// WHEP endpoint (`webRTCPlayback.url` = `<customer>/<input_uid>/webRTC/play`).
///
/// This client POSTs a recvonly SDP offer to that endpoint and renders the
/// media Cloudflare answers with. It is transport-agnostic (works on Android,
/// iOS and web) and needs no extra plugin — flutter_webrtc is already bundled.
class WhepPlayback {
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  String? _resourceUrl;
  bool _connecting = false;
  bool _disposed = false;

  bool get isConnected => _pc != null && !_disposed;

  /// ICE servers for playback.
  ///
  /// TURN IS NOT OPTIONAL HERE. This used to be hardcoded STUN-only while the
  /// BROADCASTER fetched real TURN credentials — an asymmetry that worked in
  /// the studio and failed in the pews: any viewer behind symmetric NAT (most
  /// mobile carriers, many office and WiFi networks) could not establish a WHEP
  /// session at all and simply saw "cannot play". Both sides need the same ICE
  /// capability.
  static Map<String, dynamic> _iceConfig({Map<String, dynamic>? turn}) {
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];

    final raw = turn?['iceServers'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map && e['urls'] != null) {
          servers.add(Map<String, dynamic>.from(e));
        }
      }
    }
    return {'iceServers': servers, 'sdpSemantics': 'unified-plan'};
  }

  /// Fetches short-lived TURN credentials. Returns null on any failure so the
  /// viewer degrades to STUN instead of refusing to play.
  static Future<Map<String, dynamic>?> _fetchTurn() async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke('turn-credentials')
          .timeout(const Duration(seconds: 6));
      final data = res.data;
      if (data is Map && data['iceServers'] != null) {
        return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('[Whep] TURN fetch failed, STUN-only: $e');
    }
    return null;
  }

  /// Connects to [whepUrl] and starts rendering the incoming stream.
  Future<void> connect(String whepUrl) async {
    if (_connecting || _disposed) return;
    _connecting = true;
    await renderer.initialize();

    final turn = await _fetchTurn();
    if (_disposed) return;
    final pc = await createPeerConnection(_iceConfig(turn: turn));
    _pc = pc;

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        renderer.srcObject = event.streams[0];
      }
    };

    // Receive-only transceivers: we never publish from the viewer.
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    final sdp = offer.sdp;
    if (sdp == null || sdp.isEmpty) {
      throw Exception('Could not build a WebRTC playback offer');
    }

    // WHEP is a single POST of the offer SDP; the answer comes back in the body
    // and the session resource (for teardown) in the `Location` header.
    final res = await http.post(
      Uri.parse(whepUrl),
      headers: {'Content-Type': 'application/sdp'},
      body: sdp,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('WHEP playback failed (${res.statusCode})');
    }
    final location = res.headers['location'];
    if (location != null && location.isNotEmpty) {
      _resourceUrl = Uri.parse(whepUrl).resolve(location).toString();
    }
    final answer = res.body;
    if (answer.trim().isEmpty || answer.trim().startsWith('{')) {
      throw Exception('WHEP endpoint did not return a session description');
    }
    await pc.setRemoteDescription(
      RTCSessionDescription(answer, 'answer'),
    );
    debugPrint('[WHEP] playback session established');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final url = _resourceUrl;
    _resourceUrl = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      renderer.srcObject = null;
    } catch (_) {}
    try {
      await renderer.dispose();
    } catch (_) {}
    // Release the server-side WHEP resource (best effort).
    if (url != null) {
      try {
        await http.delete(Uri.parse(url));
      } catch (_) {}
    }
  }
}
