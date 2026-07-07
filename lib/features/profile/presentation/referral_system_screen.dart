import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import '../data/referral_service.dart';

class ReferralSystemScreen extends ConsumerWidget {
  const ReferralSystemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referralCodeAsync = ref.watch(referralCodeProvider);
    final statsAsync = ref.watch(referralStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Referral Program", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            _buildGiftCard(),
            const SizedBox(height: 30),
            referralCodeAsync.when(
              data: (code) => _buildCodeCard(context, code),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text("Error loading referral code", style: TextStyle(color: Colors.red)),
            ),
            const SizedBox(height: 30),
            statsAsync.when(
              data: (stats) => _buildStatsCard(stats),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _buildStatsCard(ReferralStats.empty()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGiftCard() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1E293B)]),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Row(
        children: [
          Icon(LucideIcons.gift, color: Colors.amber, size: 50),
          SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Invite & Grow together", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                Text("Get +100 Loyalty Coins for every new church member that completes registration!", style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(BuildContext context, String referralCode) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        children: [
          const Text("YOUR REFERRAL CODE", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(referralCode, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
                IconButton(
                  icon: const Icon(LucideIcons.copy, color: Colors.grey),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: referralCode));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code copied to clipboard!"), backgroundColor: Colors.teal));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          ElevatedButton.icon(
            onPressed: () {
              SharePlus.instance.share(ShareParams(text: "Join me on Church On App using my referral code: $referralCode and get 100 free Loyalty Coins! Download at: https://churchonapp.com/join?ref=$referralCode"));
            },
            icon: const Icon(LucideIcons.share2),
            label: const Text("SHARE INVITE LINK"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatsCard(ReferralStats stats) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("YOUR REFERRAL STATS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          _buildStatRow("Invited Members", stats.invited.toString()),
          const Divider(),
          _buildStatRow("Pending Verification", stats.pendingVerification.toString()),
          const Divider(),
          _buildStatRow("Coins Earned", "${stats.coinsEarned} Coins"),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}
