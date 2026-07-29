import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fundraising_models.dart';

class GroupContributionService {
  final SupabaseClient _client;
  GroupContributionService(this._client);

  Future<GroupContribution?> getGroup(String groupId) async {
    final data = await _client
        .from('group_contributions')
        .select('*, group_contribution_members!inner(count)')
        .eq('id', groupId)
        .maybeSingle();
    if (data == null) return null;
    final memberCount = (data['group_contribution_members'] as List?)?.length ?? 0;
    return GroupContribution.fromMap({...data, 'member_count': memberCount});
  }

  Future<List<GroupContribution>> getGroups(String tenantId) async {
    final data = await _client
        .from('group_contributions')
        .select('*, group_contribution_members!inner(count)')
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false);

    return data.map((map) {
      final memberCount = (map['group_contribution_members'] as List?)?.length ?? 0;
      return GroupContribution.fromMap({...map, 'member_count': memberCount});
    }).toList();
  }

  Stream<List<GroupContribution>> getGroupsStream(String tenantId) {
    return _client
        .from('group_contributions')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => GroupContribution.fromMap(map)).toList());
  }

  Future<GroupContribution> createGroup({
    required String tenantId,
    required String title,
    String description = '',
    required double targetAmount,
    String currency = 'ZMW',
    String frequency = 'one_time',
    double minAmount = 1,
    double? maxAmount,
    DateTime? endDate,
    required String createdBy,
  }) async {
    final data = await _client.from('group_contributions').insert({
      'tenant_id': tenantId,
      'title': title,
      'description': description,
      'target_amount': targetAmount,
      'currency': currency,
      'frequency': frequency,
      'min_amount': minAmount,
      'max_amount': maxAmount,
      'end_date': endDate?.toIso8601String(),
      'created_by': createdBy,
    }).select().single();

    return GroupContribution.fromMap(data);
  }

  Future<void> closeGroup(String groupId) async {
    await _client
        .from('group_contributions')
        .update({'status': 'cancelled'})
        .eq('id', groupId);
  }

  Future<List<GroupContributionMember>> getMembers(String groupId) async {
    final data = await _client
        .from('group_contribution_members')
        .select()
        .eq('group_id', groupId)
        .order('joined_at', ascending: true);

    return data.map((map) => GroupContributionMember.fromMap(map)).toList();
  }

  Stream<List<GroupContributionMember>> getMembersStream(String groupId) {
    return _client
        .from('group_contribution_members')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .order('joined_at', ascending: true)
        .map((data) => data.map((map) => GroupContributionMember.fromMap(map)).toList());
  }

  Future<void> joinGroup({
    required String groupId,
    required String userId,
    required String userName,
    required double pledgedAmount,
  }) async {
    await _client.from('group_contribution_members').insert({
      'group_id': groupId,
      'user_id': userId,
      'user_name': userName,
      'pledged_amount': pledgedAmount,
    });
  }

  Future<void> contribute({
    required String groupId,
    required String memberId,
    required String userName,
    required double amount,
    bool isAnonymous = false,
    String? message,
  }) async {
    // RPC first (atomic increment) — before any notifications
    try {
      await _client.rpc('increment_group_collected', params: {
        'group_id': groupId,
        'amount': amount,
      });

      await _client.rpc('increment_member_paid', params: {
        'member_id': memberId,
        'amount': amount,
      });
    } catch (e) {
      rethrow;
    }

    // Insert payment record after RPC succeeds
    final result = await _client.from('group_contribution_payments').insert({
      'group_id': groupId,
      'member_id': memberId,
      'user_name': userName,
      'amount': amount,
      'is_anonymous': isAnonymous,
      'message': message,
    }).select('id').single();

    final _ = result['id'];

    // Notify other group members only after DB is consistent
    try {
      final group = await _client
          .from('group_contributions')
          .select('title')
          .eq('id', groupId)
          .maybeSingle();
      final members = await _client
          .from('group_contribution_members')
          .select('user_id')
          .eq('group_id', groupId);
      final memberIds = members
          .where((m) => m['user_id'] != memberId)
          .map((m) => m['user_id'] as String)
          .toList();
      if (memberIds.isNotEmpty) {
        final payerDisplay = isAnonymous ? 'Someone' : userName;
        await _client.functions.invoke('push-notifications', body: {
          'userIds': memberIds,
          'title': 'Group Contribution',
          'body': '$payerDisplay contributed K${amount.toStringAsFixed(0)} to ${group?['title'] ?? 'the group'}',
          'data': {
            'type': 'group_contribution',
            'reference_id': groupId,
            'channel_id': 'coa_payments',
          },
        });
      }
    } catch (e) {
      debugPrint('[GroupContribution] Payment notification failed: $e');
    }
  }

  Future<List<GroupContributionPayment>> getPayments(String groupId) async {
    final data = await _client
        .from('group_contribution_payments')
        .select()
        .eq('group_id', groupId)
        .order('created_at', ascending: false);

    return data.map((map) => GroupContributionPayment.fromMap(map)).toList();
  }

  Stream<List<GroupContributionPayment>> getPaymentsStream(String groupId) {
    return _client
        .from('group_contribution_payments')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => GroupContributionPayment.fromMap(map)).toList());
  }

  Future<GroupContributionMember?> getMyMembership(String groupId, String userId) async {
    final data = await _client
        .from('group_contribution_members')
        .select()
        .eq('group_id', groupId)
        .eq('user_id', userId)
        .maybeSingle();

    if (data == null) return null;
    return GroupContributionMember.fromMap(data);
  }
}
