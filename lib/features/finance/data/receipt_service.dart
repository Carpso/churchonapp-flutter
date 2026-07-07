import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaymentReceipt {
  final String id;
  final String transactionId;
  final double amount;
  final String category;
  final String status;
  final String reference;
  final DateTime createdAt;
  final String? recipientName;
  final String? recipientPhone;
  final String? tenantId;
  final String? tenantName;
  final String? userName;
  final double? platformFee;
  final double? netPayout;
  final String? provider;
  final String? disbursementStatus;

  PaymentReceipt({
    required this.id,
    required this.transactionId,
    required this.amount,
    required this.category,
    required this.status,
    required this.reference,
    required this.createdAt,
    this.recipientName,
    this.recipientPhone,
    this.tenantId,
    this.tenantName,
    this.userName,
    this.platformFee,
    this.netPayout,
    this.provider,
    this.disbursementStatus,
  });

  factory PaymentReceipt.fromMaps(Map<String, dynamic> txn, Map<String, dynamic>? log, Map<String, dynamic>? church) {
    final tenantId = txn['tenant_id']?.toString();
    return PaymentReceipt(
      id: log?['id']?.toString() ?? txn['id'].toString(),
      transactionId: txn['id'].toString(),
      amount: (txn['amount'] ?? 0).toDouble(),
      category: txn['category'] ?? 'offering',
      status: txn['status'] ?? 'pending',
      reference: txn['reference'] ?? '',
      createdAt: DateTime.parse(txn['created_at'] ?? DateTime.now().toIso8601String()),
      recipientName: txn['recipient_name'],
      recipientPhone: txn['recipient_phone'],
      tenantId: tenantId,
      tenantName: church?['name'],
      platformFee: (log?['platform_fee'] ?? 0).toDouble(),
      netPayout: (log?['net_payout'] ?? 0).toDouble(),
      provider: log?['provider'],
      disbursementStatus: log?['disbursement_status'],
    );
  }
}

class ReceiptService {
  final SupabaseClient _client;
  ReceiptService(this._client);

  Future<PaymentReceipt?> getReceipt(String reference) async {
    final txn = await _client
        .from('transactions')
        .select()
        .eq('reference', reference)
        .maybeSingle();
    if (txn == null) return null;

    final log = await _client
        .from('payment_logs')
        .select()
        .eq('tx_ref', reference)
        .maybeSingle();

    Map<String, dynamic>? church;
    final tenantId = txn['tenant_id'];
    if (tenantId != null) {
      church = await _client
          .from('churches')
          .select('name')
          .eq('id', tenantId)
          .maybeSingle();
    }

    return PaymentReceipt.fromMaps(txn, log, church);
  }

  Future<List<PaymentReceipt>> getReceiptsForUser(String userId) async {
    final txns = await _client
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);

    final references = txns.map((t) => t['reference'].toString()).toList();
    final logMap = <String, Map<String, dynamic>>{};
    for (final ref in references) {
      final log = await _client
          .from('payment_logs')
          .select()
          .eq('tx_ref', ref)
          .maybeSingle();
      if (log != null) logMap[ref] = log;
    }

    final tenantIds = txns
        .map((t) => t['tenant_id']?.toString())
        .where((id) => id != null)
        .cast<String>()
        .toSet()
        .toList();

    Map<String, Map<String, dynamic>> churchMap = {};
    for (final tid in tenantIds) {
      final church = await _client
          .from('churches')
          .select('id, name')
          .eq('id', tid)
          .maybeSingle();
      if (church != null) churchMap[tid] = church;
    }

    return txns.map((t) {
      final ref = t['reference'].toString();
      return PaymentReceipt.fromMaps(t, logMap[ref], churchMap[t['tenant_id']?.toString() ?? '']);
    }).toList();
  }
}

final receiptServiceProvider = Provider((ref) => ReceiptService(Supabase.instance.client));

final receiptProvider = FutureProvider.family<PaymentReceipt?, String>((ref, reference) {
  return ref.watch(receiptServiceProvider).getReceipt(reference);
});
