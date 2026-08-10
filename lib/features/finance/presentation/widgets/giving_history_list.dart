import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';

class GivingHistoryList extends ConsumerWidget {
  const GivingHistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    return transactionsAsync.when(
      data: (transactions) {
        if (transactions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.only(top: 40.0),
              child: Text("No stewardship records found.", style: TextStyle(color: Colors.grey)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          itemCount: transactions.length,
          itemBuilder: (context, index) => _buildHistoryItem(context, transactions[index]),
        );
      },
      loading: () => const ListSkeleton(count: 5),
      error: (err, stack) => Center(child: Text("Error loading history: $err")),
    );
  }

  Widget _buildHistoryItem(BuildContext context, Transaction item) {
    final isAdd = item.category == 'top_up' || item.amount > 0;
    final amountText = "${isAdd ? '+' : ''}K ${item.amount.toStringAsFixed(2)}";
    final dateStr = DateFormat.yMMMd().format(item.createdAt);

    IconData icon = LucideIcons.heart;
    Color iconColor = Colors.red.shade400;
    String categoryName = item.category.toUpperCase();

    if (item.category == 'tithe') {
      categoryName = "Tithe Payment";
      icon = LucideIcons.banknote;
      iconColor = Colors.green;
    } else if (item.category == 'giving') {
      categoryName = "Offering";
      icon = LucideIcons.gift;
      iconColor = Colors.purple;
    } else if (item.category == 'top_up') {
      categoryName = "Wallet Top Up";
      icon = LucideIcons.arrowDownLeft;
      iconColor = Colors.teal;
    } else if (item.category == 'transfer') {
      categoryName = "Coins Transfer";
      icon = LucideIcons.send;
      iconColor = Colors.blue;
    } else if (item.category == 'withdrawal') {
      categoryName = "Wallet Withdrawal";
      icon = LucideIcons.arrowUpRight;
      iconColor = Colors.orange;
    }

    return GestureDetector(
      onTap: () => context.push('/receipt/${item.reference}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(categoryName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  if (item.recipientName != null && item.recipientName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: Text(
                        "to ${item.recipientName}",
                        style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  Text(dateStr, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amountText,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: isAdd ? Colors.green : Colors.black87,
                  ),
                ),
                Text(
                  item.status.toUpperCase(),
                  style: TextStyle(
                    color: item.status == 'completed' ? Colors.green : Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
