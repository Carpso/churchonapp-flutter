import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/supabase_service.dart';

/// COA (superadmin / coa_employee) view of Pro Meeting subscriptions.
///
/// Real data only — the server RPC re-derives every total from
/// `meeting_subscriptions` + `coa_payments`. The client never computes money.
class MeetingRevenueSummary {
  final int activeCount;
  final int newCount;
  final double mrr;
  final double collected;
  final double refunds;
  final double coaCut;

  const MeetingRevenueSummary({
    required this.activeCount,
    required this.newCount,
    required this.mrr,
    required this.collected,
    required this.refunds,
    required this.coaCut,
  });

  static const empty = MeetingRevenueSummary(
    activeCount: 0,
    newCount: 0,
    mrr: 0,
    collected: 0,
    refunds: 0,
    coaCut: 0,
  );

  factory MeetingRevenueSummary.fromJson(Map<String, dynamic> map) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return MeetingRevenueSummary(
      activeCount: (map['active_count'] as num?)?.toInt() ?? 0,
      newCount: (map['new_count'] as num?)?.toInt() ?? 0,
      mrr: d(map['mrr']),
      collected: d(map['collected']),
      refunds: d(map['refunds']),
      coaCut: d(map['coa_cut']),
    );
  }
}

class MeetingSubscriptionRow {
  final String id;
  final String? tenantId;
  final String tenantName;
  final String plan;
  final String status;
  final double amountKwacha;
  final double coaCutKwacha;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final String? paymentRef;
  final String? coaPaymentId;
  final bool autoRenew;
  final DateTime? cancelledAt;
  final DateTime? refundedAt;
  final String? refundRef;
  final DateTime? createdAt;

  const MeetingSubscriptionRow({
    required this.id,
    required this.tenantId,
    required this.tenantName,
    required this.plan,
    required this.status,
    required this.amountKwacha,
    required this.coaCutKwacha,
    required this.startedAt,
    required this.expiresAt,
    required this.paymentRef,
    required this.coaPaymentId,
    required this.autoRenew,
    required this.cancelledAt,
    required this.refundedAt,
    required this.refundRef,
    required this.createdAt,
  });

  bool get isActive => status == 'active';

  factory MeetingSubscriptionRow.fromMap(Map<String, dynamic> map) {
    DateTime? dt(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return MeetingSubscriptionRow(
      id: map['id'].toString(),
      tenantId: map['tenant_id']?.toString(),
      tenantName: (map['tenant_name'] ?? 'Unknown church').toString(),
      plan: (map['plan'] ?? 'monthly').toString(),
      status: (map['status'] ?? 'pending').toString(),
      amountKwacha: (map['amount_kwacha'] as num?)?.toDouble() ?? 0,
      coaCutKwacha: (map['coa_cut_kwacha'] as num?)?.toDouble() ?? 0,
      startedAt: dt(map['started_at']),
      expiresAt: dt(map['expires_at']),
      paymentRef: map['payment_ref']?.toString(),
      coaPaymentId: map['coa_payment_id']?.toString(),
      autoRenew: map['auto_renew'] == true,
      cancelledAt: dt(map['cancelled_at']),
      refundedAt: dt(map['refunded_at']),
      refundRef: map['refund_ref']?.toString(),
      createdAt: dt(map['created_at']),
    );
  }
}

class MeetingAdminReport {
  final MeetingRevenueSummary summary;
  final List<MeetingSubscriptionRow> subscriptions;
  final int windowDays;

  const MeetingAdminReport({
    required this.summary,
    required this.subscriptions,
    required this.windowDays,
  });

  static const empty = MeetingAdminReport(
    summary: MeetingRevenueSummary.empty,
    subscriptions: [],
    windowDays: 30,
  );

  factory MeetingAdminReport.fromJson(Map<String, dynamic> map) {
    final summary = map['summary'] is Map
        ? MeetingRevenueSummary.fromJson(
            Map<String, dynamic>.from(map['summary'] as Map))
        : MeetingRevenueSummary.empty;
    final rows = map['subscriptions'] is List
        ? (map['subscriptions'] as List)
            .whereType<Map>()
            .map((e) => MeetingSubscriptionRow.fromMap(
                Map<String, dynamic>.from(e)))
            .toList()
        : <MeetingSubscriptionRow>[];
    return MeetingAdminReport(
      summary: summary,
      subscriptions: rows,
      windowDays: (map['window_days'] as num?)?.toInt() ?? 30,
    );
  }
}

class MeetingAdminService {
  final SupabaseClient _client;
  MeetingAdminService(this._client);

  Future<MeetingAdminReport> getReport(int days) async {
    try {
      final res = await _client.rpc(
        'get_meeting_admin_report',
        params: {'p_days': days},
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      return MeetingAdminReport.fromJson(map);
    } catch (e) {
      debugPrint('get_meeting_admin_report error: $e');
      return MeetingAdminReport.empty;
    }
  }

  Future<bool> cancel(String subscriptionId) =>
      _action('cancel_meeting_subscription', {
        'p_subscription_id': subscriptionId,
      });

  Future<bool> refund(String subscriptionId, String reason) =>
      _action('refund_meeting_subscription', {
        'p_subscription_id': subscriptionId,
        'p_reason': reason,
      });

  Future<bool> forceExpire(String subscriptionId) =>
      _action('force_expire_meeting_subscription', {
        'p_subscription_id': subscriptionId,
      });

  Future<bool> _action(String fn, Map<String, dynamic> params) async {
    final res = await _client.rpc(fn, params: params);
    final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    return map['success'] == true;
  }
}

final meetingAdminServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return MeetingAdminService(client);
});

/// Revenue report keyed by window (7 / 30 / 90 days). `int` has value equality.
final meetingAdminReportProvider =
    FutureProvider.family<MeetingAdminReport, int>((ref, days) {
  return ref.watch(meetingAdminServiceProvider).getReport(days);
});
