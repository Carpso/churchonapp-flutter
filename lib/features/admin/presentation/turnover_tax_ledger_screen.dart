import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import '../../../core/services/supabase_service.dart';

class TaxLedgerEntry {
  final String id;
  final DateTime date;
  final String reference;
  final String category;
  final double grossCollectedZmw;
  final double platformRevenueZmw;
  final double turnoverTax3PctZmw;
  final String status;

  TaxLedgerEntry({
    required this.id,
    required this.date,
    required this.reference,
    required this.category,
    required this.grossCollectedZmw,
    required this.platformRevenueZmw,
    required this.turnoverTax3PctZmw,
    required this.status,
  });
}

final turnoverTaxLedgerProvider = FutureProvider.family<List<TaxLedgerEntry>, DateTime>((ref, monthDate) async {
  final supabase = ref.read(supabaseServiceProvider);
  final startOfMonth = DateTime(monthDate.year, monthDate.month, 1);
  final endOfMonth = DateTime(monthDate.year, monthDate.month + 1, 0, 23, 59, 59);

  final res = await supabase.client
      .from('payment_logs')
      .select('id, amount, metadata, category, status, created_at, tx_ref')
      .gte('created_at', startOfMonth.toIso8601String())
      .lte('created_at', endOfMonth.toIso8601String())
      .order('created_at', ascending: false);

  final entries = <TaxLedgerEntry>[];
  for (final map in (res as List)) {
    final amount = (map['amount'] as num?)?.toDouble() ?? 0.0;
    final meta = map['metadata'] as Map<String, dynamic>? ?? {};
    final category = map['category'] as String? ?? meta['category'] as String? ?? 'general';
    final status = (map['status'] as String? ?? 'completed').toLowerCase();

    // Determine gross revenue vs COA platform profit cut for Zambia Turnover Tax (3%)
    double coaRevenue = 0.0;
    final c = category.toLowerCase();
    if (c == 'ride' || c == 'event' || c == 'marketplace' || c == 'bookshop' || c == 'writer' || c == 'vendor' || c == 'product') {
      coaRevenue = amount * 0.10;
    } else {
      final raw = amount * 0.01;
      coaRevenue = raw < 3.0 ? 3.0 : (raw > 50.0 ? 50.0 : raw);
    }

    final tax3Pct = coaRevenue * 0.03; // Zambia Turnover Tax rate: 3%

    entries.add(TaxLedgerEntry(
      id: map['id']?.toString() ?? '',
      date: DateTime.parse(map['created_at'] as String),
      reference: map['tx_ref'] as String? ?? map['id']?.toString() ?? 'N/A',
      category: category,
      grossCollectedZmw: amount,
      platformRevenueZmw: coaRevenue,
      turnoverTax3PctZmw: tax3Pct,
      status: status,
    ));
  }
  return entries;
});

class TurnoverTaxLedgerScreen extends ConsumerStatefulWidget {
  const TurnoverTaxLedgerScreen({super.key});

  @override
  ConsumerState<TurnoverTaxLedgerScreen> createState() => _TurnoverTaxLedgerScreenState();
}

class _TurnoverTaxLedgerScreenState extends ConsumerState<TurnoverTaxLedgerScreen> {
  DateTime _selectedMonth = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(turnoverTaxLedgerProvider(_selectedMonth));
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final dueDayLabel = DateFormat('MMMM 14, yyyy').format(
      DateTime(_selectedMonth.year, _selectedMonth.month + 1, 14),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Turnover Tax Ledger (ZRA)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.calendar, color: Colors.amber),
            onPressed: _pickMonth,
          ),
        ],
      ),
      body: ledgerAsync.when(
        data: (entries) {
          double totalGross = 0;
          double totalPlatformRevenue = 0;
          double totalTurnoverTaxDue = 0;

          for (final e in entries) {
            if (e.status == 'completed' || e.status == 'settled' || e.status == 'success') {
              totalGross += e.grossCollectedZmw;
              totalPlatformRevenue += e.platformRevenueZmw;
              totalTurnoverTaxDue += e.turnoverTax3PctZmw;
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Month Header Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)]),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(monthLabel, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                            child: const Text('3% ZRA Turnover Tax', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Payment Due Date: $dueDayLabel', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Stat Cards Row
                Row(
                  children: [
                    Expanded(
                      child: _statCard('Gross Volume', 'K${totalGross.toStringAsFixed(2)}', LucideIcons.wallet, Colors.blue),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard('COA Revenue', 'K${totalPlatformRevenue.toStringAsFixed(2)}', LucideIcons.trendingUp, Colors.greenAccent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard('Tax Due (3%)', 'K${totalTurnoverTaxDue.toStringAsFixed(2)}', LucideIcons.receipt, Colors.amber),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                const Text('Auditable Itemized Ledger', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),

                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('No logged transactions for this month', style: TextStyle(color: Colors.white54))),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final e = entries[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.fileText, color: e.status == 'completed' ? Colors.greenAccent : Colors.redAccent, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.category.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('${DateFormat('MMM d, HH:mm').format(e.date)} · Ref: ${e.reference}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Gross: K${e.grossCollectedZmw.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                Text('Tax: K${e.turnoverTax3PctZmw.toStringAsFixed(2)}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
        loading: () => const Center(child: ListSkeleton()),
        error: (err, _) => Center(child: Text('Error loading tax ledger: $err', style: const TextStyle(color: Colors.white54))),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          FittedBox(child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14))),
        ],
      ),
    );
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month, 1));
    }
  }
}
