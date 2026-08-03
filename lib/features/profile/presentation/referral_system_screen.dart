import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import '../data/referral_service.dart';

class ReferralSystemScreen extends ConsumerWidget {
  const ReferralSystemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referralCodeAsync = ref.watch(referralCodeProvider);
    final statsAsync = ref.watch(referralStatsProvider);
    final historyAsync = ref.watch(referralHistoryProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
              loading: () => const ShimmerLoader.rectangular(height: 120),
              error: (_, __) => const Text("Error loading referral code", style: TextStyle(color: Colors.red)),
            ),
            const SizedBox(height: 30),
            statsAsync.when(
              data: (stats) => _buildStatsCard(stats),
              loading: () => const ShimmerLoader.rectangular(height: 100),
              error: (_, __) => _buildStatsCard(ReferralStats.empty()),
            ),
            const SizedBox(height: 30),
            historyAsync.when(
              data: (history) => _buildHistorySection(history),
              loading: () => const ListSkeleton(count: 2),
              error: (_, __) => const SizedBox.shrink(),
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
          _buildStatRow("Invited Members", stats.invited.toString(), LucideIcons.users),
          const Divider(),
          _buildStatRow("Verified & Earned", stats.verified.toString(), LucideIcons.checkCircle, color: Colors.green),
          const Divider(),
          _buildStatRow("Pending Verification", stats.pendingVerification.toString(), LucideIcons.clock, color: Colors.orange),
          const Divider(),
          _buildStatRow("Total Coins Earned", "${stats.totalCoinsEarned} CC", LucideIcons.coins, color: const Color(0xFFFFD700)),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String val, IconData icon, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          Text(val, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
        ],
      ),
    );
  }

  Widget _buildHistorySection(List<ReferralRecord> history) {
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
          const Text("REFERRAL HISTORY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          if (history.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(LucideIcons.userPlus, size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text("No referrals yet", style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text("Share your code to earn 100 CC per referral!", style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  ],
                ),
              ),
            )
          else
            ...history.map((record) => _buildHistoryItem(record)),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(ReferralRecord record) {
    final isVerified = record.status == 'completed';
    final displayName = record.refereeName ?? record.refereeEmail ?? 'Unknown';
    final dateStr = DateFormat('MMM d, yyyy').format(record.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isVerified ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isVerified ? Colors.green.shade100 : Colors.orange.shade100,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: isVerified ? Colors.green.shade100 : Colors.orange.shade100,
            child: Text(
              displayName.substring(0, 1).toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isVerified ? Colors.green.shade700 : Colors.orange.shade700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(dateStr, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isVerified ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isVerified ? "VERIFIED" : "PENDING",
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              if (isVerified)
                const Text("+100 CC", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))
              else
                Text("Awaiting join", style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}
