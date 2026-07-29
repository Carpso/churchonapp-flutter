import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fundraising_models.dart';

class FundraisingService {
  final SupabaseClient _client;

  FundraisingService(this._client);

  Stream<List<FundraisingVenture>> getVenturesStream(String tenantId, String userId) {
    return _client
        .from('fundraising_ventures')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false)
        .map((data) => (data as List)
            .map((m) => FundraisingVenture.fromMap(m))
            .where((v) => v.status == 'active')
            .toList());
  }

  Future<FundraisingVenture> getVenture(String id) async {
    final data = await _client
        .from('fundraising_ventures')
        .select('id, tenant_id, title, description, category, target_amount, raised_amount, currency, status, start_date, end_date, image_url, allow_other_tenants, allowed_tenant_ids, created_by, created_at')
        .eq('id', id)
        .single();
    return FundraisingVenture.fromMap(data);
  }

  Future<String> createVenture({
    required String tenantId,
    required String title,
    required String description,
    required String category,
    required double targetAmount,
    required String currency,
    required bool allowOtherTenants,
    List<String> allowedTenantIds = const [],
    String? imageUrl,
    DateTime? endDate,
    String? createdBy,
  }) async {
    final data = await _client.from('fundraising_ventures').insert({
      'tenant_id': tenantId,
      'title': title,
      'description': description,
      'category': category,
      'target_amount': targetAmount,
      'currency': currency,
      'allow_other_tenants': allowOtherTenants,
      'allowed_tenant_ids': allowedTenantIds,
      'image_url': imageUrl,
      'end_date': endDate?.toIso8601String(),
      'created_by': createdBy,
    }).select('id').single();

    // Notify church members about new fundraising campaign
    try {
      final others = await _client
          .from('profiles')
          .select('id')
          .eq('tenant_id', tenantId)
          .limit(500);
      if (others.isNotEmpty) {
        await _client.functions.invoke('push-notifications', body: {
          'userIds': others.map((o) => o['id'] as String).toList(),
          'title': 'New Fundraising Campaign',
          'body': '$title has been launched. Target: $currency ${targetAmount.toStringAsFixed(0)}',
          'data': {
            'type': 'fundraising',
            'reference_id': data['id'],
            'channel_id': 'coa_announcements',
          },
        });
      }
    } catch (e) {
      debugPrint('[FundraisingService] Venture notification failed: $e');
    }

    return data['id'];
  }

  Future<void> contribute({
    required String ventureId,
    required String tenantId,
    required String contributorId,
    String? contributorName,
    required double amount,
    required bool isAnonymous,
    String? message,
    String? tenantName,
  }) async {
    final result = await _client.from('fundraising_contributions').insert({
      'venture_id': ventureId,
      'tenant_id': tenantId,
      'tenant_name': tenantName,
      'contributor_id': contributorId,
      'contributor_name': isAnonymous ? null : contributorName,
      'amount': amount,
      'is_anonymous': isAnonymous,
      'message': message,
    }).select('id').single();

    final insertedId = result['id'];

    // Notify venture creator
    try {
      final venture = await _client
          .from('fundraising_ventures')
          .select('created_by, title')
          .eq('id', ventureId)
          .maybeSingle();
      if (venture != null && venture['created_by'] != contributorId) {
        final contributorDisplay = isAnonymous ? 'Someone' : (contributorName ?? 'A member');
        await _client.functions.invoke('push-notifications', body: {
          'userId': venture['created_by'],
          'title': 'New Contribution',
          'body': '$contributorDisplay contributed K${amount.toStringAsFixed(0)} to ${venture['title']}',
          'data': {
            'type': 'fundraising',
            'reference_id': ventureId,
            'channel_id': 'coa_payments',
          },
        });
      }
    } catch (e) {
      debugPrint('[FundraisingService] Contribution notification failed: $e');
    }

    try {
      await _client.rpc('increment_fundraising_raised', params: {
        'venture_id': ventureId,
        'amount': amount,
      });
    } catch (e) {
      await _client.from('fundraising_contributions').delete().eq('id', insertedId);
      rethrow;
    }
  }

  Stream<List<FundraisingContribution>> getContributionsStream(String ventureId) {
    return _client
        .from('fundraising_contributions')
        .stream(primaryKey: ['id'])
        .eq('venture_id', ventureId)
        .order('created_at', ascending: false)
        .map((data) => (data as List).map((m) => FundraisingContribution.fromMap(m)).toList());
  }

  Future<void> inviteTenant(String ventureId, String fromTenantId, String toTenantId) async {
    await _client.from('fundraising_invites').insert({
      'venture_id': ventureId,
      'from_tenant_id': fromTenantId,
      'to_tenant_id': toTenantId,
    });
  }

  Stream<List<FundraisingVenture>> getInvitedVenturesStream(String tenantId) {
    return _client
        .from('fundraising_ventures')
        .stream(primaryKey: ['id'])
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .map((data) => (data as List)
            .map((m) => FundraisingVenture.fromMap(m))
            .where((v) => v.allowOtherTenants && v.allowedTenantIds.contains(tenantId))
            .toList());
  }

  Future<List<FundraisingContribution>> getTopContributors(String ventureId, {int limit = 10}) async {
    final data = await _client
        .from('fundraising_contributions')
        .select('id, venture_id, tenant_id, tenant_name, contributor_id, contributor_name, amount, is_anonymous, message, created_at')
        .eq('venture_id', ventureId)
        .order('amount', ascending: false)
        .limit(limit);
    return (data as List).map((m) => FundraisingContribution.fromMap(m)).toList();
  }

  Future<void> closeVenture(String ventureId) async {
    await _client
        .from('fundraising_ventures')
        .update({'status': 'completed'})
        .eq('id', ventureId);
  }

  Future<double> getTotalRaised(String tenantId) async {
    final data = await _client
        .from('fundraising_ventures')
        .select('raised_amount')
        .eq('tenant_id', tenantId);
    final ventures = data as List;
    return ventures.fold<double>(0, (sum, v) => sum + ((v['raised_amount'] as num?)?.toDouble() ?? 0));
  }
}
