import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/give/presentation/lipila_payment_gateway.dart';

/// Landing screen for scanned QR deep links:
///   `churchonapp://pay?ref=...&amount=...&recipient=...`
///   `https://churchonapp.com/pay?ref=...&amount=...&recipient=...`
///
/// Runs the REAL Lipila gateway against the QR's own `ref`, so the
/// server-side `coa_payments` anchor matches the QR reference instead of the
/// old fake "I HAVE PAID" ledger write with no money behind it.
class PayByQrScreen extends ConsumerStatefulWidget {
  final String? reference;
  final String? amount;
  final String? recipient;
  final String? description;

  const PayByQrScreen({
    super.key,
    this.reference,
    this.amount,
    this.recipient,
    this.description,
  });

  @override
  ConsumerState<PayByQrScreen> createState() => _PayByQrScreenState();
}

class _PayByQrScreenState extends ConsumerState<PayByQrScreen> {
  bool _paid = false;

  double get _amount => double.tryParse(widget.amount ?? '') ?? 0;
  bool get _isValid =>
      (widget.reference ?? '').isNotEmpty &&
      _amount > 0 &&
      (widget.recipient ?? '').isNotEmpty;

  Future<void> _pay() async {
    if (!_isValid) return;
    final tenant = ref.read(currentTenantProvider);
    final refCode = widget.reference!;
    final description = (widget.description ?? '').isEmpty
        ? 'QR Payment'
        : widget.description!;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LipilaPaymentGateway(
        amount: _amount,
        description: description,
        category: 'giving',
        reference: refCode,
        recipientName: widget.recipient,
        paymentReason: description,
        onComplete: (success, txId) {
          Navigator.pop(ctx, success && txId != null ? txId : null);
        },
      ),
    );

    if (result == null || !mounted) return; // cancelled
    try {
      await ref.read(financeServiceProvider).logTransaction(
            _amount,
            'qr_payment',
            result,
            tenantId: tenant?.id,
            recipientName: widget.recipient,
          );
      if (mounted) setState(() => _paid = true);
    } catch (e) {
      if (mounted) {
        PremiumToast.showError(context, "Payment recorded but history write failed: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_isValid) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan to Pay')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.qrCode, size: 64, color: Colors.grey),
                const SizedBox(height: 20),
                const Text(
                  'This payment link is incomplete',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ask the church to generate a fresh QR code and scan it again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.hintColor),
                ),
                const SizedBox(height: 25),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('BACK TO HOME'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_paid) {
      return Scaffold(
        appBar: AppBar(title: const Text('Payment')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.checkCircle,
                    size: 72, color: Colors.green),
                const SizedBox(height: 20),
                const Text(
                  'Payment Sent!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'K${_amount.toStringAsFixed(2)} to ${widget.recipient}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.hintColor),
                ),
                const SizedBox(height: 8),
                Text(
                  'REF: ${widget.reference}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey),
                ),
                const SizedBox(height: 30),
                FilledButton(
                  onPressed: () => context.go('/'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56)),
                  child: const Text('DONE'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan to Pay')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15)),
              ),
              child: Column(
                children: [
                  const Text('AMOUNT DUE',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text(
                    'K${_amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 44, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(widget.recipient!,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pay,
              icon: const Icon(LucideIcons.smartphone),
              label: const Text('PAY NOW',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'You will receive a Mobile Money PIN prompt (or card checkout) on the next step. Reference: ${widget.reference}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}
