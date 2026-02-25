import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class Organization {
  final String id;
  final String name;
  final String bishopId;
  final String? secretaryId;
  final String? treasurerId;

  Organization({
    required this.id,
    required this.name,
    required this.bishopId,
    this.secretaryId,
    this.treasurerId,
  });

  factory Organization.fromMap(Map<String, dynamic> map) {
    return Organization(
      id: map['id'],
      name: map['name'],
      bishopId: map['bishop_id'],
      secretaryId: map['secretary_id'],
      treasurerId: map['treasurer_id'],
    );
  }
}

class OrganizationService {
  final SupabaseClient _client;
  OrganizationService(this._client);

  Future<Organization?> getOrganizationByBishop(String bishopId) async {
    final data = await _client
        .from('organizations')
        .select('*')
        .eq('bishop_id', bishopId)
        .maybeSingle();
    return data != null ? Organization.fromMap(data) : null;
  }

  Stream<List<Tenant>> streamLinkedChurches(String orgId) {
    return _client
        .from('churches')
        .stream(primaryKey: ['id'])
        .eq('organization_id', orgId)
        .map((data) => data.map((map) => Tenant.fromMap(map)).toList());
  }

  Future<void> linkChurchToOrg(String churchId, String orgId) async {
    await _client
        .from('churches')
        .update({'organization_id': orgId})
        .eq('id', churchId);
  }

  Future<void> submitPastorReport({
    required String pastorId,
    required String orgId,
    required String content,
    required Map<String, dynamic> stats,
  }) async {
    await _client.from('pastor_reports').insert({
      'pastor_id': pastorId,
      'organization_id': orgId,
      'content': content,
      'aggregated_stats': stats,
      'status': 'pending', // pending, reviewed by secretary, seen by bishop
    });
  }

  Stream<List<Map<String, dynamic>>> streamPastorReports(String orgId) {
    return _client
        .from('pastor_reports')
        .stream(primaryKey: ['id'])
        .eq('organization_id', orgId)
        .order('created_at', ascending: false);
  }
}

final organizationServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return OrganizationService(client);
});

