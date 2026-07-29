import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/platform_settings_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/give/presentation/lipila_payment_gateway.dart';

class HomeSubscriptionPaywall extends ConsumerStatefulWidget {
  final Tenant tenant;
  const HomeSubscriptionPaywall({super.key, required this.tenant});

  @override
  ConsumerState<HomeSubscriptionPaywall> createState() => _HomeSubscriptionPaywallState();
}

class _HomeSubscriptionPaywallState extends ConsumerState<HomeSubscriptionPaywall> {
  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    final hasSubmitted = tenant.paymentReference != null && tenant.paymentReference!.isNotEmpty;
    final settingsAsync = ref.watch(platformSettingsProvider);
    final churchFee = settingsAsync.maybeWhen(data: (s) => s.churchFee, orElse: () => 1500.0);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.shade50.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.red.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: Colors.red.shade700, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(hasSubmitted ? "Payment Under Review" : "Subscription Required", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            hasSubmitted
                ? "Your payment reference (${tenant.paymentReference}) is currently being reviewed by the Superadmin. Access to ${tenant.name} will be restored as soon as payment is confirmed."
                : "The 30-day free trial for ${tenant.name} has expired. To reactivate full access for all members, please submit a payment of K${churchFee.toStringAsFixed(2)} ZMW.",
            style: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.5),
          ),
          const SizedBox(height: 20),
          if (!hasSubmitted)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => _paySubscription(churchFee),
                icon: const Icon(LucideIcons.creditCard, color: Colors.white),
                label: const Text("PAY NOW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 3)),
                    const SizedBox(height: 15),
                    Text("Awaiting Superadmin confirmation...", style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => ref.read(currentTenantProvider.notifier).setTenant(null),
              child: const Text("SELECT ANOTHER CHURCH", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  void _paySubscription(double amount) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LipilaPaymentGateway(
        amount: amount,
        description: "Church Subscription Renewal",
        category: 'subscription',
        recipientName: "Church On App Official",
        recipientAccount: "0976847775",
        paymentReason: "Subscription Renewal - ${widget.tenant.name}",
        onComplete: (success, txId) async {
          if (ctx.mounted) Navigator.pop(ctx);
          if (success && txId != null) {
            try {
              await Supabase.instance.client.from('churches').update({
                'payment_reference': txId,
                'payment_submitted_at': DateTime.now().toIso8601String(),
              }).eq('id', widget.tenant.id);
              await ref.read(currentTenantProvider.notifier).loadTenant();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Payment submitted successfully!"), backgroundColor: Colors.green),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Payment recorded but update failed: $e"), backgroundColor: Colors.red),
                );
              }
            }
          }
        },
      ),
    );
  }
}
