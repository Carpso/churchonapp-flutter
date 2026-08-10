import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/coins_service.dart';
import '../../../core/widgets/error_retry_widget.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../../core/utils/money.dart';
import '../../connect/data/user_activity_service.dart';
import '../data/finance_service.dart';
import 'transaction_page.dart';
import 'payout_request_screen.dart';
import 'lipila_payment_gateway.dart';
import 'widgets/giving_widget.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  void _showTopUpSheet(BuildContext context, WidgetRef actionRef) {
    final amountCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: EdgeInsets.only(
            left: 25,
            right: 25,
            top: 30,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Top Up Wallet',
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (K)',
                hintText: 'Enter amount to add',
                prefixIcon: Icon(LucideIcons.banknote, size: 20),
              ),
            ),
            const SizedBox(height: 30),
            FilledButton(
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text);
                if (amt == null || amt <= 0) return;
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (sheetCtx) => LipilaPaymentGateway(
                    amount: amt,
                    description: 'Wallet Top Up',
                    category: 'top_up',
                    onComplete: (success, txId) async {
                      Navigator.pop(sheetCtx);
                      if (success && context.mounted) {
                        actionRef.invalidate(profileProvider);
                      }
                    },
                  ),
                );
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
              child: const Text('PROCEED TO PAYMENT'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Church Wallet", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: profileAsync.when(
        data: (profile) {
          final coins = profile?.coins ?? 0;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(transactionsStreamProvider);
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                _buildWalletCard(context, coins),
                const SizedBox(height: 30),
        _buildActionButtons(context, ref),
        const SizedBox(height: 40),
                const Text("Recent Transactions", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                 _buildTransactionsList(context, transactionsAsync, ref),
              ],
            ),
          ),
          );
        },
        loading: () => const ListSkeleton(count: 3),
        error: (e, s) => ErrorRetryWidget(
          message: "Failed to load wallet",
          onRetry: () => ref.invalidate(profileProvider),
        ),
      ),
    );
  }

  Widget _buildWalletCard(BuildContext context, num coins) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL BALANCE", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              Icon(LucideIcons.wallet, color: Colors.white.withValues(alpha: 0.8), size: 24),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            formatKwacha(coins.toDouble()),
            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Icon(LucideIcons.shieldCheck, color: Colors.white.withValues(alpha: 0.8), size: 16),
              const SizedBox(width: 5),
              const Text("Encrypted & Secure", style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef actionRef) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildActionButton(context, LucideIcons.arrowUpRight, "Top Up", onTap: () => _showTopUpSheet(context, actionRef)),
        _buildActionButton(context, LucideIcons.send, "Send", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const TransactionPage(
            title: "Send",
            description: "Transfer church coins to another member safely.",
            icon: LucideIcons.send,
            color: Colors.blue,
          )));
        }),
        _buildActionButton(context, LucideIcons.gift, "Give", onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const GivingWidget(),
          );
        }),
        _buildActionButton(context, LucideIcons.arrowDownLeft, "Withdraw", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const PayoutRequestScreen()));
        }),
        _buildDailyCollectButton(context),
      ],
    );
  }

  Widget _buildDailyCollectButton(BuildContext context) {
    return Consumer(builder: (context, ref, child) {
      final canCollectAsync = ref.watch(canCollectDailyProvider);
      return canCollectAsync.when(
        data: (canCollect) => _buildCollectButton(context, canCollect, ref),
        loading: () => const SizedBox.shrink(),
        error: (e, st) => const SizedBox.shrink(),
      );
    });
  }

  Widget _buildCollectButton(BuildContext context, bool canCollect, WidgetRef ref) {
    return GestureDetector(
        onTap: () async {
          if (!canCollect) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Already collected today!"), backgroundColor: Colors.orange));
            }
            return;
          }
          final service = ref.read(coinsServiceProvider);
          final activity = ref.read(userActivityServiceProvider);
          final earned = await service.collectDailyCoins();
          if (earned > 0) {
            await activity.logActivity(type: ActivityType.coinCollected, description: "Daily coin reward", coinsEarned: earned);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("+$earned coins collected!"), backgroundColor: Colors.green));
            }
          }
        },
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: canCollect ? Colors.amber : Colors.grey.shade300,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (canCollect ? Colors.amber : Colors.grey).withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                canCollect ? LucideIcons.coins : LucideIcons.checkCircle,
                color: canCollect ? Colors.black : Colors.grey,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              canCollect ? "Daily" : "Done",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: canCollect ? Colors.amber.shade800 : Colors.grey),
            ),
          ],
        ),
      );
  }

  Widget _buildActionButton(BuildContext context, IconData icon, String label, {required VoidCallback onTap}) {
    return Semantics(
      label: "$label button",
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.secondary, size: 24),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList(BuildContext context, AsyncValue<List<Transaction>> transactionsAsync, WidgetRef ref) {
    return transactionsAsync.when(
      data: (transactions) {
        if (transactions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 30.0),
              child: Text("No transactions found",
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5))),
            ),
          );
        }
        return ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: transactions.length,
          separatorBuilder: (context, index) => const SizedBox(height: 15),
          itemBuilder: (context, index) {
            final t = transactions[index];
            final isAdd = t.category == 'top_up' || t.amount > 0;
            final amountText = "${isAdd ? '+' : ''}${formatKwacha(t.amount)}";
            
            // Format date
            final dateStr = "${t.createdAt.day}/${t.createdAt.month}/${t.createdAt.year}";

            // Map category to a friendly name and icon
            String title = t.category;
            IconData icon = LucideIcons.arrowUpRight;
            Color iconColor = Colors.green;

            if (t.category == 'tithe') {
              title = "Tithe Payment";
              icon = LucideIcons.heart;
              iconColor = Colors.red;
            } else if (t.category == 'giving') {
              title = "Offering";
              icon = LucideIcons.gift;
              iconColor = Colors.purple;
            } else if (t.category == 'top_up') {
              title = "Wallet Top Up";
              icon = LucideIcons.arrowDownLeft;
              iconColor = Colors.green;
            } else if (t.category == 'transfer') {
              title = "Coins Transfer";
              icon = LucideIcons.send;
              iconColor = Colors.blue;
            } else if (t.category == 'withdrawal') {
              title = "Wallet Withdrawal";
              icon = LucideIcons.arrowUpRight;
              iconColor = Colors.orange;
            }

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: iconColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(dateStr, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(
                    amountText,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: isAdd ? Colors.green : Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => ErrorRetryWidget(
        message: "Failed to load transactions",
        onRetry: () => ref.invalidate(transactionsStreamProvider),
      ),
    );
  }
}

