import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-side withdrawable balance for one church (from
/// `get_church_withdrawable_balances` RPC). Amounts are derived from confirmed
/// collections minus committed payouts — never trusted from the client.
class ChurchWithdrawable {
  const ChurchWithdrawable({
    required this.churchId,
    required this.churchName,
    this.treasurerPhone,
    required this.grossCollected,
    required this.committedGiving,
    required this.inFlightWithdrawals,
    required this.withdrawable,
  });

  final String churchId;
  final String churchName;
  final String? treasurerPhone;
  final double grossCollected;
  final double committedGiving;
  final double inFlightWithdrawals;
  final double withdrawable;

  factory ChurchWithdrawable.fromMap(Map<String, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    return ChurchWithdrawable(
      churchId: m['church_id']?.toString() ?? '',
      churchName: m['church_name']?.toString() ?? 'Unknown Church',
      treasurerPhone: m['treasurer_phone']?.toString(),
      grossCollected: d('gross_collected'),
      committedGiving: d('committed_giving'),
      inFlightWithdrawals: d('in_flight_withdrawals'),
      withdrawable: d('withdrawable'),
    );
  }
}

/// One row of the church_withdrawals ledger (from `get_church_withdrawals`).
class ChurchWithdrawalRecord {
  const ChurchWithdrawalRecord({
    required this.id,
    required this.churchId,
    this.churchName,
    required this.grossAmount,
    required this.lipilaFee,
    required this.coaFee,
    this.netAmount,
    required this.recipientPhone,
    this.lipilaReference,
    required this.status,
    this.lastError,
    required this.createdAt,
    this.processedAt,
  });

  final String id;
  final String churchId;
  final String? churchName;
  final double grossAmount;
  final double lipilaFee;
  final double coaFee;
  final double? netAmount;
  final String recipientPhone;
  final String? lipilaReference;
  final String status;
  final String? lastError;
  final DateTime createdAt;
  final DateTime? processedAt;

  bool get isInFlight => status == 'pending' || status == 'processing';

  factory ChurchWithdrawalRecord.fromMap(Map<String, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    DateTime? dt(String k) {
      final v = m[k];
      return v == null ? null : DateTime.tryParse(v.toString());
    }

    return ChurchWithdrawalRecord(
      id: m['id']?.toString() ?? '',
      churchId: m['church_id']?.toString() ?? '',
      churchName: m['church_name']?.toString(),
      grossAmount: d('gross_amount'),
      lipilaFee: d('lipila_fee'),
      coaFee: d('coa_fee'),
      netAmount: (m['net_amount'] as num?)?.toDouble(),
      recipientPhone: m['recipient_phone']?.toString() ?? '',
      lipilaReference: m['lipila_reference']?.toString(),
      status: m['status']?.toString() ?? 'pending',
      lastError: m['last_error']?.toString(),
      createdAt: dt('created_at') ?? DateTime.now(),
      processedAt: dt('processed_at'),
    );
  }
}

class ChurchPayoutService {
  ChurchPayoutService(this._client);

  final SupabaseClient _client;

  /// All churches with a server-side withdrawable giving balance (admin RPC).
  Future<List<ChurchWithdrawable>> fetchWithdrawableBalances() async {
    try {
      final res = await _client.rpc('get_church_withdrawable_balances');
      return (res as List)
          .map((e) => ChurchWithdrawable.fromMap((e as Map).cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => b.withdrawable.compareTo(a.withdrawable));
    } catch (e) {
      debugPrint('Error fetching withdrawable balances: $e');
      return [];
    }
  }

  /// Recent church_withdrawals ledger rows (admin RPC).
  Future<List<ChurchWithdrawalRecord>> fetchWithdrawals({int limit = 200}) async {
    try {
      final res = await _client.rpc('get_church_withdrawals', params: {'p_limit': limit});
      return (res as List)
          .map((e) => ChurchWithdrawalRecord.fromMap((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('Error fetching church withdrawals: $e');
      return [];
    }
  }

  /// Trigger the settlement engine now (runs enqueue + payout processing).
  /// `lipila-settle` verifies the caller is a superadmin / coa_employee.
  Future<Map<String, dynamic>> runSettlementNow() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final res = await _client.functions.invoke('lipila-settle', body: const {});
    return (res.data as Map?)?.cast<String, dynamic>() ?? const {};
  }
}

final churchPayoutServiceProvider = Provider(
  (ref) => ChurchPayoutService(Supabase.instance.client),
);
