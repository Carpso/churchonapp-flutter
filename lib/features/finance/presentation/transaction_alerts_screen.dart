import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import '../data/finance_service.dart';

final tenantAlertsProvider = StreamProvider.autoDispose<List<Transaction>>((ref) {
  final tenant = ref.watch(currentTenantProvider);
  final tenantId = tenant?.id;
  if (tenantId == null) return const Stream.empty();
  final financeService = ref.watch(financeServiceProvider);
  return financeService.getTenantLedgerStream(tenantId);
});

class TransactionAlertsScreen extends ConsumerWidget {
  const TransactionAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(tenantAlertsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Transaction Alerts"),
        centerTitle: true,
      ),
      body: alerts.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (e, _) => Center(child: Text("Failed to load transactions: $e")),
        data: (transactions) {
          if (transactions.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.inbox, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text("No transactions yet", style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(tenantAlertsProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
            itemCount: transactions.length,
            itemBuilder: (context, index) => _TransactionAlertCard(transaction: transactions[index]),
          ),
          );
        },
      ),
    );
  }
}

class _TransactionAlertCard extends ConsumerWidget {
  final Transaction transaction;
  const _TransactionAlertCard({required this.transaction});

  void _showDetailSheet(BuildContext context) {
    final isCompleted = transaction.status == 'completed';
    final isPending = transaction.status == 'pending';
    final Color statusColor;
    if (isCompleted) {
      statusColor = Colors.green;
    } else if (isPending) {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.red;
    }
    final categoryLabel = transaction.category.toUpperCase();
    final time = DateFormat('dd MMM yyyy HH:mm').format(transaction.createdAt);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      backgroundColor: Colors.white,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                  child: Icon(isCompleted ? LucideIcons.checkCircle : isPending ? LucideIcons.clock : LucideIcons.xCircle, color: statusColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("K ${transaction.amount.toStringAsFixed(2)}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: statusColor)),
                      const SizedBox(height: 2),
                      Text(transaction.recipientName ?? "Member", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _detailRow("Status", transaction.status.toUpperCase(), statusColor),
            _detailRow("Category", categoryLabel, Colors.grey.shade700),
            _detailRow("Reference", transaction.reference, Colors.grey.shade700),
            _detailRow("Date", time, Colors.grey.shade700),
            if (transaction.recipientPhone != null) _detailRow("Phone", transaction.recipientPhone!, Colors.grey.shade700),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/receipt/${transaction.reference}');
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: const Text("VIEW RECEIPT", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          Flexible(child: Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: valueColor), textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCompleted = transaction.status == 'completed';
    final isPending = transaction.status == 'pending';

    final Color statusColor;
    final IconData statusIcon;
    if (isCompleted) {
      statusColor = Colors.green;
      statusIcon = LucideIcons.checkCircle;
    } else if (isPending) {
      statusColor = Colors.orange;
      statusIcon = LucideIcons.clock;
    } else {
      statusColor = Colors.red;
      statusIcon = LucideIcons.xCircle;
    }

    final categoryLabel = transaction.category.toUpperCase();
    final time = DateFormat('dd MMM yyyy HH:mm').format(transaction.createdAt);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetailSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(statusIcon, color: statusColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(categoryLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        Text(transaction.recipientName ?? "Member",
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(time, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("K ${transaction.amount.toStringAsFixed(2)}",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isCompleted ? Colors.green.shade700 : statusColor)),
                  const SizedBox(height: 2),
                  Text(transaction.reference.length > 12
                      ? '...${transaction.reference.substring(transaction.reference.length - 8)}'
                      : transaction.reference,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
