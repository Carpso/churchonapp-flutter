import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserSession {
  final String id;
  final String userId;
  final String? deviceInfo;
  final String? ipAddress;
  final DateTime lastActiveAt;
  final DateTime createdAt;
  final bool isActive;

  UserSession({
    required this.id,
    required this.userId,
    this.deviceInfo,
    this.ipAddress,
    required this.lastActiveAt,
    required this.createdAt,
    required this.isActive,
  });

  factory UserSession.fromMap(Map<String, dynamic> map) => UserSession(
    id: map['id']?.toString() ?? '',
    userId: map['user_id']?.toString() ?? '',
    deviceInfo: map['device_info']?.toString(),
    ipAddress: map['ip_address']?.toString(),
    lastActiveAt: DateTime.tryParse(map['last_active_at']?.toString() ?? '') ?? DateTime.now(),
    createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    isActive: map['is_active'] == true,
  );
}

class SessionService {
  final SupabaseClient _client;
  SessionService(this._client);

  Future<void> recordSession({String? deviceInfo, String? ipAddress}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('user_sessions').insert({
      'user_id': user.id,
      'device_info': deviceInfo,
      'ip_address': ipAddress,
      'is_active': true,
    });
  }

  Future<void> logoutSession(String sessionId) async {
    await _client.from('user_sessions').update({'is_active': false}).eq('id', sessionId);
  }

  Future<void> logoutAllSessions() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('user_sessions')
        .update({'is_active': false})
        .eq('user_id', user.id)
        .eq('is_active', true);
  }

  Stream<List<UserSession>> getActiveSessions() {
    final user = _client.auth.currentUser;
    if (user == null) return const Stream.empty();
    return _client
        .from('user_sessions')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => UserSession.fromMap(map)).toList());
  }

  Future<List<UserSession>> getAllSessions({String? userId}) async {
    List<Map<String, dynamic>> data;
    if (userId != null) {
      data = List<Map<String, dynamic>>.from(
        await _client.from('user_sessions').select().eq('user_id', userId).order('created_at', ascending: false),
      );
    } else {
      data = List<Map<String, dynamic>>.from(
        await _client.from('user_sessions').select().order('created_at', ascending: false),
      );
    }
    return data.map((map) => UserSession.fromMap(map)).toList();
  }
}

final sessionServiceProvider = Provider((ref) => SessionService(Supabase.instance.client));

final activeSessionsProvider = StreamProvider<List<UserSession>>((ref) {
  return ref.watch(sessionServiceProvider).getActiveSessions();
});
