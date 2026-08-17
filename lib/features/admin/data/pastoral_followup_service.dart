import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PastoralFollowup {
  final String id;
  final String tenantId;
  final String memberId;
  final String followupType;
  final String notes;
  final String status;
  final DateTime? followUpAt;
  final DateTime? completedAt;
  final String? createdBy;
  final DateTime createdAt;

  const PastoralFollowup({
    required this.id,
    required this.tenantId,
    required this.memberId,
    required this.followupType,
    required this.notes,
    required this.status,
    required this.followUpAt,
    required this.completedAt,
    required this.createdBy,
    required this.createdAt,
  });

  bool get isOpen => status == 'open';

  factory PastoralFollowup.fromMap(Map<String, dynamic> map) {
    return PastoralFollowup(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      memberId: map['member_id'] as String,
      followupType: map['followup_type'] as String? ?? 'visit',
      notes: map['notes'] as String? ?? '',
      status: map['status'] as String? ?? 'open',
      followUpAt: map['follow_up_at'] != null
          ? DateTime.tryParse(map['follow_up_at'] as String)
          : null,
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'] as String)
          : null,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String) ?? DateTime.now(),
    );
  }
}

class PastoralFollowupService {
  PastoralFollowupService(this._client);
  final SupabaseClient _client;

  Stream<List<PastoralFollowup>> followupsStream(String tenantId) {
    return _client
        .from('pastoral_followups')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(PastoralFollowup.fromMap).toList());
  }

  Future<List<Map<String, dynamic>>> members(String tenantId) async {
    final rows = await _client
        .from('profiles')
        .select('id, full_name, avatar_url')
        .eq('tenant_id', tenantId)
        .order('full_name');
    return rows;
  }

  Future<void> create({
    required String tenantId,
    required String memberId,
    required String followupType,
    String notes = '',
    DateTime? followUpAt,
  }) async {
    await _client.from('pastoral_followups').insert({
      'tenant_id': tenantId,
      'member_id': memberId,
      'followup_type': followupType,
      'notes': notes,
      'follow_up_at': followUpAt?.toIso8601String(),
    });
  }

  Future<void> setStatus(String id, String status) async {
    await _client.from('pastoral_followups').update({
      'status': status,
      if (status == 'done') 'completed_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> remove(String id) async {
    await _client.from('pastoral_followups').delete().eq('id', id);
  }
}

final pastoralFollowupServiceProvider = Provider<PastoralFollowupService>((ref) {
  return PastoralFollowupService(Supabase.instance.client);
});

StreamProvider<List<PastoralFollowup>> pastoralFollowupsProvider(String tenantId) {
  return StreamProvider.autoDispose<List<PastoralFollowup>>((ref) {
    return ref.watch(pastoralFollowupServiceProvider).followupsStream(tenantId);
  });
}
