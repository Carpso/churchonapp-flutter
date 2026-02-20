import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/profile_provider.dart';
import 'giving_screen.dart';
import 'transaction_page.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Church Wallet", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: profileAsync.when(
        data: (profile) {
          final coins = profile?.coins ?? 0;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWalletCard(context, coins),
                const SizedBox(height: 30),
                _buildActionButtons(context),
                const SizedBox(height: 40),
                const Text("Recent Transactions", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                _buildTransactionsList(context),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text("Error: $e")),
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
            color: Theme.of(context).primaryColor.withOpacity(0.3),
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
              const Text("TOTAL BALANCE", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              Icon(LucideIcons.wallet, color: Colors.white.withOpacity(0.8), size: 24),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            "K ${coins.toDouble()}",
            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Icon(LucideIcons.shieldCheck, color: Colors.white.withOpacity(0.8), size: 16),
              const SizedBox(width: 5),
              const Text("Encrypted & Secure", style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildActionButton(context, LucideIcons.arrowUpRight, "Top Up", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const TransactionPage(
            title: "Top Up",
            description: "Add funds to your Kingdom wallet using Mobile Money or Cards.",
            icon: LucideIcons.arrowUpRight,
            color: Colors.green,
          )));
        }),
        _buildActionButton(context, LucideIcons.send, "Send", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const TransactionPage(
            title: "Send",
            description: "Transfer church coins to another member safely.",
            icon: LucideIcons.send,
            color: Colors.blue,
          )));
        }),
        _buildActionButton(context, LucideIcons.gift, "Give", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const GivingScreen()));
        }),
        _buildActionButton(context, LucideIcons.arrowDownLeft, "Withdraw", onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const TransactionPage(
            title: "Withdraw",
            description: "Withdraw your coins to your connected bank or mobile money account.",
            icon: LucideIcons.arrowDownLeft,
            color: Colors.red,
          )));
        }),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context, IconData icon, String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
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
    );
  }

  Widget _buildTransactionsList(BuildContext context) {
    // Placeholder transactions for now. In a real scenario, this would be fetched from a repository.
    final transactions = [
      {"title": "Wallet Top Up", "date": "Today, 10:30 AM", "amount": "+K 500.00", "isAdd": true},
      {"title": "Tithe", "date": "Yesterday, 9:00 AM", "amount": "-K 250.00", "isAdd": false},
      {"title": "Bookshop Purchase", "date": "Feb 15, 2:15 PM", "amount": "-K 120.00", "isAdd": false},
      {"title": "Transfer from Bro. John", "date": "Feb 10, 8:45 AM", "amount": "+K 100.00", "isAdd": true},
    ];

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: transactions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 15),
      itemBuilder: (context, index) {
        final t = transactions[index];
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t["isAdd"] == true ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  t["isAdd"] == true ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight,
                  color: t["isAdd"] == true ? Colors.green : Colors.red,
                  size: 20,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t["title"] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(t["date"] as String, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              ),
              Text(
                t["amount"] as String,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: t["isAdd"] == true ? Colors.green : Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
