import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One church_withdrawals ledger row as returned by `get_my_church_earnings`.
class ChurchEarningPayout {
  const ChurchEarningPayout({
    required this.id,
    required this.grossAmount,
    this.netAmount,
    this.coaFee = 0,
    this.lipilaFee = 0,
    this.recipientPhone,
    this.lipilaReference,
    required this.status,
    this.createdAt,
    this.processedAt,
  });

  final String id;
  final double grossAmount;
  final double? netAmount;
  final double coaFee;
  final double lipilaFee;
  final String? recipientPhone;
  final String? lipilaReference;
  final String status;
  final DateTime? createdAt;
  final DateTime? processedAt;

  factory ChurchEarningPayout.fromMap(Map<String, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    DateTime? dt(String k) {
      final v = m[k];
      return v == null ? null : DateTime.tryParse(v.toString());
    }

    return ChurchEarningPayout(
      id: m['id']?.toString() ?? '',
      grossAmount: d('gross_amount'),
      netAmount: (m['net_amount'] as num?)?.toDouble(),
      coaFee: d('coa_fee'),
      lipilaFee: d('lipila_fee'),
      recipientPhone: m['recipient_phone']?.toString(),
      lipilaReference: m['lipila_reference']?.toString(),
      status: m['status']?.toString() ?? 'pending',
      createdAt: dt('created_at'),
      processedAt: dt('processed_at'),
    );
  }
}

/// A leader's own church earnings â€” server-derived, read-only. Mirrors the
/// chisomo host dashboard: withdrawable balance, what has been paid out, and the
/// payout ledger. Amounts are computed by `get_my_church_earnings` (SECURITY
/// DEFINER, tenant-scoped) and can never be set from the client.
class ChurchEarnings {
  const ChurchEarnings({
    required this.withdrawable,
    required this.grossCollected,
    required this.committedGiving,
    required this.inFlightWithdrawals,
    this.recipientPhone,
    required this.payouts,
  });

  final double withdrawable;
  final double grossCollected;
  final double committedGiving;
  final double inFlightWithdrawals;
  final String? recipientPhone;
  final List<ChurchEarningPayout> payouts;

  double get paidOut => payouts
      .where((p) => p.status == 'paid')
      .fold<double>(0, (s, p) => s + (p.netAmount ?? 0));

  factory ChurchEarnings.fromMap(Map<String, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    final rows = (m['withdrawals'] as List?) ?? const [];
    return ChurchEarnings(
      withdrawable: d('withdrawable'),
      grossCollected: d('gross_collected'),
      committedGiving: d('committed_giving'),
      inFlightWithdrawals: d('in_flight_withdrawals'),
      recipientPhone: m['recipient_phone']?.toString(),
      payouts: rows
          .map((e) => ChurchEarningPayout.fromMap((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  static const empty = ChurchEarnings(
    withdrawable: 0,
    grossCollected: 0,
    committedGiving: 0,
    inFlightWithdrawals: 0,
    payouts: [],
  );
}

class ChurchEarningsService {
  ChurchEarningsService(this._client);

  final SupabaseClient _client;

  Future<ChurchEarnings> fetch() async {
    try {
      final res = await _client.rpc('get_my_church_earnings');
      if (res is Map) {
        return ChurchEarnings.fromMap(res.cast<String, dynamic>());
      }
      return ChurchEarnings.empty;
    } catch (e) {
      debugPrint('Error fetching church earnings: $e');
      return ChurchEarnings.empty;
    }
  }
}

final churchEarningsServiceProvider = Provider(
  (ref) => ChurchEarningsService(Supabase.instance.client),
);

final churchEarningsProvider = FutureProvider<ChurchEarnings>((ref) {
  return ref.watch(churchEarningsServiceProvider).fetch();
});
