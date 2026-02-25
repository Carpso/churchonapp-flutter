import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/finance_service.dart';
import '../../../core/providers/profile_provider.dart';
import 'package:intl/intl.dart';

class TitheHistoryScreen extends ConsumerWidget {
  const TitheHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final bool isPastor = profile?.role == 'pastor' || profile?.role == 'admin';

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Tithe & Offering Sheet", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: transactionsAsync.when(
        data: (transactions) {
          final totalAmount = transactions.fold(0.0, (sum, t) => sum + t.amount);
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryCard(
                  isPastor ? "TOTAL COLLECTED (PERSONAL)" : "MY TOTAL GIVING", 
                  totalAmount, 
                  Colors.green
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("History Tracking", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (isPastor)
                      const Text("PASTOR VIEW", style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 15),
                if (transactions.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.only(top: 40.0),
                    child: Text("No records found.", style: TextStyle(color: Colors.grey)),
                  ))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final t = transactions[index];
                      return _buildTitheCard(
                        t.category.toUpperCase(),
                        t.amount,
                        DateFormat.yMMMd().format(t.createdAt),
                        t.status.toUpperCase(),
                      );
                    },
                  ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text("Error: $err")),
      ),
    );
  }

  Widget _buildSummaryCard(String label, double amount, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Text("K ${amount.toStringAsFixed(2)}", style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const LinearProgressIndicator(value: 1.0, backgroundColor: Color(0xFFEEEEEE), color: Colors.green),
        ],
      ),
    );
  }

  Widget _buildTitheCard(String category, double amount, String date, String status) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(LucideIcons.banknote, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(date, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("K ${amount.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              Text(status, style: TextStyle(color: status == 'COMPLETED' ? Colors.blue : Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

