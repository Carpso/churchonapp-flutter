import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
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

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          "${tenant.name} Finance",
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
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
                const SizedBox(height: 30),
                Text("Stewardship Analytics", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 20),
                _buildChartCard(theme, "Daily Contribution Trend", _buildLineChart(theme, txs)),
                const SizedBox(height: 20),
                _buildChartCard(theme, "Category Breakdown", _buildPieChart(theme, tithesTotal, offeringsTotal, eventsTotal, productsTotal)),
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
