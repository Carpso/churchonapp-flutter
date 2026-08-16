import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/platform_settings_service.dart';
import 'package:church_on_app/core/config/env.dart';
import 'package:church_on_app/core/config/remote_config.dart';
import 'package:church_on_app/features/finance/data/coin_purchase_service.dart';
import 'package:church_on_app/features/finance/presentation/lipila_payment_gateway.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';

class BuyCoinsScreen extends ConsumerStatefulWidget {
  const BuyCoinsScreen({super.key});

  @override
  ConsumerState<BuyCoinsScreen> createState() => _BuyCoinsScreenState();
}

class _BuyCoinsScreenState extends ConsumerState<BuyCoinsScreen> {
  CoinPackage? _selectedPackage;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      data: (profile) => _buildScreen(context, profile),
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(child: Text('Error: $e', style: TextStyle(color: Colors.white))),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, UserProfile? profile) {
    final currentCoins = profile?.coins ?? 0;
    final packages = CoinPurchaseService.packagesFrom(widgetRemoteConfig(ref));

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Buy Church Coins", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBalanceCard(currentCoins),
            const SizedBox(height: 24),
            const Text("Choose a Package", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              "Buy coins with Mobile Money or Card. Non-refundable.",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
            ),
            const SizedBox(height: 16),
            ...packages.map((pkg) => _buildPackageCard(pkg)),
            const SizedBox(height: 24),
            if (_selectedPackage != null) ...[
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _proceedToPayment(_selectedPackage!),
                  icon: const Icon(LucideIcons.creditCard, color: Colors.black),
                  label: Text(
                    "Pay K${_selectedPackage!.priceKwacha} for ${_selectedPackage!.coins} CC",
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _buildLegalDisclaimer(),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(int balance) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("YOUR BALANCE", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(LucideIcons.coins, color: Colors.white, size: 28),
              const SizedBox(width: 10),
              Text("$balance CC", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "1 CC ≈ K0.10 • Earn free coins daily by opening the app",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(CoinPackage pkg) {
    final isSelected = _selectedPackage == pkg;
    return GestureDetector(
      onTap: () => setState(() => _selectedPackage = pkg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.withValues(alpha: 0.15) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.white12,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(LucideIcons.coins, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(pkg.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      if (pkg.bonus != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(pkg.bonus!, style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${pkg.coins} CC • K${pkg.priceKwacha} • K${pkg.pricePerCoin.toStringAsFixed(2)}/coin",
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              "K${pkg.priceKwacha}",
              style: const TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? LucideIcons.checkCircle2 : LucideIcons.circle,
              color: isSelected ? Colors.amber : Colors.white24,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegalDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.info, color: Colors.white.withValues(alpha: 0.4), size: 14),
              const SizedBox(width: 6),
              Text("Terms & Legal", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Church Coins (CC) are loyalty reward tokens for in-app use only. They have no real-world monetary value and cannot be exchanged for cash, transferred to other users, or refunded. Coins can be earned for free through daily app activity or purchased with real money. Coin purchases are final and non-refundable. COA reserves the right to modify the coin system at any time. By purchasing, you agree to these terms.",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  void _proceedToPayment(CoinPackage pkg) {
    final settingsAsync = ref.read(platformSettingsProvider);
    final settings = settingsAsync.value;
    final recipientAccount = settings?.coaMoMoNumber ?? Env.coaMoMoNumber;
    final recipientName = settings?.coaMoMoName ?? Env.coaMoMoName;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => LipilaPaymentGateway(
        amount: pkg.priceKwacha.toDouble(),
        description: "Church Coins: ${pkg.label} (${pkg.coins} CC)",
        recipientName: recipientName,
        recipientAccount: recipientAccount,
        onComplete: (success, txId) async {
          Navigator.pop(sheetCtx);
          if (success && txId != null) {
            final service = ref.read(coinPurchaseServiceProvider);
            final result = await service.purchaseCoins(
              package: pkg,
              paymentRef: txId,
              paymentMethod: 'mobile_money',
            );
            if (mounted) {
              if (result.success) {
                ref.invalidate(profileProvider);
                PremiumToast.showSuccess(context, "${pkg.coins} Church Coins added to your balance!");
                Navigator.pop(context);
              } else {
                PremiumToast.showError(context, "Payment succeeded but coins failed to credit: ${result.error}");
              }
            }
          }
        },
      ),
    );
  }
}
