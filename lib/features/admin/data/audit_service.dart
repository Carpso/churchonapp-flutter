import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuditService {
  final SupabaseClient _client;
  AuditService(this._client);

  Future<void> logAction({
    required String action,
    required String entityType,
    String? entityId,
    Map<String, dynamic> details = const {},
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('admin_audit_log').insert({
      'admin_id': user.id,
      'admin_email': user.email,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'details': details,
    });
  }

  Stream<List<Map<String, dynamic>>> getAuditLogStream({int limit = 100}) {
    return _client
        .from('admin_audit_log')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(limit)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  Future<List<Map<String, dynamic>>> getRecentAuditLogs({int limit = 50}) async {
    final res = await _client
        .from('admin_audit_log')
        .select('*, profiles:admin_id(full_name, avatar_url)')
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> logChurchAction({
    required String action,
    required String churchId,
    String? churchName,
    Map<String, dynamic> details = const {},
  }) async {
    await logAction(
      action: action,
      entityType: 'church',
      entityId: churchId,
      details: {'church_name': churchName, ...details},
    );
  }

  Future<void> logRoleChange({
    required String targetUserId,
    required String oldRole,
    required String newRole,
  }) async {
    await logAction(
      action: 'role_change',
      entityType: 'profile',
      entityId: targetUserId,
      details: {'old_role': oldRole, 'new_role': newRole},
    );
  }

  Future<void> logPaymentAction({
    required String action,
    required String paymentId,
    double? amount,
    String? churchName,
  }) async {
    await logAction(
      action: action,
      entityType: 'payment',
      entityId: paymentId,
      details: {'amount': amount, 'church_name': churchName},
    );
  }
}

final auditServiceProvider = Provider((ref) => AuditService(Supabase.instance.client));

final auditLogStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(auditServiceProvider).getAuditLogStream();
});
