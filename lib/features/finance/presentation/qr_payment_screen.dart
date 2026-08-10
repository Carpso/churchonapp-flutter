import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/qr_code_with_logo.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/widgets/premium_confirmation_sheet.dart';
import 'package:church_on_app/core/services/code_generator_service.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class QrPaymentScreen extends ConsumerWidget {
  final double amount;
  final String description;
  final String recipient;

  const QrPaymentScreen({
    super.key,
    required this.amount,
    required this.description,
    required this.recipient,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codeGen = ref.read(codeGeneratorProvider);
    final refCodeAsync = FutureProvider<String>((ref) => codeGen.generatePaymentRef());
    final refCodeValue = ref.watch(refCodeAsync);

    return refCodeValue.when(
      data: (refCode) {
        final qrData = 'churchonapp://pay?ref=$refCode&amount=${amount.toStringAsFixed(2)}&recipient=${Uri.encodeComponent(recipient)}';

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text("PAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildQrCard(context, qrData, refCode),
                  const SizedBox(height: 40),
                  _buildPaymentDetails(),
                  const SizedBox(height: 50),
                  _buildActionButtons(context, ref, refCode),
                  const SizedBox(height: 20),
                  const Text(
                    "Scan this QR at any Hub or with your Banking App to settle the transaction via our sovereign ledger.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(child: Text("Error: $e", style: TextStyle(color: Colors.red))),
      ),
    );
  }

  Widget _buildQrCard(BuildContext context, String qrData, String refCode) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 40, spreadRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.landmark, color: Theme.of(context).primaryColor, size: 20),
              const SizedBox(width: 10),
              Text(
                "VERIFIED HUB PAYMENT",
                style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 30),
          QrCodeWithLogo(
            data: qrData,
            size: 220,
            logoSize: 44,
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
            child: Text(
              "REF: $refCode",
              style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetails() {
    return Column(
      children: [
        Text(
          "K ${amount.toStringAsFixed(2)}",
          style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          description.toUpperCase(),
          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
        ),
        const SizedBox(height: 20),
        Text(
          "Recipient: $recipient",
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref, String refCode) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () async {
            final tenant = ref.read(currentTenantProvider);
            try {
              await ref.read(financeServiceProvider).logTransaction(
                amount,
                'qr_payment',
                refCode,
                tenantId: tenant?.id,
                recipientName: recipient,
              );
              if (context.mounted) {
                PremiumConfirmationSheet.show(
                  context: context,
                  title: "Payment Recorded!",
                  message: "Your payment of K${amount.toStringAsFixed(2)} to $recipient has been recorded in the sovereign ledger.",
                  referenceId: refCode,
                  type: ConfirmationType.success,
                  primaryLabel: "DONE",
                  onPrimary: () => Navigator.pop(context),
                );
              }
            } catch (e) {
              if (context.mounted) {
                PremiumToast.showError(context, "Payment failed: ${e.toString().replaceFirst("Exception: ", "")}");
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: const Text("I HAVE PAID", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 15),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CANCEL TRANSACTION", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
