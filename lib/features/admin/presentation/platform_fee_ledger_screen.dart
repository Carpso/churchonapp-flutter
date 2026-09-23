import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/admin/data/church_payout_service.dart';
import 'package:church_on_app/features/admin/data/platform_fee_service.dart';

/// Admin platform-fee ledger + reconciliation view (chisomo `fee_sweeps` /
/// Lipila-logs parity). Read-only oversight of the COA payout cut earned on
/// church withdrawals and the sweeps that settle it to the platform number.
class PlatformFeeLedgerScreen extends ConsumerStatefulWidget {
  const PlatformFeeLedgerScreen({super.key});

  @override
  ConsumerState<PlatformFeeLedgerScreen> createState() => _PlatformFeeLedgerScreenState();
}

class _PlatformFeeLedgerScreenState extends ConsumerState<PlatformFeeLedgerScreen> {
  PlatformFeeSummary _summary = PlatformFeeSummary.empty;
  List<FeeSweepRecord> _sweeps = [];
  bool _loading = true;
  bool _running = false;

  PlatformFeeService get _service => ref.read(platformFeeServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.fetchSummary(),
      _service.fetchSweeps(),
    ]);
    if (!mounted) return;
    setState(() {
      _summary = results[0] as PlatformFeeSummary;
      _sweeps = results[1] as List<FeeSweepRecord>;
      _loading = false;
    });
  }

  Future<void> _runSettlement() async {
    setState(() => _running = true);
    try {
      final res = await ref.read(churchPayoutServiceProvider).runSettlementNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Settlement run: ${res['payoutPaid'] ?? 0} paid · '
            '${res['reconciled'] ?? 0} reconciled · '
            'sweep K${res['feeSweepAmount'] ?? 0}',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Settlement error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).value;
    final role = profile?.role ?? '';
    final allowed = ['superadmin', 'coa_employee', 'employee', 'treasurer', 'pastor', 'bishop']
        .contains(role);
    final canRun = ['superadmin', 'coa_employee'].contains(role);

    if (!allowed) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Platform Fees'),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Access restricted.')),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Platform Fees & Reconciliation'),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _kpiRow(theme),
                  const SizedBox(height: 12),
                  if (canRun) _runButton(theme),
                  const SizedBox(height: 16),
                  _sectionTitle(theme, 'Fee Sweeps', LucideIcons.receipt),
                  const SizedBox(height: 8),
                  if (_sweeps.isEmpty)
                    _empty(theme, 'No fee sweeps yet. The COA payout cut is swept '
                        'to the settlement number once it crosses the minimum.')
                  else
                    ..._sweeps.map((s) => _sweepRow(theme, s)),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _kpiRow(ThemeData theme) {
    return Row(
      children: [
        _kpi(theme, 'Earned', 'K${_summary.payoutFeesEarned.toStringAsFixed(2)}', Colors.green),
        const SizedBox(width: 8),
        _kpi(theme, 'Settled', 'K${_summary.payoutFeesSettled.toStringAsFixed(2)}', Colors.teal),
        const SizedBox(width: 8),
        _kpi(theme, 'Pending', 'K${_summary.payoutFeesPending.toStringAsFixed(2)}', Colors.orange),
        const SizedBox(width: 8),
        _kpi(theme, 'Collected', 'K${_summary.totalCollected.toStringAsFixed(2)}', theme.primaryColor),
        const SizedBox(width: 8),
        _kpi(theme, 'Paid out', 'K${_summary.totalPaidOut.toStringAsFixed(2)}', Colors.blueGrey),
      ],
    );
  }

  Widget _kpi(ThemeData theme, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(label, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }

  Widget _runButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _running ? null : _runSettlement,
        style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700, padding: const EdgeInsets.symmetric(vertical: 14)),
        icon: _running
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(LucideIcons.refreshCw),
        label: Text(_running ? 'Reconciling…' : 'Run reconciliation & sweep now'),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
      ],
    );
  }

  Widget _sweepRow(ThemeData theme, FeeSweepRecord s) {
    final (color, label) = switch (s.status) {
      'success' => (Colors.green, 'SETTLED'),
      'pending' => (Colors.orange, 'PENDING'),
      'failed' => (Colors.red, 'FAILED'),
      _ => (Colors.grey, s.status.toUpperCase()),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('K${s.amount.toStringAsFixed(2)} · ${s.kind}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface)),
                if (s.lipilaReference != null)
                  Text(s.lipilaReference!, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                if (s.lastError != null)
                  Text(s.lastError!, style: const TextStyle(fontSize: 10, color: Colors.red),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (s.createdAt != null)
            Text('${s.createdAt!.day}/${s.createdAt!.month}',
                style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  Widget _empty(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      child: Text(text, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
    );
  }
}
