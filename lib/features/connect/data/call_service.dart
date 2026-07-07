import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CallStatus { dialing, ringing, connected, rejected, ended }

class CallSession {
  final String id;
  final String callerId;
  final String recipientId;
  final String type;
  final CallStatus status;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;

  CallSession({
    required this.id,
    required this.callerId,
    required this.recipientId,
    required this.type,
    required this.status,
    this.offer,
    this.answer,
  });

  factory CallSession.fromMap(Map<String, dynamic> map) {
    return CallSession(
      id: map['id'],
      callerId: map['caller_id'],
      recipientId: map['recipient_id'],
      type: map['type'] ?? 'video',
      status: CallStatus.values.firstWhere(
        (e) => e.name == (map['status'] ?? 'dialing'),
        orElse: () => CallStatus.dialing,
      ),
      offer: map['offer'],
      answer: map['answer'],
    );
  }
}

class CallService {
  final _client = Supabase.instance.client;

  Stream<List<CallSession>> get incomingCallsStream {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();

    return _client
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('recipient_id', userId)
        .map((data) => data
            .where((e) => e['status'] == 'dialing')
            .map((e) => CallSession.fromMap(e))
            .toList());
  }

  Future<CallSession> startCall(String recipientId, String type, Map<String, dynamic> offer) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception("User not authenticated");

    final res = await _client.from('calls').insert({
      'caller_id': userId,
      'recipient_id': recipientId,
      'type': type,
      'status': 'dialing',
      'offer': offer,
    }).select().single();

    return CallSession.fromMap(res);
  }

  Future<void> acceptCall(String callId, Map<String, dynamic> answer) async {
    await _client.from('calls').update({
      'status': 'connected',
      'answer': answer,
    }).eq('id', callId);
  }

  Future<void> rejectCall(String callId) async {
    await _client.from('calls').update({
      'status': 'rejected',
    }).eq('id', callId);
  }

  Future<void> endCall(String callId) async {
    await _client.from('calls').update({
      'status': 'ended',
    }).eq('id', callId);
  }

  Future<void> addCandidate(String callId, Map<String, dynamic> candidate, String type) async {
    await _client.from('call_candidates').insert({
      'call_id': callId,
      'type': type,
      'candidate': candidate,
    });
  }

  Stream<List<Map<String, dynamic>>> getCandidatesStream(String callId) {
    return _client
        .from('call_candidates')
        .stream(primaryKey: ['id'])
        .eq('call_id', callId)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  Stream<CallSession> streamCall(String callId) {
    return _client
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('id', callId)
        .map((data) => CallSession.fromMap(data.first));
  }
}

final callServiceProvider = Provider((ref) => CallService());

final incomingCallStreamProvider = StreamProvider<CallSession?>((ref) {
  final service = ref.watch(callServiceProvider);
  return service.incomingCallsStream.map((calls) => calls.isNotEmpty ? calls.first : null);
});

