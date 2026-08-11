import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../../core/widgets/error_retry_widget.dart';

class MultiCurrencyWalletScreen extends ConsumerWidget {
  const MultiCurrencyWalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      data: (profile) => _buildScreen(context, profile, ref),
      loading: () => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: ListSkeleton(count: 4),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: ErrorRetryWidget(
          message: "Failed to load profile",
          onRetry: () => ref.invalidate(profileProvider),
        ),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, UserProfile? profile, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Multi-Wallet", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            _buildGlobalBalanceCard(context, profile),
            const SizedBox(height: 30),
            _buildCurrencyTile(
              context, 
              "Zambian Kwacha", 
              "K ${profile?.balanceZmw.toStringAsFixed(2) ?? '0.00'}", 
              Colors.green, 
              LucideIcons.banknote
            ),
            const SizedBox(height: 20),
            _buildCurrencyTile(
              context, 
              "Coins (CC)", 
              "${profile?.balanceCc.toStringAsFixed(2) ?? '0.00'} CC", 
              Colors.amber, 
              LucideIcons.coins
            ),
            const SizedBox(height: 40),
            const Text(
              "INTERNATIONAL EXPANSION", 
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.grey)
            ),
            const SizedBox(height: 20),
            _buildFxRateCard(context, ref),
            const SizedBox(height: 20),
            _buildExpansionHub(context),
            const SizedBox(height: 40),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalBalanceCard(BuildContext context, UserProfile? profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(35),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Theme.of(context).primaryColor, const Color(0xFF6D28D9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.3), 
            blurRadius: 25, 
            offset: const Offset(0, 10)
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "CHURCH COINS BALANCE", 
            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)
          ),
          const SizedBox(height: 15),
          Text(
            "K ${profile?.balanceZmw.toInt() ?? 0}",
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              _buildSimpleStat("ZMW", "K ${profile?.balanceZmw.toInt() ?? 0}"),
              const SizedBox(width: 40),
              _buildSimpleStat("CC", "${profile?.balanceCc.toInt() ?? 0}"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildCurrencyTile(BuildContext context, String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("ACCOUNT BALANCE", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildExpansionHub(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.1)),
      ),
      child: const Row(
        children: [
          Icon(LucideIcons.globe, color: Colors.blueAccent),
          SizedBox(width: 15),
          Expanded(
            child: Text(
              "Church On App is currently available in Zambia. More regions coming soon.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFxRateCard(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.arrowLeftRight, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Text(
              "Live USD Exchange Rate",
              style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          ref.watch(zmwPerUsdProvider).when(
            data: (rate) => Text(
              "1 USD = K${rate.toStringAsFixed(2)}",
              style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w900),
            ),
            loading: () => const Text("Loading…", style: TextStyle(color: Colors.grey, fontSize: 12)),
            error: (_, __) => const Text("Rate unavailable", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return const SizedBox.shrink();
  }
}

