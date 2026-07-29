import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'widgets/giving_history_list.dart';

class GivingHistoryScreen extends ConsumerWidget {
  const GivingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Stewardship History"),
      ),
      body: transactionsAsync.when(
        data: (transactions) {
          final currentYear = DateTime.now().year;
          final annualTotal = transactions
              .where((t) => t.createdAt.year == currentYear)
              .fold(0.0, (sum, t) => sum + t.amount);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(transactionsStreamProvider);
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.all(25),
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "ANNUAL CONTRIBUTIONS ($currentYear)",
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "K ${annualTotal.toStringAsFixed(2)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Track your sovereign seeds on the Ledger",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: GivingHistoryList(),
                ),
              ],
            ),
          );
        },
        loading: () => const ListSkeleton(count: 4),
        error: (err, stack) => ErrorRetryWidget(
          message: "Failed to load giving history",
          onRetry: () => ref.invalidate(transactionsStreamProvider),
        ),
      ),
    );
  }
}
