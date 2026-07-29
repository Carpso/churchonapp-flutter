import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/finance/data/payment_state.dart';
import 'package:church_on_app/features/give/presentation/widgets/momo_phone_input_widget.dart';
import 'package:church_on_app/features/give/presentation/widgets/payment_status_overlay.dart';

class LipilaPaymentGateway extends ConsumerStatefulWidget {
  final double amount;
  final String description;
  final String category;
  final String? recipientName;
  final String? recipientAccount;
  final String? paymentReason;
  final Function(bool success, String? transactionId) onComplete;

  const LipilaPaymentGateway({
    super.key,
    required this.amount,
    required this.description,
    this.category = 'giving',
    this.recipientName,
    this.recipientAccount,
    this.paymentReason,
    required this.onComplete,
  });

  @override
  ConsumerState<LipilaPaymentGateway> createState() =>
      _LipilaPaymentGatewayState();
}

class _LipilaPaymentGatewayState extends ConsumerState<LipilaPaymentGateway> {
  String _selectedNetwork = "MTN";
  final _phoneCtrl = TextEditingController();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(profileProvider).value;
      if (profile?.phoneNumber != null && profile!.phoneNumber!.isNotEmpty) {
        _phoneCtrl.text = profile.phoneNumber!;
      }
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _initiatePayment() {
    final phoneError = MomoPhoneInputWidget.validateZambianPhone(_phoneCtrl.text);
    if (phoneError != null) {
      setState(() => _errorMessage = phoneError);
      return;
    }
    setState(() => _errorMessage = null);
    ref.read(lipilaPaymentProvider.notifier).initiatePayment(
          phone: _phoneCtrl.text,
          amount: widget.amount,
          description: widget.description,
          narration: widget.paymentReason,
        );
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final paymentAsync = ref.watch(lipilaPaymentProvider);
    final paymentState = paymentAsync.value ?? const LipilaPaymentState();
    final displayRecipient =
        widget.recipientName ?? tenant?.name ?? "Church On App";
    final displayAccount = widget.recipientAccount ??
        tenant?.treasurerPhone ??
        "Merchant ID: 68907";

    ref.listen<AsyncValue<LipilaPaymentState>>(lipilaPaymentProvider, (prev, next) {
      final data = next.value;
      if (data == null) return;
      if (data.status == PaymentStatus.succeeded) {
        widget.onComplete(true, data.referenceId);
      } else if (data.status == PaymentStatus.cancelled) {
        widget.onComplete(false, null);
      }
    });

    final isProcessing = paymentState.status == PaymentStatus.initiating ||
        paymentState.status == PaymentStatus.awaitingPin;

    return PopScope(
      canPop: !isProcessing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showCancelConfirmationDialog();
      },
      child: Container(
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
                Text(
                  "Secure Settlement",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () {
                    if (isProcessing) {
                      _showCancelConfirmationDialog();
                    } else {
                      ref.read(lipilaPaymentProvider.notifier).reset();
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

          if (paymentState.status == PaymentStatus.succeeded)
            PaymentStatusOverlay(
              status: paymentState.status,
              statusMessage: paymentState.statusMessage,
              amount: widget.amount,
              referenceId: paymentState.referenceId,
              recipientName: displayRecipient,
              onContinue: () {
                ref.read(lipilaPaymentProvider.notifier).reset();
                widget.onComplete(true, paymentState.referenceId);
              },
            )
          else if (paymentState.status == PaymentStatus.failed)
            PaymentStatusOverlay(
              status: paymentState.status,
              statusMessage: paymentState.statusMessage,
              errorMessage: paymentState.errorMessage,
              amount: widget.amount,
              onRetry: () {
                ref.read(lipilaPaymentProvider.notifier).reset();
                _initiatePayment();
              },
            )
          else if (paymentState.status == PaymentStatus.cancelled)
            PaymentStatusOverlay(
              status: paymentState.status,
              statusMessage: paymentState.statusMessage,
              amount: widget.amount,
              onRetry: () {
                ref.read(lipilaPaymentProvider.notifier).reset();
              },
            )
          else if (paymentState.status == PaymentStatus.initiating ||
              paymentState.status == PaymentStatus.awaitingPin)
            PaymentStatusOverlay(
              status: paymentState.status,
              statusMessage: paymentState.statusMessage,
              amount: widget.amount,
              onCancel: () =>
                  ref.read(lipilaPaymentProvider.notifier).cancel(),
            )
          else ...[
            _buildRecipientCard(displayRecipient, displayAccount),
            const SizedBox(height: 30),
            MomoPhoneInputWidget(
              controller: _phoneCtrl,
              selectedNetwork: _selectedNetwork,
              onNetworkChanged: (network) =>
                  setState(() => _selectedNetwork = network),
              error: _errorMessage,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _initiatePayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                minimumSize: const Size(double.infinity, 65),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                "PROCEED TO PIN PROMPT",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Center(
            child: Text(
              "Regulated by Bank of Zambia via Lipila",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildRecipientCard(String displayRecipient, String displayAccount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          _buildInfoRow("Paying To:", displayRecipient, isTitle: true),
          const SizedBox(height: 8),
          _buildInfoRow("Settlement A/C:", displayAccount),
          const SizedBox(height: 8),
          _buildInfoRow("Reference:", widget.paymentReason ?? widget.description),
          const Divider(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Total (Inc. Fees)",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                "K${widget.amount.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isTitle = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: isTitle ? FontWeight.w900 : FontWeight.bold,
              fontSize: isTitle ? 14 : 12,
            ),
          ),
        ),
      ],
    );
  }

  void _showCancelConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: Colors.orange),
            SizedBox(width: 10),
            Text("Transaction Active"),
          ],
        ),
        content: const Text(
          "Your mobile money payment PIN prompt is currently active. "
          "Leaving or closing now may disrupt settlement verification.\n\n"
          "Are you sure you want to cancel this transaction?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CONTINUE TRANSACTION"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              ref.read(lipilaPaymentProvider.notifier).cancel();
              Navigator.pop(context); // Close sheet
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("ABORT TRANSACTION"),
          ),
        ],
      ),
    );
  }
}
