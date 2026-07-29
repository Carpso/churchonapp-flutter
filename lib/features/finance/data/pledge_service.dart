import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class Pledge {
  final String id;
  final String userId;
  final String? tenantId;
  final String category;
  final double totalAmount;
  final double amountPerCycle;
  final String frequency;
  final int installments;
  final double paidAmount;
  final DateTime startDate;
  final String status;

  Pledge({
    required this.id,
    required this.userId,
    this.tenantId,
    required this.category,
    required this.totalAmount,
    required this.amountPerCycle,
    required this.frequency,
    required this.installments,
    required this.paidAmount,
    required this.startDate,
    required this.status,
  });

  factory Pledge.fromMap(Map<String, dynamic> map) => Pledge(
        id: map['id']?.toString() ?? '',
        userId: map['user_id'] ?? '',
        tenantId: map['tenant_id'],
        category: map['category'] ?? 'general',
        totalAmount: (map['total_amount'] ?? 0).toDouble(),
        amountPerCycle: (map['amount_per_cycle'] ?? 0).toDouble(),
        frequency: map['frequency'] ?? 'monthly',
        installments: (map['installments'] ?? 1).toInt(),
        paidAmount: (map['paid_amount'] ?? 0).toDouble(),
        startDate: DateTime.parse(map['start_date'] ?? DateTime.now().toIso8601String()),
        status: map['status'] ?? 'active',
      );

  double get progress => totalAmount > 0 ? (paidAmount / totalAmount).clamp(0.0, 1.0) : 0.0;
  bool get isComplete => status == 'completed' || paidAmount >= totalAmount;
  int get cyclesPaid => amountPerCycle > 0 ? (paidAmount / amountPerCycle).floor() : 0;
}

class PledgeService {
  final SupabaseClient _client;
  PledgeService(this._client);

  Future<void> createPledge({
    required String tenantId,
    required String category,
    required double totalAmount,
    required double amountPerCycle,
    required String frequency,
    required int installments,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    await _client.from('pledges').insert({
      'user_id': user.id,
      'tenant_id': tenantId,
      'category': category,
      'total_amount': totalAmount,
      'amount_per_cycle': amountPerCycle,
      'frequency': frequency,
      'installments': installments,
    });
  }

  Future<List<Pledge>> getMyPledges() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final data = await _client
        .from('pledges')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return (data as List).map((m) => Pledge.fromMap(m)).toList();
  }

  Future<List<Pledge>> getTenantPledges(String tenantId) async {
    final data = await _client
        .from('pledges')
        .select()
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false);
    return (data as List).map((m) => Pledge.fromMap(m)).toList();
  }

  /// Attribute a completed installment payment to a pledge, marking it
  /// completed once the full commitment is fulfilled.
  Future<void> recordInstallmentPayment(String pledgeId, double amount) async {
    final cur = await _client
        .from('pledges')
        .select('paid_amount, total_amount')
        .eq('id', pledgeId)
        .maybeSingle();
    if (cur == null) return;
    final paid = (cur['paid_amount'] ?? 0).toDouble() + amount;
    final total = (cur['total_amount'] ?? 0).toDouble();
    final status = paid >= total ? 'completed' : 'active';
    await _client.from('pledges').update({
      'paid_amount': paid,
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', pledgeId);

    // Notify user when pledge is fully completed
    if (status == 'completed') {
      try {
        final pledge = await _client
            .from('pledges')
            .select('user_id, category')
            .eq('id', pledgeId)
            .maybeSingle();
        if (pledge != null) {
          await _client.functions.invoke('push-notifications', body: {
            'userId': pledge['user_id'],
            'title': 'Pledge Fulfilled!',
            'body': 'Your ${pledge['category']} pledge has been fully paid. God bless your faithfulness!',
            'data': {
              'type': 'pledge_completed',
              'reference_id': pledgeId,
              'channel_id': 'coa_payments',
            },
          });
        }
      } catch (e) {
        debugPrint('[PledgeService] Completion notification failed: $e');
      }
    }
  }
}

final pledgeServiceProvider = Provider((ref) {
  return PledgeService(ref.watch(supabaseServiceProvider).client);
});

final myPledgesProvider = FutureProvider<List<Pledge>>((ref) {
  return ref.watch(pledgeServiceProvider).getMyPledges();
});

final tenantPledgesProvider = FutureProvider.family<List<Pledge>, String>((ref, tenantId) {
  return ref.watch(pledgeServiceProvider).getTenantPledges(tenantId);
});
