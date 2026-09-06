import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/features/finance/data/ledger_pdf_service.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:church_on_app/core/widgets/pro_charts.dart';
import 'package:intl/intl.dart';

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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.14)),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.info, size: 14, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Consolidated — Finance Dashboard is now the single source for ledger, trends & payouts. This view shares the same professional chart engine.',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/finance-dashboard'),
                          child: const Text('Open', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(child: _buildAnalyticsSection(context, txs)),
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
                  child: _buildTxItem(context, txs[index]),
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

  Widget _buildAnalyticsSection(BuildContext context, List<Transaction> txs) {
    return Column(
      children: [
        _buildTrendChart(context, txs),
        const SizedBox(height: 20),
        _buildCategoryDistribution(context, txs),
      ],
    );
  }

  Widget _buildTrendChart(BuildContext context, List<Transaction> txs) {
    final Map<String, double> dailyTotals = {};
    for (var tx in txs) {
      final key = DateFormat('MM/dd').format(tx.createdAt);
      dailyTotals[key] = (dailyTotals[key] ?? 0) + tx.amount;
    }
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
    return ProChartCard(
      title: 'Financial Trend',
      subtitle: 'Daily net — ${txs.length} transactions',
      height: 200,
      child: ProLineChart(spots: spots, bottomLabels: labels),
    );
  }

  Widget _buildCategoryDistribution(BuildContext context, List<Transaction> txs) {
    double tithes = 0;
    double offerings = 0;
    double others = 0;
    for (var tx in txs) {
      final cat = tx.category.toLowerCase();
      if (cat.contains('tithe')) {
        tithes += tx.amount;
      } else if (cat.contains('offering') || cat.contains('giving')) {
        offerings += tx.amount;
      } else {
        others += tx.amount;
      }
    }
    final total = tithes + offerings + others;
    if (total == 0) return const SizedBox.shrink();
    return ProChartCard(
      title: 'Giving Distribution',
      subtitle: 'Share by category • ${NumberFormat.compactCurrency(symbol: 'K ').format(total)} total',
      height: 220,
      child: ProPieChart(
        centerValue: NumberFormat.compactCurrency(symbol: 'K ').format(total),
        centerLabel: 'TOTAL',
        sections: [
          if (tithes > 0) ProPieSection(label: 'Tithes', value: tithes, color: Theme.of(context).primaryColor),
          if (offerings > 0) ProPieSection(label: 'Offerings', value: offerings, color: const Color(0xFFF59E0B)),
          if (others > 0) ProPieSection(label: 'Other', value: others, color: const Color(0xFF94A3B8)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, List<Transaction> txs, WidgetRef ref, String tenantId) {
    final tenantName = ref.read(currentTenantProvider)?.name ?? tenantId;
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
                onPressed: () => LedgerPdfService.generateAndPrintLedger(txs, tenantName),
                icon: Icon(LucideIcons.fileOutput, color: Theme.of(context).primaryColor, size: 20),
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

  Widget _buildTxItem(BuildContext context, Transaction tx) {
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
            decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Icon(LucideIcons.arrowDownLeft, color: Theme.of(context).primaryColor, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.category.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
if (tx.userId.isNotEmpty)
        _GiverName(userId: tx.userId)
                else
                  Text(tx.reference, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("${tx.amount < 0 ? '-' : '+'} K ${tx.amount.abs().toStringAsFixed(2)}",
                  style: TextStyle(color: tx.amount < 0 ? Colors.red : Colors.green, fontWeight: FontWeight.w900, fontSize: 16)),
              Text("${tx.createdAt.day}/${tx.createdAt.month} ${tx.createdAt.hour}:${tx.createdAt.minute}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

final Map<String, String> _giverNameCache = {};

class _GiverName extends StatefulWidget {
  final String userId;

  const _GiverName({required this.userId});

  @override
  State<_GiverName> createState() => _GiverNameState();
}

class _GiverNameState extends State<_GiverName> {
  String? _name;

  @override
  void initState() {
    super.initState();
    final cached = _giverNameCache[widget.userId];
    if (cached != null) {
      _name = cached;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', widget.userId)
          .maybeSingle();
      final name = res?['full_name']?.toString();
      if (name != null && name.isNotEmpty) {
        _giverNameCache[widget.userId] = name;
        if (mounted) setState(() => _name = name);
      }
    } catch (e) {
      debugPrint('ledger giver name lookup failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = _name ?? widget.userId.substring(0, 8);
    return Text(display, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis);
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

