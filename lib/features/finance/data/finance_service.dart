import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/config/fee_config.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/finance/data/offline_giving_queue.dart';

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

class RecentGiver {
  final String name;
  final double amount;
  final DateTime createdAt;

  const RecentGiver({
    required this.name,
    required this.amount,
    required this.createdAt,
  });
}

class ChurchGivingOverview {
  final double monthlyTotal;
  final List<RecentGiver> givers;

  const ChurchGivingOverview({
    required this.monthlyTotal,
    required this.givers,
  });
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
        .map((data) {
          final list = data.map((map) => Transaction.fromMap(map)).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Future<void> logTransaction(
    double amount,
    String category,
    String reference, {
    String? tenantId,
    String? recipientPhone,
    String? recipientName,
    String? paymentMethod,
    FeeConfig? feeConfig,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final fees = feeConfig ?? FeeConfig.defaults;
    final isCard = paymentMethod == 'card';
    final platformFee = fees.platformFee(amount, isCard: isCard);

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

    try {
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
        'payment_method': paymentMethod ?? 'momo',
      });
    } catch (e) {
      // OFFLINE GIVING QUEUE: when the network is down (payment already
      // confirmed via Lipila), persist the intent locally and replay it
      // idempotently via the server-side RPCs once connectivity returns.
      debugPrint('logTransaction insert failed — queueing offline giving: $e');
      await OfflineGivingQueue(Supabase.instance.client).enqueue(
        OfflineGivingIntent(
          paymentRef: reference,
          userId: user.id,
          tenantId: tenantId,
          amount: amount,
          category: category,
          paymentMethod: paymentMethod ?? 'momo',
          recipientPhone: finalPhone,
          recipientName: finalName,
        ),
      );
      return;
    }
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

    // AUTOMATIC SETTLEMENT ENGINE
    // Churches/sellers receive the FULL amount — fee was already collected from
    // the buyer on top. Enqueue a server-side payout task anchored to this
    // collection's reference; the settlement engine (webhook/cron) resolves the
    // church treasurer server-side and disburses after confirmation. The client
    // can no longer move money directly.
    try {
      await _client.rpc('enqueue_payout_task', params: {
        'p_source': 'giving',
        'p_source_ref': null,
        'p_payment_ref': reference,
        'p_recipient_user_id': null,
        'p_recipient_phone': recipientPhone ?? '',
        'p_gross_amount': amount,
      });
    } catch (e) {
      debugPrint("Automatic settlement enqueue failed: $e");
    }
  }
Future<ChurchGivingOverview> getChurchGivingOverview(String tenantId) async {
    final res = await _client.rpc('get_church_giving_overview', params: {
      'p_tenant_id': tenantId,
    }).timeout(const Duration(seconds: 15));
    final map = (res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{});
    final giversRaw = map['recent_givers'];
    final givers = <RecentGiver>[];
    if (giversRaw is List) {
      for (final g in giversRaw) {
        if (g is! Map) continue;
        final gm = Map<String, dynamic>.from(g);
        givers.add(RecentGiver(
          name: gm['name']?.toString() ?? 'Giver',
          amount: (gm['amount'] ?? 0).toDouble(),
          createdAt: DateTime.tryParse(gm['created_at']?.toString() ?? '') ??
              DateTime.now(),
        ));
      }
    }
    return ChurchGivingOverview(
      monthlyTotal: (map['monthly_total'] ?? 0).toDouble(),
      givers: givers,
    );
  }
}

final financeServiceProvider = Provider((ref) => FinanceService(Supabase.instance.client));

final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  return ref.watch(financeServiceProvider).getTransactionsStream();
});

final churchGivingOverviewProvider = FutureProvider<ChurchGivingOverview>((ref) {
  final tenant = ref.watch(currentTenantProvider);
  if (tenant == null) throw Exception('No church selected');
  return ref.watch(financeServiceProvider).getChurchGivingOverview(tenant.id);
});

