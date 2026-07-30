import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class Transaction {
  final String id;
  final String userId;
  final double amount;
  final String category;
  final String status;
  final String reference;
  final String? tenantId;
  final DateTime createdAt;
  final String? recipientName;
  final String? recipientPhone;

  Transaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.category,
    required this.status,
    required this.reference,
    this.tenantId,
    required this.createdAt,
    this.recipientName,
    this.recipientPhone,
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
      recipientName: map['recipient_name'],
      recipientPhone: map['recipient_phone'],
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

  Future<void> logTransaction(
    double amount,
    String category,
    String reference, {
    String? tenantId,
    String? recipientPhone,
    String? recipientName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    const cutPercent = 0.01;
    final platformFee = amount * cutPercent > 3.0 ? amount * cutPercent : 3.0;

    // Dynamic fallback for Church Giving/Offerings if recipientPhone is null
    String? finalPhone = recipientPhone;
    String? finalName = recipientName;
    if (finalPhone == null && tenantId != null) {
      try {
        final church = await _client.from('churches').select('treasurer_phone, name').eq('id', tenantId).maybeSingle();
        if (church != null) {
          finalPhone = church['treasurer_phone'];
          finalName = church['name'];
        }
      } catch (e) {
        debugPrint('Failed to look up church treasurer: $e');
      }
    }

    await _client.from('transactions').insert({
      'user_id': user.id,
      'amount': amount,
      'category': category,
      'reference': reference,
      'status': 'completed',
      'tenant_id': tenantId,
      'platform_fee': platformFee,
      'recipient_name': finalName,
      'recipient_phone': finalPhone,
    });
    
    // Also update profile coins (stewardship points)
    final profile = await _client.from('profiles').select('coins').eq('id', user.id).single();
    final currentCoins = profile['coins'] ?? 0;
    await _client.from('profiles').update({'coins': currentCoins + amount.toInt()}).eq('id', user.id);

    // Update Central Treasury coins
    try {
      final treasury = await _client.from('profiles').select('coins').eq('id', '00000000-0000-0000-0000-000000000000').maybeSingle();
      if (treasury != null) {
        final treasuryCoins = treasury['coins'] ?? 0;
        await _client.from('profiles').update({'coins': treasuryCoins + platformFee.toInt()}).eq('id', '00000000-0000-0000-0000-000000000000');
      }
    } catch (e) {
      debugPrint('Error updating treasury coins: $e');
    }

    // Set variable scope for subsequent payout call
    recipientPhone = finalPhone;
    recipientName = finalName;

    // AUTOMATIC SPLIT SETTLEMENT ENGINE
    // Automatically trigger MoMo payout via server-side edge function.
    if (recipientPhone != null && recipientPhone.trim().isNotEmpty) {
      try {
        final double payoutAmount = amount - platformFee;
        String targetPhone = recipientPhone.replaceAll(RegExp(r'\D'), '');
        if (targetPhone.startsWith('0')) targetPhone = '260${targetPhone.substring(1)}';
        if (targetPhone.startsWith('9')) targetPhone = '260$targetPhone';
        if (targetPhone.length == 9) targetPhone = '260$targetPhone';

        final payoutRef = const Uuid().v4();

        await _client.functions.invoke(
          'lipila-payout',
          method: HttpMethod.post,
          body: {
            'accountNumber': targetPhone,
            'amount': payoutAmount,
            'narration': 'COA Settlement split: $reference',
            'referenceId': payoutRef,
          },
        );
      } catch (e) {
        debugPrint("Automatic Payout split settlement failed for $recipientPhone: $e");
      }
    }
  }
}

final financeServiceProvider = Provider((ref) => FinanceService(Supabase.instance.client));

final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  return ref.watch(financeServiceProvider).getTransactionsStream();
});

