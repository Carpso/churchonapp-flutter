import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/services/coins_service.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/admin/data/ad_service.dart';
import 'package:church_on_app/core/widgets/coa_payment_sheet.dart';

class AdPaymentSheet extends ConsumerStatefulWidget {
  final String adId;

  const AdPaymentSheet({super.key, required this.adId});

  @override
  ConsumerState<AdPaymentSheet> createState() => _AdPaymentSheetState();
}

class _AdPaymentSheetState extends ConsumerState<AdPaymentSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.only(
        left: 25,
        right: 25,
        top: 30,
        bottom: MediaQuery.of(context).viewInsets.bottom + 40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Promote This Ad",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "Pay with Church Coins or Mobile Money.",
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildPackage(context, "Starter", "1 week", "100 CC", "K50", () => _payWithCoins(100), () => _payWithMobileMoney(50)),
                const Divider(height: 20),
                _buildPackage(context, "Standard", "1 month", "350 CC", "K150", () => _payWithCoins(350), () => _payWithMobileMoney(150)),
                const Divider(height: 20),
                _buildPackage(context, "Premium", "3 months", "1000 CC", "K400", () => _payWithCoins(1000), () => _payWithMobileMoney(400)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _payWithCoins(100),
              icon: const Icon(LucideIcons.coins, color: Colors.white),
              label: const Text(
                "Pay with Church Coins",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _payWithMobileMoney(50),
              icon: const Icon(LucideIcons.smartphone, color: Colors.white),
              label: const Text(
                "Pay with Mobile Money",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackage(
    BuildContext context,
    String name,
    String duration,
    String coinPrice,
    String momoPrice,
    VoidCallback onPayWithCoins,
    VoidCallback onPayWithMobile,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(duration, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            GestureDetector(
              onTap: onPayWithCoins,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(coinPrice, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800, fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onPayWithMobile,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(momoPrice, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _payWithCoins(int coinAmount) async {
    try {
      final coinsService = ref.read(coinsServiceProvider);
      final balance = await coinsService.getCoins();
      if (balance < coinAmount) {
        if (!mounted) return;
        PremiumToast.showError(context, "Insufficient coins. You need $coinAmount CC but have $balance CC.");
        return;
      }
      final client = ref.read(supabaseServiceProvider).client;
      final user = client.auth.currentUser;
      if (user == null) throw Exception("Not authenticated");
      await client.rpc('add_coins', params: {
        'user_id': user.id,
        'amount': -coinAmount,
      });
      await ref.read(adServiceProvider).promoteAd(widget.adId, 'coins', coinAmount);
      if (!mounted) return;
      Navigator.pop(context);
      PremiumToast.showSuccess(context, "Ad promoted with $coinAmount Church Coins!");
    } catch (e) {
      if (!mounted) return;
      PremiumToast.showError(context, "Payment failed: $e");
    }
  }

  void _payWithMobileMoney(double amountZmw) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CoaPaymentSheet(
        serviceType: 'ad_promotion',
        amount: amountZmw,
        serviceLabel: "Ad Promotion",
        description: "Pay K$amountZmw directly to Church On App to promote your ad.",
        onComplete: (paymentId, paymentRef) async {
          try {
            await ref.read(adServiceProvider).promoteWithMobileMoney(widget.adId, amountZmw, paymentRef);
            ref.invalidate(activeAdsProvider(null));
            if (!ctx.mounted) return;
            PremiumToast.showSuccess(ctx, "Ad promoted successfully via Mobile Money!");
          } catch (e) {
            if (!ctx.mounted) return;
            PremiumToast.showError(ctx, "Failed to promote ad: $e");
          }
        },
      ),
    );
  }
}
