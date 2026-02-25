import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/profile_provider.dart';
import 'package:church_on_app/features/admin/data/admin_service.dart';

class MultiCurrencyWalletScreen extends ConsumerWidget {
  const MultiCurrencyWalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Multi-Wallet", style: TextStyle(fontWeight: FontWeight.bold)),
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
              "K ${profile?.balanceZmw?.toStringAsFixed(2) ?? '0.00'}", 
              Colors.green, 
              LucideIcons.banknote
            ),
            const SizedBox(height: 20),
            _buildCurrencyTile(
              context, 
              "Kingdom Coins (CC)", 
              "${profile?.balanceCc?.toStringAsFixed(2) ?? '0.00'} CC", 
              Colors.amber, 
              LucideIcons.coins
            ),
            const SizedBox(height: 40),
            const Text(
              "INTERNATIONAL EXPANSION", 
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.grey)
            ),
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
            color: Theme.of(context).primaryColor.withOpacity(0.3), 
            blurRadius: 25, 
            offset: const Offset(0, 10)
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ESTIMATED GLOBAL WEALTH", 
            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)
          ),
          const SizedBox(height: 15),
          const Text(
            "Sovereign Ledger Active", 
            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              _buildSimpleStat("ZMW", "K ${profile?.balanceZmw?.toInt() ?? 0}"),
              const SizedBox(width: 40),
              _buildSimpleStat("CC", "${profile?.balanceCc?.toInt() ?? 0}"),
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
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("ACCOUNT BALANCE", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
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
        border: Border.all(color: Colors.blueAccent.withOpacity(0.1)),
      ),
      child: const Row(
        children: [
          Icon(LucideIcons.globe, color: Colors.blueAccent),
          SizedBox(width: 15),
          Expanded(
            child: Text(
              "Zambia & Zimbabwe Hubs Active. Upcoming expansion to South Africa & Nigeria.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.secondary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: const Text("CURRENCY EXCHANGE", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 15),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("GENERATE AUDIT PROOF", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

