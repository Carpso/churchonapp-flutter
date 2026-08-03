import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/finance/presentation/buy_coins_screen.dart';
import 'package:church_on_app/features/finance/presentation/partner_redemption_screen.dart';

class PayoutRequestScreen extends ConsumerWidget {
  const PayoutRequestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      data: (profile) => _buildScreen(context, profile),
      loading: () => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ShimmerLoader.rectangular(width: double.infinity, height: 100),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  ShimmerLoader.rectangular(width: 140, height: 100),
                  SizedBox(width: 12),
                  ShimmerLoader.rectangular(width: 140, height: 100),
                ],
              ),
            ],
          ),
        ),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, UserProfile? profile) {
    final balance = profile?.coins ?? 0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Church Coins", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBalanceCard(context, balance),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    context: context,
                    icon: LucideIcons.shoppingCart,
                    title: "Buy Coins",
                    subtitle: "Purchase with\nMobile Money",
                    color: Colors.green,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyCoinsScreen())),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionCard(
                    context: context,
                    icon: LucideIcons.gift,
                    title: "Redeem",
                    subtitle: "Spend coins at\npartner locations",
                    color: Colors.amber,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartnerRedemptionScreen())),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text("How to Earn Coins", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildEarningItem(LucideIcons.calendarCheck, "Daily App Opens", "Open the app every day to build your streak"),
            const SizedBox(height: 10),
            _buildEarningItem(LucideIcons.flame, "Reading Streaks", "Read your Bible daily for bonus coins"),
            const SizedBox(height: 10),
            _buildEarningItem(LucideIcons.userPlus, "Referrals", "Invite friends and earn 100 CC per referral"),
            const SizedBox(height: 10),
            _buildEarningItem(LucideIcons.scanLine, "Attendance", "Scan in at church services"),
            const SizedBox(height: 10),
            _buildEarningItem(LucideIcons.gamepad2, "Bible Quiz", "Participate in Bible quiz games"),
            const SizedBox(height: 24),
            const Text("What You Can Redeem", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildRedemptionOption(
              icon: LucideIcons.bookOpen,
              title: "Partner Bookshops",
              subtitle: "Redeem coins for free books and Bibles at partner bookshops.",
              color: Colors.orange,
            ),
            const SizedBox(height: 10),
            _buildRedemptionOption(
              icon: LucideIcons.coffee,
              title: "Partner Coffee Shops",
              subtitle: "Get free coffee and snacks from partner coffee shops.",
              color: Colors.brown,
            ),
            const SizedBox(height: 10),
            _buildRedemptionOption(
              icon: LucideIcons.trophy,
              title: "Bible Quiz Merch",
              subtitle: "Redeem coins for exclusive Bible Quiz merchandise.",
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            _buildLegalDisclaimer(),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, int balance) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyCoinsScreen())),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(25),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("CHURCH COINS BALANCE", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(LucideIcons.coins, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Text("$balance CC", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text("BUY MORE", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 11), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildEarningItem(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Icon(icon, color: Colors.amber.shade700, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRedemptionOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.info, color: Colors.grey.shade400, size: 14),
              const SizedBox(width: 6),
              Text("About Church Coins", style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Church Coins (CC) are loyalty reward tokens for in-app use only. They have no real-world monetary value and cannot be exchanged for cash, transferred to other users, or refunded. Coins can be earned for free or purchased with real money. Purchases are final and non-refundable.",
            style: TextStyle(color: Colors.grey.shade400, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }
}
