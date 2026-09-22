import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/utils/money.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/admin/data/meeting_admin_service.dart';

/// COA revenue + admin console for Pro Meeting subscriptions.
///
/// Superadmin hub → Platform Tools. Staff-only (the RPC enforces it too).
/// Lists every subscription with tenant / plan / amount / status / dates /
/// payment ref and shows real revenue totals (MRR, active, refunds, COA cut)
/// over a selectable window, with cancel / refund / force-expire actions and
/// CSV export.
class MeetingRevenueScreen extends ConsumerStatefulWidget {
  const MeetingRevenueScreen({super.key});

  @override
  ConsumerState<MeetingRevenueScreen> createState() =>
      _MeetingRevenueScreenState();
}

class _MeetingRevenueScreenState extends ConsumerState<MeetingRevenueScreen> {
  int _days = 30;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) PremiumToast.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refresh() => ref.invalidate(meetingAdminReportProvider(_days));

  Future<void> _cancel(MeetingSubscriptionRow row) async {
    await _run(() async {
      final ok = await ref.read(meetingAdminServiceProvider).cancel(row.id);
      if (!mounted) return;
      ok
          ? PremiumToast.showSuccess(context, 'Subscription cancelled.')
          : PremiumToast.showError(context, 'Could not cancel.');
      _refresh();
    });
  }

  Future<void> _forceExpire(MeetingSubscriptionRow row) async {
    await _run(() async {
      final ok =
          await ref.read(meetingAdminServiceProvider).forceExpire(row.id);
      if (!mounted) return;
      ok
          ? PremiumToast.showSuccess(context, 'Subscription expired.')
          : PremiumToast.showError(context, 'Could not expire.');
      _refresh();
    });
  }

  Future<void> _refund(MeetingSubscriptionRow row) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Refund subscription',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Reason (recorded on the refund)',
            labelStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, ctrl.text.trim().isEmpty ? 'staff_refund' : ctrl.text.trim()),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || !mounted) return;
    await _run(() async {
      final ok =
          await ref.read(meetingAdminServiceProvider).refund(row.id, reason);
      if (!mounted) return;
      ok
          ? PremiumToast.showSuccess(context, 'Refund recorded.')
          : PremiumToast.showError(context, 'Could not refund.');
      _refresh();
    });
  }

  Future<void> _export(MeetingAdminReport report) async {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final buffer = StringBuffer(
        'subscription_id,tenant,plan,status,amount_kwacha,coa_cut_kwacha,'
        'started_at,expires_at,payment_ref,auto_renew,refunded_at,refund_ref\n');
    for (final r in report.subscriptions) {
      buffer.writeln([
        r.id,
        '"${r.tenantName.replaceAll('"', "'")}"',
        r.plan,
        r.status,
        r.amountKwacha.toStringAsFixed(2),
        r.coaCutKwacha.toStringAsFixed(2),
        r.startedAt != null ? df.format(r.startedAt!) : '',
        r.expiresAt != null ? df.format(r.expiresAt!) : '',
        r.paymentRef ?? '',
        r.autoRenew,
        r.refundedAt != null ? df.format(r.refundedAt!) : '',
        r.refundRef ?? '',
      ].join(','));
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) PremiumToast.showSuccess(context, 'CSV copied to clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(meetingAdminReportProvider(_days));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        title: const Text('Meeting Revenue',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(LucideIcons.download, color: Colors.white, size: 18),
            onPressed: () {
              final report = async.value;
              if (report != null) _export(report);
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, color: Colors.white, size: 18),
            onPressed: _refresh,
          ),
        ],
      ),
      body: async.when(
        data: (report) => RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              _windowChips(theme),
              const SizedBox(height: 12),
              _summaryGrid(theme, report.summary),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('SUBSCRIPTIONS',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const Spacer(),
                  Text('${report.subscriptions.length}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              if (report.subscriptions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('No meeting subscriptions yet.',
                        style: TextStyle(color: Colors.white54)),
                  ),
                ),
              ...report.subscriptions.map((r) => _rowCard(theme, r)),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('$e', style: const TextStyle(color: Colors.white54)),
        ),
      ),
    );
  }

  Widget _windowChips(ThemeData theme) {
    return Row(
      children: [7, 30, 90].map((d) {
        final selected = _days == d;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text('${d}d'),
            selected: selected,
            onSelected: (_) => setState(() => _days = d),
            labelStyle: TextStyle(
                color: selected ? Colors.black : Colors.white70, fontSize: 12),
            selectedColor: theme.primaryColor,
            backgroundColor: const Color(0xFF151A2E),
          ),
        );
      }).toList(),
    );
  }

  Widget _summaryGrid(ThemeData theme, MeetingRevenueSummary s) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _kpi(theme, 'MRR', formatKwacha(s.mrr), LucideIcons.trendingUp, theme.primaryColor),
        _kpi(theme, 'Active', '${s.activeCount}', LucideIcons.users, Colors.greenAccent),
        _kpi(theme, 'Collected', formatKwacha(s.collected), LucideIcons.banknote, Colors.lightBlueAccent),
        _kpi(theme, 'COA cut', formatKwacha(s.coaCut), LucideIcons.pieChart, Colors.amber),
        _kpi(theme, 'Refunds', formatKwacha(s.refunds), LucideIcons.rotateCcw, Colors.redAccent),
        _kpi(theme, 'New', '${s.newCount}', LucideIcons.plusCircle, Colors.purpleAccent),
      ],
    );
  }

  Widget _kpi(ThemeData theme, String label, String value, IconData icon, Color color) {
    final width = (MediaQuery.of(context).size.width - 42) / 2;
    return Container(
      width: width.clamp(140.0, 320.0).toDouble(),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _rowCard(ThemeData theme, MeetingSubscriptionRow r) {
    final df = DateFormat('d MMM y');
    final color = switch (r.status) {
      'active' => Colors.greenAccent,
      'pending' => Colors.orangeAccent,
      'refunded' => Colors.redAccent,
      'cancelled' => Colors.grey,
      'expired' => Colors.white54,
      _ => Colors.white54,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.tenantName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
              ),
              _chip(r.status.toUpperCase(), color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${r.plan.toUpperCase()} · ${formatKwacha(r.amountKwacha)}'
            ' · COA cut ${formatKwacha(r.coaCutKwacha)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '${r.startedAt != null ? 'Start ${df.format(r.startedAt!)}' : 'Not started'}'
            '${r.expiresAt != null ? ' · Expires ${df.format(r.expiresAt!)}' : ''}'
            '${r.autoRenew ? ' · AUTO-RENEW' : ''}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if ((r.paymentRef ?? '').isNotEmpty)
            Text('Ref: ${r.paymentRef}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          if (r.refundedAt != null)
            Text('Refunded ${df.format(r.refundedAt!)} · ${r.refundRef ?? ''}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: _busy ? null : () => _cancel(r),
                icon: const Icon(LucideIcons.xCircle, size: 15),
                label: const Text('Cancel'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _forceExpire(r),
                icon: const Icon(LucideIcons.clock, size: 15),
                label: const Text('Expire'),
              ),
              TextButton.icon(
                onPressed: (_busy || r.status == 'refunded')
                    ? null
                    : () => _refund(r),
                icon: const Icon(LucideIcons.rotateCcw, size: 15),
                label: const Text('Refund'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w900)),
      );
}
