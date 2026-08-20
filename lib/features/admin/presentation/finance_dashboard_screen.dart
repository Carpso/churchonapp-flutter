import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';
import 'package:church_on_app/features/admin/presentation/church_payout_screen.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ledger_screen.dart';

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
                _buildSummaryCard(context, totalBalance, thisMonthTotal, tithesTotal, offeringsTotal),
                const SizedBox(height: 15),
                _buildWithdrawableCard(context, ref, tenant.id),
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
                      "K ${tx.amount.toStringAsFixed(2)}",
                      "${tx.createdAt.day}/${tx.createdAt.month} ${tx.createdAt.hour}:${tx.createdAt.minute}",
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

  Widget _buildSummaryCard(BuildContext context, double total, double monthly, double tithes, double offerings) {
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
                      "K ${NumberFormat.compactCurrency(symbol: '', decimalDigits: 1).format(total)}",
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
              _buildMiniStat("This Month", "K ${NumberFormat.compact().format(monthly)}", LucideIcons.trendingUp, Colors.greenAccent),
              _buildMiniStat("Tithes", "K ${NumberFormat.compact().format(tithes)}", LucideIcons.heart, Theme.of(context).primaryColor),
              _buildMiniStat("Offerings", "K ${NumberFormat.compact().format(offerings)}", LucideIcons.coins, Colors.amberAccent),
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

  Widget _buildWithdrawableCard(BuildContext context, WidgetRef ref, String tenantId) {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: Supabase.instance.client.rpc('get_church_withdrawable_balances'),
      builder: (context, snapshot) {
        final data = snapshot.data;
        double withdrawable = 0.0;
        double inFlight = 0.0;
        if (data is Map<String, dynamic>) {
          withdrawable = ((data['withdrawable'] ?? 0) as num).toDouble();
          inFlight = ((data['in_flight'] ?? 0) as num).toDouble();
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
                      "K ${withdrawable.toStringAsFixed(2)}",
                      style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface),
                    ),
                    if (inFlight > 0)
                      Text("$inFlight in flight", style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                  ],
                ),
              ),
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

  Widget _buildGivingTrendCard(ThemeData theme, WidgetRef ref, String tenantId) {
    final seriesAsync = ref.watch(churchGivingSeriesProvider(tenantId));
    return seriesAsync.when(
      data: (series) {
        if (series.length < 2) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Center(child: Text("Not enough giving history", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11))),
          );
        }
        final maxTotal = series.fold<double>(0, (max, e) {
          final t = (e['total'] as num?)?.toDouble() ?? 0;
          return t > max ? t : max;
        });
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Giving Trend (6 months)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 20),
              SizedBox(
                height: 160,
                child: BarChart(
                  BarChartData(
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= series.length) return const SizedBox.shrink();
                            final month = (series[idx]['month'] as String? ?? '');
                            if (month.length >= 7) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(month.substring(5, 7), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ),
                    barGroups: List.generate(series.length, (i) {
                      final total = (series[i]['total'] as num?)?.toDouble() ?? 0;
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: total,
                            width: 18,
                            borderRadius: BorderRadius.circular(6),
                            color: total > 0 ? Colors.amber.shade600 : theme.primaryColor.withValues(alpha: 0.15),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: maxTotal > 0 ? maxTotal : 1,
                              color: Colors.amber.withValues(alpha: 0.06),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const ShimmerLoader.rectangular(height: 200, width: double.infinity),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 20),
          SizedBox(height: 180, child: chart),
        ],
      ),
    );
  }

  Widget _buildLineChart(ThemeData theme, List<Transaction> txs) {
    final Map<String, double> dailyTotals = {};
    for (var tx in txs) {
      final dateKey = "${tx.createdAt.month}/${tx.createdAt.day}";
      dailyTotals[dateKey] = (dailyTotals[dateKey] ?? 0) + tx.amount;
    }

    final sortedKeys = dailyTotals.keys.toList()..sort();
    final spots = sortedKeys.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), dailyTotals[e.value] ?? 0);
    }).toList();

    if (spots.isEmpty) {
      return Center(child: Text("Not enough trend data", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)));
    }

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.amber,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.amber.withValues(alpha: 0.05),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChart(ThemeData theme, double tithes, double offerings, double events, double products) {
    final total = tithes + offerings + events + products;
    if (total == 0.0) {
      return Center(child: Text("No contributions to classify", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)));
    }

    return PieChart(
      PieChartData(
        sections: [
          if (tithes > 0)
            PieChartSectionData(
              value: tithes,
              title: 'Tithe (${(tithes/total*100).toStringAsFixed(0)}%)',
              color: Colors.green,
              radius: 50,
              titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          if (offerings > 0)
            PieChartSectionData(
              value: offerings,
              title: 'Offering (${(offerings/total*100).toStringAsFixed(0)}%)',
              color: Colors.orange,
              radius: 50,
              titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          if (events > 0)
            PieChartSectionData(
              value: events,
              title: 'Events (${(events/total*100).toStringAsFixed(0)}%)',
              color: theme.primaryColor,
              radius: 50,
              titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          if (products > 0)
            PieChartSectionData(
              value: products,
              title: 'Market (${(products/total*100).toStringAsFixed(0)}%)',
              color: theme.primaryColor.withValues(alpha: 0.55),
              radius: 50,
              titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
            ),
        ],
        centerSpaceRadius: 40,
        sectionsSpace: 5,
      ),
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
