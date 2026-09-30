import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/platform_settings_service.dart';
import 'package:church_on_app/core/config/env.dart';
import 'package:church_on_app/features/give/presentation/lipila_payment_gateway.dart';

class CoaPaymentSheet extends ConsumerStatefulWidget {
  final String serviceType;
  final double amount;
  final String serviceLabel;
  final String description;
  final bool startWithCard;
  final Function(String? paymentId, String paymentRef) onComplete;

  const CoaPaymentSheet({
    super.key,
    required this.serviceType,
    required this.amount,
    required this.serviceLabel,
    this.description = '',
    this.startWithCard = false,
    required this.onComplete,
  });

  @override
  ConsumerState<CoaPaymentSheet> createState() => _CoaPaymentSheetState();
}

class _CoaPaymentSheetState extends ConsumerState<CoaPaymentSheet> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(platformSettingsProvider).value;
    final momoName = (settings?.coaMoMoName.isNotEmpty ?? false) ? settings!.coaMoMoName : Env.coaMoMoName;
    final momoNumber = (settings?.coaMoMoNumber.isNotEmpty ?? false) ? settings!.coaMoMoNumber : Env.coaMoMoNumber;
    return LipilaPaymentGateway(
      amount: widget.amount,
      description: widget.description.isNotEmpty ? widget.description : widget.serviceLabel,
      category: widget.serviceType,
      recipientName: momoName,
      recipientAccount: momoNumber,
      paymentReason: widget.serviceLabel,
      startWithCard: widget.startWithCard,
      // The sheet — not the verification listener — decides when this flow is
      // over: the user sees the success overlay, taps CONTINUE, then we pop
      // with the reference so awaiting callers (showModalBottomSheet<String>)
      // finally receive it. Never insert a coa_payments row from here:
      // lipila-collect already upserts the pending anchor server-side
      // (client-side submitPayment only produced 23505 conflicts).
      autoCompleteOnSuccess: false,
      onComplete: (success, transactionId) async {
        if (!success || transactionId == null) return;
        if (context.mounted) Navigator.pop(context, transactionId);
        try {
          await widget.onComplete(null, transactionId);
        } catch (e) {
          debugPrint('CoaPaymentSheet: completion handler failed: $e');
        }
      },
    );
  }
}
