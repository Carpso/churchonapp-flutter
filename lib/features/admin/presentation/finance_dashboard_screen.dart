import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/pro_charts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/features/finance/data/ledger_pdf_service.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';
import 'package:church_on_app/features/admin/presentation/church_payout_screen.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ledger_screen.dart';

/// Session-only privacy toggle — hides all monetary figures behind `K ****`.
/// Deliberately NOT persisted (SharedPreferences) so a shared device never
/// leaks balances into unencrypted local caches.
final financePrivacyProvider = StateProvider<bool>((ref) => false);

String moneyOrMasked(double value, bool hidden, {bool compact = false}) {
  if (hidden) return 'K ****';
  return compact
      ? NumberFormat.compactCurrency(symbol: 'K ', decimalDigits: 1).format(value)
      : 'K ${value.toStringAsFixed(2)}';
}

class FinanceDashboardScreen extends ConsumerWidget {
  const FinanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tenant = ref.watch(currentTenantProvider);
    if (tenant == null) {
      return const Scaffold(
        body: Center(child: Text("No Church Selected")),
      );
    }

    final ledgerAsync = ref.watch(ledgerStreamProvider(tenant.id));
    final givingOverviewAsync = ref.watch(churchGivingOverviewProvider);
    final hideMoney = ref.watch(financePrivacyProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          "${tenant.name} Finance",
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          // Privacy toggle — masks every currency figure on this dashboard.
          IconButton(
            tooltip: hideMoney ? 'Show amounts' : 'Hide amounts',
            icon: Icon(hideMoney ? LucideIcons.eyeOff : LucideIcons.eye),
            onPressed: () => ref.read(financePrivacyProvider.notifier).state = !hideMoney,
          ),
          IconButton(
            tooltip: 'Report Creator',
            icon: const Icon(LucideIcons.filePlus2),
            onPressed: () => context.push('/report-creator'),
          ),
        ],
      ),
      body: ledgerAsync.when(
        data: (txs) {
          double totalBalance = 0.0;
          double tithesTotal = 0.0;
          double offeringsTotal = 0.0;
          double eventsTotal = 0.0;
          double productsTotal = 0.0;

          final now = DateTime.now();
          double thisMonthTotal = 0.0;

          for (var tx in txs) {
            totalBalance += tx.amount;
            if (tx.createdAt.year == now.year && tx.createdAt.month == now.month) {
              thisMonthTotal += tx.amount;
            }

            final cat = tx.category.toLowerCase();
            if (cat == 'tithe') {
              tithesTotal += tx.amount;
            } else if (cat == 'offering') {
              offeringsTotal += tx.amount;
            } else if (cat == 'event') {
              eventsTotal += tx.amount;
            } else if (cat == 'product') {
              productsTotal += tx.amount;
            }
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(ledgerStreamProvider(tenant.id));
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                _buildSummaryCard(context, totalBalance, thisMonthTotal, tithesTotal, offeringsTotal, hideMoney),
                const SizedBox(height: 15),
                _buildWithdrawableCard(context, ref, tenant.id, hideMoney),
                const SizedBox(height: 16),
                _buildLedgerActions(context, ref, tenant, txs, theme),
                const SizedBox(height: 30),
                Text("Stewardship Analytics", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 20),
                _buildChartCard(theme, "Daily Contribution Trend", _buildLineChart(theme, txs)),
                const SizedBox(height: 20),
                _buildGivingTrendCard(theme, ref, tenant.id),
                const SizedBox(height: 20),
                _buildChartCard(theme, "Category Breakdown", _buildPieChart(theme, tithesTotal, offeringsTotal, eventsTotal, productsTotal)),
                const SizedBox(height: 30),
                Text("Top Givers This Month", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 15),
                _buildRecentGivers(theme, givingOverviewAsync),
                const SizedBox(height: 30),
                Text("Recent Transactions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 15),
                if (txs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text("No transactions recorded yet.", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)))),
                  )
                else
                  ...txs.take(5).map((tx) {
                    Color catColor = Theme.of(context).primaryColor;
                    final cat = tx.category.toLowerCase();
                    if (cat == 'tithe') catColor = Colors.green;
                    if (cat == 'offering') catColor = Colors.orange;
                    if (cat == 'event') catColor = Theme.of(context).primaryColor.withValues(alpha: 0.7);

                    return _buildTransactionItem(theme,
                      "${tx.category.toUpperCase()} - ${tx.reference.substring(0, tx.reference.length > 8 ? 8 : tx.reference.length)}",
                      moneyOrMasked(tx.amount, hideMoney),
                      DateFormat('d/M HH:mm').format(tx.createdAt),
                      catColor,
                    );
                  }),
              ],
            ),
          ),
          );
        },
        loading: () => const _FinanceDashboardShimmer(),
        error: (err, st) => Center(child: Text("Error loading financial reports: $err")),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, double total, double monthly, double tithes, double offerings, bool hideMoney) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TREASURY", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 5),
                  Flexible(
                    child: Text(
                      moneyOrMasked(total, hideMoney, compact: true),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                child: const Icon(LucideIcons.landmark, color: Colors.amber, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 25),
          const Divider(color: Colors.white12),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStat("This Month", moneyOrMasked(monthly, hideMoney, compact: true), LucideIcons.trendingUp, Colors.greenAccent),
              _buildMiniStat("Tithes", moneyOrMasked(tithes, hideMoney, compact: true), LucideIcons.heart, Theme.of(context).primaryColor),
              _buildMiniStat("Offerings", moneyOrMasked(offerings, hideMoney, compact: true), LucideIcons.coins, Colors.amberAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _buildWithdrawableCard(BuildContext context, WidgetRef ref, String tenantId, bool hideMoney) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).value;
    // PAYOUTS button → ChurchPayoutScreen (COA settlement engine) is
    // superadmin/COA-employee-only; pastors/bishops/treasurers still see
    // their church's withdrawable balance but can't open COA settlement.
    final isCoaTeam =
        profile != null && (profile.isSuperadmin || profile.role == 'coa_employee');
    return FutureBuilder<Map<String, dynamic>>(
      future: Supabase.instance.client.rpc('get_church_withdrawable_balances'),
      builder: (context, snapshot) {
        final data = snapshot.data;
        double withdrawable = 0.0;
        double inFlight = 0.0;
        if (data is Map<String, dynamic>) {
          withdrawable = ((data['withdrawable'] ?? 0) as num?)?.toDouble() ?? 0.0;
          inFlight = ((data['in_flight'] ?? 0) as num?)?.toDouble() ?? 0.0;
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: const Icon(LucideIcons.wallet, color: Colors.green, size: 22),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Withdrawable Balance", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text(
                      moneyOrMasked(withdrawable, hideMoney),
                      style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface),
                    ),
                    if (inFlight > 0)
                      Text("${moneyOrMasked(inFlight, hideMoney)} in flight", style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                  ],
                ),
              ),
              if (isCoaTeam)
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChurchPayoutScreen()),
                  ),
                  icon: const Icon(LucideIcons.arrowRight, size: 15),
                  label: const Text("PAYOUTS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLedgerActions(BuildContext context, WidgetRef ref, Tenant tenant, List<Transaction> txs, ThemeData theme) {
    final total = txs.fold<double>(0, (s, t) => s + t.amount);
    // Stacked vertically — Row with two Expanded buttons overflowed on narrow phones.
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: txs.isEmpty
                ? null
                : () => LedgerPdfService.generateAndPrintLedger(txs, tenant.id),
            icon: Icon(LucideIcons.fileOutput, size: 14, color: theme.primaryColor),
            label: const Text('Export PDF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primaryColor,
              side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.22)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              backgroundColor: theme.colorScheme.surface,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: txs.isEmpty
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Text('Confirm Remittance'),
                        content: Text('Remit K ${total.toStringAsFixed(2)} to HQ / Bishop? This creates a negative ledger entry.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remit')),
                        ],
                      ),
                    );
                    if (confirm != true || !context.mounted) return;
                    await ref.read(financeServiceProvider).logTransaction(-total, 'remittance', 'HQ Remittance - ${DateTime.now().toIso8601String()}', tenantId: tenant.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Remittance completed')));
                      ref.invalidate(ledgerStreamProvider(tenant.id));
                    }
                  },
            icon: const Icon(LucideIcons.landmark, size: 14, color: Colors.white),
            label: const Text('Remit to HQ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGivingTrendCard(ThemeData theme, WidgetRef ref, String tenantId) {
    final seriesAsync = ref.watch(churchGivingSeriesProvider(tenantId));
    return seriesAsync.when(
      data: (series) {
        if (series.length < 2) {
          return ProChartCard(
            title: 'Giving Trend',
            subtitle: '6 months',
            height: 160,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.barChart3, size: 28, color: theme.colorScheme.onSurface.withValues(alpha: 0.18)),
                  const SizedBox(height: 8),
                  Text('Not enough giving history yet', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w600)),
                  Text('Two months of giving unlocks the trend', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.35), fontSize: 10)),
                ],
              ),
            ),
          );
        }
        final values = series.map<double>((e) => (e['total'] as num?)?.toDouble() ?? 0).toList();
        final labels = series.map<String>((e) {
          final m = (e['month'] as String? ?? '');
          if (m.length >= 7) {
            try {
              final dt = DateTime.parse('$m-01');
              return DateFormat.MMM().format(dt);
            } catch (_) {
              return m.substring(5, 7);
            }
          }
          return '';
        }).toList();
        final total6m = values.fold<double>(0, (s, v) => s + v);
        return ProChartCard(
          title: 'Giving Trend',
          subtitle: 'Last 6 months • ${NumberFormat.compactCurrency(symbol: 'K ').format(total6m)} total',
          height: 180,
          child: ProBarChart(values: values, labels: labels),
        );
      },
      loading: () => const ShimmerLoader.rectangular(height: 220, width: double.infinity),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildRecentGivers(ThemeData theme, AsyncValue<ChurchGivingOverview> overviewAsync) {
    return overviewAsync.when(
      data: (overview) {
        if (overview.givers.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(child: Text("No givers recorded yet this month", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12))),
          );
        }
        return Column(
          children: overview.givers.take(8).map((g) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
                    child: Icon(LucideIcons.heart, size: 15, color: theme.primaryColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          "K ${g.amount.toStringAsFixed(2)}",
                          style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    "${g.createdAt.day}/${g.createdAt.month}",
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
      loading: () => const ShimmerLoader.rectangular(height: 160, width: double.infinity),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildChartCard(ThemeData theme, String title, Widget chart) {
    return ProChartCard(title: title, height: 180, child: chart);
  }

  Widget _buildLineChart(ThemeData theme, List<Transaction> txs) {
    final Map<String, double> dailyTotals = {};
    for (var tx in txs) {
      final dateKey = DateFormat('MM/dd').format(tx.createdAt);
      dailyTotals[dateKey] = (dailyTotals[dateKey] ?? 0) + tx.amount;
    }
    // Sort by actual date, not string
    final entries = dailyTotals.entries.toList()
      ..sort((a, b) {
        try {
          return DateFormat('MM/dd').parse(a.key).compareTo(DateFormat('MM/dd').parse(b.key));
        } catch (_) {
          return a.key.compareTo(b.key);
        }
      });
    final spots = entries.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value)).toList();
    final labels = entries.map((e) => e.key).toList();
    if (spots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.trendingUp, size: 22, color: theme.colorScheme.onSurface.withValues(alpha: 0.18)),
            const SizedBox(height: 6),
            Text('No trend yet — transactions will plot here', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.45), fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return ProLineChart(spots: spots, bottomLabels: labels);
  }

  Widget _buildPieChart(ThemeData theme, double tithes, double offerings, double events, double products) {
    final total = tithes + offerings + events + products;
    if (total == 0.0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.pieChart, size: 22, color: theme.colorScheme.onSurface.withValues(alpha: 0.18)),
            const SizedBox(height: 6),
            Text('No contributions to classify yet', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.45), fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return ProPieChart(
      centerValue: NumberFormat.compactCurrency(symbol: 'K ').format(total),
      centerLabel: 'TOTAL',
      sections: [
        if (tithes > 0) ProPieSection(label: 'Tithe', value: tithes, color: const Color(0xFF16A34A)),
        if (offerings > 0) ProPieSection(label: 'Offering', value: offerings, color: const Color(0xFFF59E0B)),
        if (events > 0) ProPieSection(label: 'Events', value: events, color: theme.primaryColor),
        if (products > 0) ProPieSection(label: 'Market', value: products, color: const Color(0xFF6366F1)),
      ],
    );
  }

  Widget _buildTransactionItem(ThemeData theme, String title, String amount, String time, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 5)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(LucideIcons.banknote, color: color, size: 18),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
                Text(time, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
              ],
            ),
          ),
          Text(amount, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 14)),
        ],
      ),
    );
  }
}

/// 6-month giving trend for the selected church (server-side RPC).
final churchGivingSeriesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, tenantId) {
  return ref.watch(organizationServiceProvider).getChurchGivingSeries(tenantId);
});

class _FinanceDashboardShimmer extends StatelessWidget {
  const _FinanceDashboardShimmer();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerLoader.rectangular(height: 150, width: double.infinity),
          const SizedBox(height: 30),
          const ShimmerLoader.rectangular(height: 18, width: 180),
          const SizedBox(height: 20),
          const ShimmerLoader.rectangular(height: 200, width: double.infinity),
          const SizedBox(height: 20),
          const ShimmerLoader.rectangular(height: 200, width: double.infinity),
          const SizedBox(height: 30),
          const ShimmerLoader.rectangular(height: 18, width: 140),
          const SizedBox(height: 15),
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ShimmerLoader.rectangular(height: 70),
            ),
          ),
        ],
      ),
    );
  }
}
