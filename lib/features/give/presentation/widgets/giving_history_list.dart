import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/widgets/shimmer_loader.dart';

class GiveTransaction {
  final String id;
  final String userId;
  final double amount;
  final String category;
  final String status;
  final String reference;
  final String? tenantId;
  final DateTime createdAt;
  final String? recipientName;
  final String? recipientPhone;

  GiveTransaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.category,
    required this.status,
    required this.reference,
    this.tenantId,
    required this.createdAt,
    this.recipientName,
    this.recipientPhone,
  });

  factory GiveTransaction.fromMap(Map<String, dynamic> map) {
    return GiveTransaction(
      id: map['id']?.toString() ?? '',
      userId: map['user_id'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      category: map['category'] ?? 'offering',
      status: map['status'] ?? 'pending',
      reference: map['reference'] ?? '',
      tenantId: map['tenant_id'],
      createdAt: DateTime.parse(
        map['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      recipientName: map['recipient_name'],
      recipientPhone: map['recipient_phone'],
    );
  }
}

final _giveTransactionsProvider = StreamProvider<List<GiveTransaction>>((ref) {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return Stream.value([]);

  return client
      .from('transactions')
      .stream(primaryKey: ['id'])
      .eq('user_id', user.id)
      .order('created_at', ascending: false)
      .map((data) =>
          data.map((map) => GiveTransaction.fromMap(map)).toList());
});

class GivingHistoryList extends ConsumerWidget {
  const GivingHistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(_giveTransactionsProvider);

    return transactionsAsync.when(
      data: (transactions) {
        if (transactions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.only(top: 40.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.heart, size: 48, color: Color(0xFFE2E8F0)),
                  SizedBox(height: 12),
                  Text(
                    "No stewardship records yet.",
                    style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Your giving history will appear here.",
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          itemCount: transactions.length,
          itemBuilder: (context, index) =>
              _buildHistoryItem(context, transactions[index]),
        );
      },
      loading: () => const _GiveHistorySkeleton(),
      error: (err, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertCircle, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text("Error loading history: $err"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, GiveTransaction item) {
    final isAdd = item.category == 'top_up' || item.amount > 0;
    final amountText = "${isAdd ? '+' : '-'}K ${item.amount.toStringAsFixed(2)}";
    final dateStr = DateFormat.yMMMd().format(item.createdAt);

    IconData icon = LucideIcons.heart;
    Color iconColor = Colors.red.shade400;
    String categoryName = item.category.toUpperCase();
    final brand = Theme.of(context).primaryColor;

    if (item.category == 'tithe') {
      categoryName = "Tithe Payment";
      icon = LucideIcons.banknote;
      iconColor = Colors.green;
    } else if (item.category == 'giving') {
      categoryName = "Offering";
      icon = LucideIcons.gift;
      iconColor = brand;
    } else if (item.category == 'top_up') {
      categoryName = "Wallet Top Up";
      icon = LucideIcons.arrowDownLeft;
      iconColor = brand.withValues(alpha: 0.75);
    } else if (item.category == 'transfer') {
      categoryName = "Coins Transfer";
      icon = LucideIcons.send;
      iconColor = brand.withValues(alpha: 0.55);
    } else if (item.category == 'withdrawal') {
      categoryName = "Wallet Withdrawal";
      icon = LucideIcons.arrowUpRight;
      iconColor = Colors.orange;
    } else if (item.category == 'building_fund') {
      categoryName = "Building Fund";
      icon = LucideIcons.construction;
      iconColor = Colors.brown;
    } else if (item.category == 'mission') {
      categoryName = "Mission Support";
      icon = LucideIcons.globe;
      iconColor = brand.withValues(alpha: 0.8);
    }

    return GestureDetector(
      onTap: () => context.push('/receipt/${item.reference}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    categoryName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (item.recipientName != null &&
                      item.recipientName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        "to ${item.recipientName}",
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
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
                    fontSize: 15,
                    color: isAdd ? Colors.green : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: item.status == 'completed'
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.status.toUpperCase(),
                    style: TextStyle(
                      color: item.status == 'completed'
                          ? Colors.green
                          : Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
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

class _GiveHistorySkeleton extends StatelessWidget {
  const _GiveHistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      itemCount: 5,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const ShimmerLoader.circular(width: 40, height: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerLoader.rectangular(
                    width: MediaQuery.of(context).size.width * 0.35,
                    height: 14,
                  ),
                  const SizedBox(height: 6),
                  ShimmerLoader.rectangular(
                    width: MediaQuery.of(context).size.width * 0.25,
                    height: 10,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ShimmerLoader.rectangular(
                  width: MediaQuery.of(context).size.width * 0.15,
                  height: 14,
                ),
                const SizedBox(height: 4),
                ShimmerLoader.rectangular(
                  width: 40,
                  height: 10,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
