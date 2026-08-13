import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/admin/data/church_payout_service.dart';

/// Church Auto-Payout dashboard (superadmin / COA employee).
///
/// Mirrors the Kingdom Sponsor (chisomo) host payout model: giving collected
/// to a church accumulates into a server-side withdrawable balance, and when it
/// crosses the configured threshold (`church_payout_min_kwacha`) the settlement
/// engine automatically disburses it to the church treasurer phone. This screen
/// is read-only oversight — balances are derived server-side and cannot be
/// edited from the client. "Run settlement now" just triggers the same cron job.
class ChurchPayoutScreen extends ConsumerStatefulWidget {
  const ChurchPayoutScreen({super.key});

  @override
  ConsumerState<ChurchPayoutScreen> createState() => _ChurchPayoutScreenState();
}

class _ChurchPayoutScreenState extends ConsumerState<ChurchPayoutScreen> {
  List<ChurchWithdrawable> _balances = [];
  List<ChurchWithdrawalRecord> _withdrawals = [];
  bool _loading = true;
  bool _running = false;
  String? _error;

  ChurchPayoutService get _service => ref.read(churchPayoutServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchWithdrawableBalances(),
        _service.fetchWithdrawals(),
      ]);
      if (!mounted) return;
      setState(() {
        _balances = results[0] as List<ChurchWithdrawable>;
        _withdrawals = results[1] as List<ChurchWithdrawalRecord>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _runSettlement() async {
    setState(() => _running = true);
    try {
      final res = await _service.runSettlementNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Settlement run: ${res['churchPayoutsEnqueued'] ?? 0} church payout(s) enqueued, '
            '${res['payoutPaid'] ?? 0} task(s) paid',
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
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Church Auto-Payout'),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red.shade300),
                      const SizedBox(height: 12),
                      Center(child: Text('Error: $_error')),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _kpiRow(theme),
                      const SizedBox(height: 12),
                      _runButton(theme),
                      const SizedBox(height: 16),
                      _sectionTitle(theme, 'Withdrawable Balances', LucideIcons.wallet),
                      const SizedBox(height: 8),
                      if (_balances.isEmpty)
                        const _EmptyNote(
                          icon: LucideIcons.inbox,
                          text: 'No churches with a withdrawable giving balance yet.\n'
                              'Collections appear here after they are confirmed by the Lipila webhook.',
                        )
                      else
                        ..._balances.map((b) => _balanceCard(theme, b)),
                      const SizedBox(height: 20),
                      _sectionTitle(theme, 'Payout Ledger', LucideIcons.history),
                      const SizedBox(height: 8),
                      if (_withdrawals.isEmpty)
                        const _EmptyNote(
                          icon: LucideIcons.clock,
                          text: 'No automatic payouts sent yet.',
                        )
                      else
                        ..._withdrawals.map((w) => _ledgerRow(theme, w)),
                      const SizedBox(height: 24),
                    ],
                  ),
      ),
    );
  }

  Widget _kpiRow(ThemeData theme) {
    final totalWithdrawable = _balances.fold<double>(0, (s, b) => s + b.withdrawable);
    final totalGross = _balances.fold<double>(0, (s, b) => s + b.grossCollected);
    final paid = _withdrawals
        .where((w) => w.status == 'paid')
        .fold<double>(0, (s, w) => s + (w.netAmount ?? 0));
    final inFlight = _withdrawals.where((w) => w.isInFlight).length;

    return Row(
      children: [
        _kpi(theme, 'Eligible', '${_balances.length}', LucideIcons.building, Colors.indigo),
        const SizedBox(width: 8),
        _kpi(theme, 'Withdrawable', 'K${_fmt(totalWithdrawable)}', LucideIcons.wallet, Colors.amber),
        const SizedBox(width: 8),
        _kpi(theme, 'Gross', 'K${_fmt(totalGross)}', LucideIcons.banknote, Colors.green),
        const SizedBox(width: 8),
        _kpi(theme, 'In-Flight', '$inFlight', LucideIcons.loader, Colors.orange),
        const SizedBox(width: 8),
        _kpi(theme, 'Paid', 'K${_fmt(paid)}', LucideIcons.checkCircle, Colors.teal),
      ],
    );
  }

  Widget _kpi(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
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
            : const Icon(LucideIcons.play),
        label: Text(_running ? 'Running settlement…' : 'Run settlement now'),
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

  Widget _balanceCard(ThemeData theme, ChurchWithdrawable b) {
    final eligible = b.withdrawable > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(b.churchName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (eligible ? Colors.green : Colors.grey).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  eligible ? 'READY' : 'BELOW MIN',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: eligible ? Colors.green : Colors.grey),
                ),
              ),
            ],
          ),
          if (b.treasurerPhone != null)
            Text('Treasurer: +${b.treasurerPhone}', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          Row(
            children: [
              _kv(theme, 'Gross', 'K${_fmt(b.grossCollected)}'),
              _kv(theme, 'Committed', 'K${_fmt(b.committedGiving)}'),
              _kv(theme, 'In-flight', 'K${_fmt(b.inFlightWithdrawals)}'),
              _kv(theme, 'Withdrawable', 'K${_fmt(b.withdrawable)}', highlight: eligible),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String label, String value, {bool highlight = false}) {
    final color = highlight ? Colors.green : theme.colorScheme.onSurface;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.6))),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _ledgerRow(ThemeData theme, ChurchWithdrawalRecord w) {
    final (color, label) = switch (w.status) {
      'paid' => (Colors.green, 'PAID'),
      'pending' => (Colors.orange, 'PENDING'),
      'processing' => (Colors.blue, 'PROCESSING'),
      'failed' => (Colors.red, 'FAILED'),
      _ => (Colors.grey, w.status.toUpperCase()),
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
                Text(w.churchName ?? w.churchId, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface)),
                Text(
                  'K${_fmt(w.grossAmount)} gross · K${_fmt(w.netAmount ?? 0)} net · +${w.recipientPhone}',
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                if (w.lastError != null)
                  Text(w.lastError!, style: const TextStyle(fontSize: 10, color: Colors.red), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_ago(w.createdAt), style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(2);

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}
