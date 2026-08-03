import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/finance/data/payment_state.dart';
import 'package:church_on_app/features/give/presentation/widgets/momo_phone_input_widget.dart';
import 'package:church_on_app/features/give/presentation/widgets/payment_status_overlay.dart';
import 'package:church_on_app/core/config/fee_config.dart';

enum PaymentMethodType { mobileMoney, card }

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
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _errorMessage;
  PaymentMethodType _paymentMethod = PaymentMethodType.mobileMoney;

  // Platform fee = COA fee + Lipila payment processor fee
  FeeConfig get _fees => ref.read(feeConfigProvider).value ?? FeeConfig.defaults;
  bool get _isCard => _paymentMethod == PaymentMethodType.card;

  double get _platformFee => _fees.platformFee(widget.amount, isCard: _isCard);

  double get _totalCharged => widget.amount + _platformFee;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profileValue = ref.read(profileProvider).value;
      if (profileValue != null) {
        final phone = profileValue.phoneNumber;
        if (phone != null && phone.isNotEmpty) {
          _phoneCtrl.text = phone;
        }
        _firstNameCtrl.text = profileValue.name.split(' ').first;
        _lastNameCtrl.text = profileValue.name.split(' ').skip(1).join(' ');
        final user = Supabase.instance.client.auth.currentUser;
        _emailCtrl.text = user?.email ?? '';
      }
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _initiatePayment() {
    if (_paymentMethod == PaymentMethodType.mobileMoney) {
      _initiateMomoPayment();
    } else {
      _initiateCardPayment();
    }
  }

  void _initiateMomoPayment() {
    final phoneError = MomoPhoneInputWidget.validateZambianPhone(_phoneCtrl.text);
    if (phoneError != null) {
      setState(() => _errorMessage = phoneError);
      return;
    }
    setState(() => _errorMessage = null);
    ref.read(lipilaPaymentProvider.notifier).initiatePayment(
          phone: _phoneCtrl.text,
          amount: _totalCharged,
          description: widget.description,
          narration: widget.paymentReason,
        );
  }

  Future<void> _initiateCardPayment() async {
    if (_firstNameCtrl.text.isEmpty || _lastNameCtrl.text.isEmpty) {
      setState(() => _errorMessage = "First and last name are required");
      return;
    }
    setState(() => _errorMessage = null);

    ref.read(lipilaPaymentProvider.notifier).initiateCardPayment(
          amount: _totalCharged,
          description: widget.description,
          narration: widget.paymentReason,
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.isNotEmpty ? _phoneCtrl.text : null,
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
      } else if (data.status == PaymentStatus.cardRedirect && data.cardUrl != null) {
        _launchCardUrl(data.cardUrl!);
      }
    });

    final isProcessing = paymentState.status == PaymentStatus.initiating ||
        paymentState.status == PaymentStatus.awaitingPin ||
        paymentState.status == PaymentStatus.cardRedirect;

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
            const SizedBox(height: 20),

            // Payment Method Selector
            _buildPaymentMethodSelector(),
            const SizedBox(height: 20),

            // MoMo fields
            if (_paymentMethod == PaymentMethodType.mobileMoney) ...[
              MomoPhoneInputWidget(
                controller: _phoneCtrl,
                selectedNetwork: _selectedNetwork,
                onNetworkChanged: (network) =>
                    setState(() => _selectedNetwork = network),
                error: _errorMessage,
              ),
            ],

            // Card fields
            if (_paymentMethod == PaymentMethodType.card) ...[
              _buildCardFields(),
            ],

            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: _initiatePayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                minimumSize: const Size(double.infinity, 65),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                _paymentMethod == PaymentMethodType.mobileMoney
                    ? "PROCEED TO PIN PROMPT"
                    : "PAY WITH CARD",
                style: const TextStyle(
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

  Widget _buildPaymentMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Payment Method",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _paymentMethod = PaymentMethodType.mobileMoney),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _paymentMethod == PaymentMethodType.mobileMoney
                        ? const Color(0xFF0F172A).withValues(alpha: 0.05)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: _paymentMethod == PaymentMethodType.mobileMoney
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F5F9),
                      width: _paymentMethod == PaymentMethodType.mobileMoney ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.smartphone,
                        color: _paymentMethod == PaymentMethodType.mobileMoney
                            ? const Color(0xFF0F172A)
                            : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Mobile Money",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _paymentMethod == PaymentMethodType.mobileMoney
                              ? const Color(0xFF0F172A)
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _paymentMethod = PaymentMethodType.card),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _paymentMethod == PaymentMethodType.card
                        ? const Color(0xFF0F172A).withValues(alpha: 0.05)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: _paymentMethod == PaymentMethodType.card
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F5F9),
                      width: _paymentMethod == PaymentMethodType.card ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.creditCard,
                        color: _paymentMethod == PaymentMethodType.card
                            ? const Color(0xFF0F172A)
                            : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Card",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _paymentMethod == PaymentMethodType.card
                              ? const Color(0xFF0F172A)
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCardFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _firstNameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: "First Name",
            hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            prefixIcon: const Icon(LucideIcons.user, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lastNameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: "Last Name",
            hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            prefixIcon: const Icon(LucideIcons.user, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: "Email (optional)",
            hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            prefixIcon: const Icon(LucideIcons.mail, size: 20),
          ),
        ),
        if (_errorMessage != null && _errorMessage!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const Icon(LucideIcons.alertCircle, color: Colors.red, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
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
          _buildInfoRow("Amount", "K${widget.amount.toStringAsFixed(2)}"),
          if (widget.category == 'giving' || widget.category == 'donation' || widget.category == 'tithe' || widget.category == 'offering' || widget.category == 'event') ...[
            const SizedBox(height: 4),
            _buildInfoRow(_fees.platformFeeLabel(isCard: _isCard), "K${_platformFee.toStringAsFixed(2)}"),
          ],
          const Divider(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Total (Inc. Fees)",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                "K${_totalCharged.toStringAsFixed(2)}",
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

  Future<void> _launchCardUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
    }
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
          "Your payment is currently active. "
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
              Navigator.pop(context);
              ref.read(lipilaPaymentProvider.notifier).cancel();
              Navigator.pop(context);
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
