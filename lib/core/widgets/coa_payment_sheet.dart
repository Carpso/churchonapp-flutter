import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/config/env.dart';
import 'package:church_on_app/core/services/coa_payment_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/give/presentation/lipila_payment_gateway.dart';

class CoaPaymentSheet extends ConsumerStatefulWidget {
  final String serviceType;
  final double amount;
  final String serviceLabel;
  final String description;
  final Function(String? paymentId, String paymentRef) onComplete;

  const CoaPaymentSheet({
    super.key,
    required this.serviceType,
    required this.amount,
    required this.serviceLabel,
    this.description = '',
    required this.onComplete,
  });

  @override
  ConsumerState<CoaPaymentSheet> createState() => _CoaPaymentSheetState();
}

class _CoaPaymentSheetState extends ConsumerState<CoaPaymentSheet> {
  @override
  Widget build(BuildContext context) {
    return LipilaPaymentGateway(
      amount: widget.amount,
      description: widget.description.isNotEmpty ? widget.description : widget.serviceLabel,
      category: widget.serviceType,
      recipientName: Env.coaMoMoName,
      recipientAccount: Env.coaMoMoNumber,
      paymentReason: widget.serviceLabel,
      onComplete: (success, transactionId) async {
        if (success && transactionId != null) {
          try {
            final svc = ref.read(coaPaymentServiceProvider);
            final paymentId = await svc.submitPayment(
              serviceType: widget.serviceType,
              amount: widget.amount,
              paymentRef: transactionId,
            );
            widget.onComplete(paymentId, transactionId);
          } catch (e) {
            if (context.mounted) PremiumToast.showError(context, 'Payment logged but service activation pending: $e');
            widget.onComplete(null, transactionId);
          }
        }
      },
    );
  }
}
