import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-side platform-fee summary (chisomo fee ledger parity). Values come
/// from `get_platform_fee_summary` — never computed on the client.
class PlatformFeeSummary {
  const PlatformFeeSummary({
    required this.payoutFeesEarned,
    required this.payoutFeesSettled,
    required this.payoutFeesPending,
    required this.totalCollected,
    required this.totalPaidOut,
  });

  final double payoutFeesEarned;
  final double payoutFeesSettled;
  final double payoutFeesPending;
  final double totalCollected;
  final double totalPaidOut;

  factory PlatformFeeSummary.fromMap(Map<String, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    return PlatformFeeSummary(
      payoutFeesEarned: d('payout_fees_earned'),
      payoutFeesSettled: d('payout_fees_settled'),
      payoutFeesPending: d('payout_fees_pending'),
      totalCollected: d('total_collected'),
      totalPaidOut: d('total_paid_out'),
    );
  }

  static const empty = PlatformFeeSummary(
    payoutFeesEarned: 0,
    payoutFeesSettled: 0,
    payoutFeesPending: 0,
    totalCollected: 0,
    totalPaidOut: 0,
  );
}

/// One platform-fee sweep to the COA settlement number.
class FeeSweepRecord {
  const FeeSweepRecord({
    required this.id,
    required this.kind,
    required this.amount,
    this.lipilaReference,
    required this.status,
    this.lastError,
    this.createdAt,
  });

  final String id;
  final String kind;
  final double amount;
  final String? lipilaReference;
  final String status;
  final String? lastError;
  final DateTime? createdAt;

  factory FeeSweepRecord.fromMap(Map<String, dynamic> m) {
    return FeeSweepRecord(
      id: m['id']?.toString() ?? '',
      kind: m['kind']?.toString() ?? 'payout_fee',
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      lipilaReference: m['lipila_reference']?.toString(),
      status: m['status']?.toString() ?? 'pending',
      lastError: m['last_error']?.toString(),
      createdAt: m['created_at'] == null ? null : DateTime.tryParse(m['created_at'].toString()),
    );
  }
}

class PlatformFeeService {
  PlatformFeeService(this._client);

  final SupabaseClient _client;

  Future<PlatformFeeSummary> fetchSummary() async {
    try {
      final res = await _client.rpc('get_platform_fee_summary');
      if (res is Map) {
        return PlatformFeeSummary.fromMap(res.cast<String, dynamic>());
      }
      return PlatformFeeSummary.empty;
    } catch (e) {
      debugPrint('Error fetching platform fee summary: $e');
      return PlatformFeeSummary.empty;
    }
  }

  Future<List<FeeSweepRecord>> fetchSweeps({int limit = 200}) async {
    try {
      final rows = await _client
          .from('fee_sweeps')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) => FeeSweepRecord.fromMap((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('Error fetching fee sweeps: $e');
      return [];
    }
  }
}

final platformFeeServiceProvider = Provider(
  (ref) => PlatformFeeService(Supabase.instance.client),
);
