import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Transaction {
  final String id;
  final String userId;
  final double amount;
  final String category;
  final String status;
  final String reference;
  final String? tenantId;
  final DateTime createdAt;

  Transaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.category,
    required this.status,
    required this.reference,
    this.tenantId,
    required this.createdAt,
  });

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id']?.toString() ?? '',
      userId: map['user_id'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      category: map['category'] ?? 'offering',
      status: map['status'] ?? 'pending',
      reference: map['reference'] ?? '',
      tenantId: map['tenant_id'],
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class FinanceService {
  final SupabaseClient _client;
  FinanceService(this._client);

  Stream<List<Transaction>> getTransactionsStream() {
    final user = _client.auth.currentUser;
    if (user == null) return Stream.value([]);

    return _client
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => Transaction.fromMap(map)).toList());
  }

  Stream<List<Transaction>> getTenantLedgerStream(String tenantId) {
    return _client
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => Transaction.fromMap(map)).toList());
  }

  Future<void> logTransaction(double amount, String category, String reference, {String? tenantId}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('transactions').insert({
      'user_id': user.id,
      'amount': amount,
      'category': category,
      'reference': reference,
      'status': 'completed',
      'tenant_id': tenantId,
    });
    
    // Also update profile coins (stewardship points)
    final profile = await _client.from('profiles').select('coins').eq('id', user.id).single();
    final currentCoins = profile['coins'] ?? 0;
    await _client.from('profiles').update({'coins': currentCoins + amount.toInt()}).eq('id', user.id);
  }
}

final financeServiceProvider = Provider((ref) => FinanceService(Supabase.instance.client));

final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  return ref.watch(financeServiceProvider).getTransactionsStream();
});
