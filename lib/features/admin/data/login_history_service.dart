import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoginRecord {
  final String id;
  final String userId;
  final String? ipAddress;
  final String? deviceInfo;
  final String? userAgent;
  final String? location;
  final String status;
  final String? failureReason;
  final DateTime createdAt;

  LoginRecord({
    required this.id,
    required this.userId,
    this.ipAddress,
    this.deviceInfo,
    this.userAgent,
    this.location,
    required this.status,
    this.failureReason,
    required this.createdAt,
  });

  factory LoginRecord.fromMap(Map<String, dynamic> map) => LoginRecord(
    id: map['id']?.toString() ?? '',
    userId: map['user_id']?.toString() ?? '',
    ipAddress: map['ip_address']?.toString(),
    deviceInfo: map['device_info']?.toString(),
    userAgent: map['user_agent']?.toString(),
    location: map['location']?.toString(),
    status: map['status']?.toString() ?? 'success',
    failureReason: map['failure_reason']?.toString(),
    createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
  );
}

class LoginHistoryService {
  final SupabaseClient _client;
  LoginHistoryService(this._client);

  Future<void> recordLogin({
    String? ipAddress,
    String? deviceInfo,
    String? userAgent,
    String? location,
    String status = 'success',
    String? failureReason,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('login_history').insert({
      'user_id': user.id,
      'ip_address': ipAddress,
      'device_info': deviceInfo,
      'user_agent': userAgent,
      'location': location,
      'status': status,
      'failure_reason': failureReason,
    });
  }

  Future<List<LoginRecord>> getLoginHistory({int limit = 20}) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final data = await _client.from('login_history')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).map((map) => LoginRecord.fromMap(map)).toList();
  }
}

final loginHistoryServiceProvider = Provider((ref) => LoginHistoryService(Supabase.instance.client));
