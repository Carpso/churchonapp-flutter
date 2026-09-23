import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/finance/data/church_earnings_service.dart';

/// Leader-facing church earnings dashboard (chisomo host-dashboard parity).
///
/// A church leader sees ONLY their own church's withdrawable balance and payout
/// ledger. Everything is derived server-side by `get_my_church_earnings`; this
/// screen is strictly read-only. When the balance crosses the configured
/// threshold the settlement engine pays the church treasurer automatically.
class ChurchEarningsScreen extends ConsumerWidget {
  const ChurchEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(churchEarningsProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('My Church Earnings'),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(churchEarningsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 80),
              const Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Center(child: Text('Error: $e')),
            ],
          ),
          data: (data) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _hero(theme, data),
              const SizedBox(height: 16),
              _breakdown(theme, data),
              const SizedBox(height: 20),
              _sectionTitle(theme, 'Payout Ledger', LucideIcons.history),
              const SizedBox(height: 8),
              if (data.payouts.isEmpty)
                _empty(theme, 'No automatic payouts sent yet. Your giving balance '
                    'is paid to the church treasurer once it crosses the minimum.')
              else
                ...data.payouts.map((p) => _payoutRow(theme, p)),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(ThemeData theme, ChurchEarnings data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WITHDRAWABLE BALANCE',
              style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.white70)),
          const SizedBox(height: 6),
          Text('K${data.withdrawable.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            data.recipientPhone == null
                ? 'No payout number set yet — add a treasurer phone in church settings.'
                : 'Auto-paid to +${data.recipientPhone} when it reaches the minimum.',
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _breakdown(ThemeData theme, ChurchEarnings data) {
    return Row(
      children: [
        _stat(theme, 'Collected', 'K${data.grossCollected.toStringAsFixed(2)}', Colors.green),
        const SizedBox(width: 8),
        _stat(theme, 'Committed', 'K${data.committedGiving.toStringAsFixed(2)}', Colors.orange),
        const SizedBox(width: 8),
        _stat(theme, 'In-flight', 'K${data.inFlightWithdrawals.toStringAsFixed(2)}', theme.primaryColor),
        const SizedBox(width: 8),
        _stat(theme, 'Paid out', 'K${data.paidOut.toStringAsFixed(2)}', Colors.teal),
      ],
    );
  }

  Widget _stat(ThemeData theme, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.85))),
          ],
        ),
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

  Widget _payoutRow(ThemeData theme, ChurchEarningPayout p) {
    final (color, label) = switch (p.status) {
      'paid' => (Colors.green, 'PAID'),
      'pending' => (Colors.orange, 'PENDING'),
      'processing' => (theme.primaryColor, 'PROCESSING'),
      'failed' => (Colors.red, 'FAILED'),
      _ => (Colors.grey, p.status.toUpperCase()),
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
            child: Text(
              'K${p.grossAmount.toStringAsFixed(2)} gross · K${(p.netAmount ?? 0).toStringAsFixed(2)} net',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
            ),
          ),
          if (p.processedAt != null)
            Text(
              '${p.processedAt!.day}/${p.processedAt!.month}',
              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            ),
        ],
      ),
    );
  }

  Widget _empty(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
    );
  }
}
