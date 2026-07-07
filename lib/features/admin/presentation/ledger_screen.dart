import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/features/finance/data/ledger_pdf_service.dart';

import 'package:fl_chart/fl_chart.dart';

class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);
    if (tenant == null) return const Scaffold(body: Center(child: Text("No Church Selected")));

    final ledgerAsync = ref.watch(ledgerStreamProvider(tenant.id));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("${tenant.name} Ledger", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ledgerAsync.when(
        data: (txs) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(ledgerStreamProvider(tenant.id));
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildSummaryCard(context, txs, ref, tenant.id)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(child: _buildAnalyticsSection(txs)),
            ),
            const SliverPadding(
              padding: EdgeInsets.all(20),
              sliver: SliverToBoxAdapter(
                child: Text("Recent Transactions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildTxItem(txs[index]),
                ),
                childCount: txs.length,
              ),
            ),
              const SliverToBoxAdapter(child: SizedBox(height: 50)),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text("Error loading ledger: $e")),
      ),
    );
  }

  Widget _buildAnalyticsSection(List<Transaction> txs) {
    return Column(
      children: [
        _buildTrendChart(txs),
        const SizedBox(height: 20),
        _buildCategoryDistribution(txs),
      ],
    );
  }

  Widget _buildTrendChart(List<Transaction> txs) {
    // Group by date
    final Map<String, double> dailyTotals = {};
    for (var tx in txs) {
      final dateKey = "${tx.createdAt.year}-${tx.createdAt.month}-${tx.createdAt.day}";
      dailyTotals[dateKey] = (dailyTotals[dateKey] ?? 0) + tx.amount;
    }

    final sortedKeys = dailyTotals.keys.toList()..sort();
    final spots = sortedKeys.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), dailyTotals[e.value]!);
    }).toList();

    return Container(
      height: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: const Color(0xFFF1F5F9))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Financial Trend", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 4,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: Colors.blue.withValues(alpha: 0.1)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryDistribution(List<Transaction> txs) {
    double tithes = 0;
    double offerings = 0;
    double others = 0;

    for (var tx in txs) {
      final cat = tx.category.toLowerCase();
      if (cat.contains('tithe')) {
        tithes += tx.amount;
      } else if (cat.contains('offering') || cat.contains('giving')) offerings += tx.amount;
      else others += tx.amount;
    }

    final total = tithes + offerings + others;
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: const Color(0xFFF1F5F9))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Giving Distribution", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: PieChart(
              PieChartData(
                sectionsSpace: 5,
                centerSpaceRadius: 40,
                sections: [
                  PieChartSectionData(value: tithes, color: Colors.blue, title: "Tithes", radius: 20, showTitle: false),
                  PieChartSectionData(value: offerings, color: Colors.amber, title: "Offerings", radius: 20, showTitle: false),
                  PieChartSectionData(value: others, color: Colors.grey[300], title: "Other", radius: 20, showTitle: false),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLegendItem("Tithes", Colors.blue, (tithes / total * 100).toStringAsFixed(0)),
              _buildLegendItem("Offerings", Colors.amber, (offerings / total * 100).toStringAsFixed(0)),
              _buildLegendItem("Other", Colors.grey, (others / total * 100).toStringAsFixed(0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, String percent) {
    return Column(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text("$percent%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSummaryCard(BuildContext context, List<Transaction> txs, WidgetRef ref, String tenantId) {
    double total = txs.fold(0.0, (sum, item) => sum + item.amount);
    double tithes = txs.where((tx) => tx.category.toLowerCase().contains('tithe')).fold(0.0, (sum, item) => sum + item.amount);
    double offerings = txs.where((tx) => tx.category.toLowerCase().contains('offering') || tx.category.toLowerCase().contains('giving')).fold(0.0, (sum, item) => sum + item.amount);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Total Real-time Balance", style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "K ${total.toStringAsFixed(2)}",
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1),
              ),
              IconButton(
                onPressed: () => LedgerPdfService.generateAndPrintLedger(txs, "My Church"),
                icon: const Icon(LucideIcons.fileOutput, color: Colors.blue, size: 20),
                style: IconButton.styleFrom(backgroundColor: Colors.white10),
              ),
            ],
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final total = txs.fold(0.0, (sum, item) => sum + item.amount);
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Confirm Remittance"),
                    content: Text("Are you sure you want to remit K ${total.toStringAsFixed(2)} to HQ / Bishop?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await ref.read(financeServiceProvider).logTransaction(
                            -total,
                            'remittance',
                            'HQ Remittance - ${DateTime.now().toIso8601String()}',
                            tenantId: tenantId,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Remittance completed successfully")),
                            );
                          }
                        },
                        child: const Text("Confirm"),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(LucideIcons.landmark, size: 16),
              label: const Text("REMIT TO HQ / BISHOP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatItem(label: "Tithes", value: "K ${tithes.toStringAsFixed(0)}", icon: LucideIcons.trendingUp),
              _StatItem(label: "Offerings", value: "K ${offerings.toStringAsFixed(0)}", icon: LucideIcons.heart),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTxItem(Transaction tx) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
            child: const Icon(LucideIcons.arrowDownLeft, color: Colors.blue, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.category.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(tx.reference, style: const TextStyle(color: Colors.grey, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("+ K ${tx.amount.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 16)),
              Text("${tx.createdAt.day}/${tx.createdAt.month} ${tx.createdAt.hour}:${tx.createdAt.minute}", style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.white38),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}

final ledgerStreamProvider = StreamProvider.family<List<Transaction>, String>((ref, tenantId) {
  return ref.watch(financeServiceProvider).getTenantLedgerStream(tenantId);
});

