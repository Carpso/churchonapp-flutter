import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/marketplace/data/marketplace_service.dart';
import 'package:church_on_app/features/admin/data/order_service.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/config/env.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _phoneCtrl = TextEditingController();
  String _selectedNetwork = "MTN";
  String _paymentMethod = "mobile_money";
  String _deliveryMethod = "delivery"; // 'delivery' or 'pickup'

  bool _isProcessing = false;
  bool _isSuccess = false;
  bool _isError = false;
  String? _errorMessage;
  String? _orderReference;

  final List<Map<String, dynamic>> _networks = [
    {"name": "MTN", "color": Colors.yellow, "id": "mtn", "logo": "assets/logo_mtn.png"},
    {"name": "Airtel", "color": Colors.red, "id": "airtel", "logo": "assets/logo_airtel.png"},
    {"name": "Zamtel", "color": Colors.green, "id": "zamtel", "logo": "assets/logo_zamtel.png"},
  ];

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

  double get _platformFee {
    final subtotal = ref.read(cartProvider.notifier).total;
    return subtotal * 0.05 > 3.00 ? subtotal * 0.05 : 3.00;
  }

  double get _deliveryFee => _deliveryMethod == 'delivery' ? 15.0 : 0.0;

  double get _total {
    final subtotal = ref.read(cartProvider.notifier).total;
    return subtotal + _platformFee + _deliveryFee;
  }

  /// Marketplace MoMo Routing: Pay seller via Lipila payout.
  /// Priority: Seller's MoMo → Tenant's MoMo → COA Team MoMo (fallback).
  Future<void> _disburseToSeller(List<CartItem> items, double subtotal, double fee, String? tenantId) async {
    try {
      final supabase = Supabase.instance.client;

      // Collect unique vendor IDs from this order
      final vendorIds = items
          .where((item) => item.product.vendorId != null && item.product.vendorId!.isNotEmpty)
          .map((item) => item.product.vendorId!)
          .toSet()
          .toList();

      if (vendorIds.isEmpty) {
        debugPrint('[Marketplace] No vendors to pay out');
        return;
      }

      for (final vendorId in vendorIds) {
        // Priority 1: Seller's MoMo phone from profiles
        String? sellerPhone;
        try {
          final profile = await supabase
              .from('profiles')
              .select('phone_number')
              .eq('id', vendorId)
              .maybeSingle();
          sellerPhone = profile?['phone_number'] as String?;
        } catch (e) {
          debugPrint('Error fetching seller phone from profile: $e');
        }

        // Priority 2: Tenant's treasurer MoMo
        if (sellerPhone == null || sellerPhone.isEmpty) {
          try {
            final church = await supabase
                .from('churches')
                .select('treasurer_phone')
                .eq('id', tenantId ?? '')
                .maybeSingle();
            sellerPhone = church?['treasurer_phone'] as String?;
          } catch (e) {
            debugPrint('Error fetching treasurer phone from church: $e');
          }
        }

        // Priority 3: COA Team MoMo (fallback)
        if (sellerPhone == null || sellerPhone.isEmpty) {
          sellerPhone = Env.coaMoMoNumber;
        }

        // Calculate this vendor's share (proportional to their items' total_price)
        final vendorItemTotal = items
            .where((item) => item.product.vendorId == vendorId)
            .fold(0.0, (sum, item) => sum + (item.product.price * item.quantity));
        final vendorShare = vendorItemTotal - (vendorItemTotal * 0.05 > 3.00 ? vendorItemTotal * 0.05 : 3.00);
        if (vendorShare <= 0) continue;

        // Normalize phone to 260XXXXXXXXX format
        String phone = sellerPhone.replaceAll(RegExp(r'\D'), '');
        if (phone.startsWith('0')) phone = '260${phone.substring(1)}';
        if (phone.startsWith('9') && phone.length == 9) phone = '260$phone';
        if (phone.length == 9) phone = '260$phone';

        final payoutRef = 'MKT-${DateTime.now().millisecondsSinceEpoch}-$vendorId';
        await supabase.functions.invoke('lipila-payout', body: {
          'accountNumber': phone,
          'amount': vendorShare,
          'narration': 'Marketplace seller payout',
          'referenceId': payoutRef,
        });
        debugPrint('[Marketplace] Paid K${vendorShare.toStringAsFixed(2)} to seller $vendorId via $phone');
      }
    } catch (e) {
      debugPrint('[Marketplace] Seller disbursement failed (non-blocking): $e');
    }
  }

  Future<void> _placeOrder() async {
    final items = ref.read(cartProvider);
    if (items.isEmpty) return;

    if (_paymentMethod == "mobile_money" && _phoneCtrl.text.isEmpty) {
      setState(() {
        _isError = true;
        _errorMessage = "Phone number is required";
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _isError = false;
      _errorMessage = null;
    });

    try {
      final subtotal = ref.read(cartProvider.notifier).total;
      final fee = _platformFee;
      final total = _total;
      final tenant = ref.read(currentTenantProvider);
      final orderService = ref.read(orderServiceProvider);
      final financeService = ref.read(financeServiceProvider);

      String? paymentReference;

      if (_paymentMethod == "wallet") {
        final profile = ref.read(profileProvider).value;
        if (profile == null || profile.coins < total.toInt()) {
          throw Exception("Insufficient wallet balance. You need ${total.toInt()} coins but have ${profile?.coins ?? 0}.");
        }
        await financeService.logTransaction(
          total,
          'product',
          'wallet_${DateTime.now().millisecondsSinceEpoch}',
          tenantId: tenant?.id,
        );
        paymentReference = 'wallet_${DateTime.now().millisecondsSinceEpoch}';
      } else {
        String phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
        if (phone.startsWith('0')) phone = '260${phone.substring(1)}';
        if (phone.startsWith('9')) phone = '260$phone';
        if (phone.length == 9) phone = '260$phone';

        final supabase = Supabase.instance.client;

        final lipilaResponse = await supabase.functions.invoke('lipila-collect', body: {
          "accountNumber": phone,
          "amount": total,
          "narration": "Marketplace Order",
        });

        if (lipilaResponse.data == null) {
          throw Exception("Payment initiation failed");
        }
        final result = lipilaResponse.data is Map
            ? Map<String, dynamic>.from(lipilaResponse.data as Map)
            : {};
        paymentReference = result['reference'] as String?;
      }

      final orderId = await orderService.createOrder(
        items: items.map((item) => {
          'item_id': item.product.id,
          'item_name': item.product.name,
          'quantity': item.quantity,
          'unit_price': item.product.price,
          'total_price': item.product.price * item.quantity,
          'vendor_id': item.product.vendorId,
        }).toList(),
        totalAmount: subtotal,
        deliveryFee: _deliveryFee,
        platformFee: fee,
        paymentReference: paymentReference,
        tenantId: tenant?.id,
      );

      // Marketplace MoMo Routing: Pay seller after order is placed
      if (_paymentMethod == "mobile_money") {
        await _disburseToSeller(items, subtotal, fee, tenant?.id);
      }

      ref.read(cartProvider.notifier).clear();

      if (mounted) {
        setState(() {
          _isSuccess = true;
          _isProcessing = false;
          _orderReference = orderId;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isError = true;
          _errorMessage = e.toString().replaceFirst("Exception: ", "");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final subtotal = ref.read(cartProvider.notifier).total;
    final profileAsync = ref.watch(profileProvider);
    final walletBalance = profileAsync.value?.coins ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Checkout", style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isSuccess ? _buildSuccessState() : _buildCheckoutContent(items, subtotal, walletBalance),
    );
  }

  Widget _buildCheckoutContent(List<CartItem> items, double subtotal, int walletBalance) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOrderSummary(items),
                const SizedBox(height: 24),
                _buildDeliveryMethodSelector(),
                const SizedBox(height: 24),
                _buildPaymentMethodSection(walletBalance),
                const SizedBox(height: 24),
                _buildOrderTotal(subtotal),
                if (_isError && _errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.alertCircle, color: Colors.red, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _buildBottomButton(),
      ],
    );
  }

  Widget _buildOrderSummary(List<CartItem> items) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Order Summary", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text("${items.length} ${items.length == 1 ? 'item' : 'items'}", style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const Divider(height: 24),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text("No items in cart", style: TextStyle(color: Colors.grey))),
            )
          else
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.package, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text("Qty: ${item.quantity}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(
                    "K ${(item.product.price * item.quantity).toStringAsFixed(2)}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildDeliveryMethodSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Delivery Method", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _deliveryMethod = 'delivery'),
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: _deliveryMethod == 'delivery' ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: _deliveryMethod == 'delivery' ? Theme.of(context).primaryColor : Colors.grey.withValues(alpha: 0.2),
                        width: _deliveryMethod == 'delivery' ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(LucideIcons.truck, color: _deliveryMethod == 'delivery' ? Theme.of(context).primaryColor : Colors.grey),
                        const SizedBox(height: 8),
                        const Text("Express Delivery", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text("K15.00", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _deliveryMethod = 'pickup'),
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: _deliveryMethod == 'pickup' ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: _deliveryMethod == 'pickup' ? Theme.of(context).primaryColor : Colors.grey.withValues(alpha: 0.2),
                        width: _deliveryMethod == 'pickup' ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(LucideIcons.mapPin, color: _deliveryMethod == 'pickup' ? Theme.of(context).primaryColor : Colors.grey),
                        const SizedBox(height: 8),
                        const Text("Pickup at Church", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text("FREE", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSection(int walletBalance) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Payment Method", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildPaymentOption(
            icon: LucideIcons.smartphone,
            title: "Mobile Money",
            subtitle: "MTN / Airtel / Zamtel",
            value: "mobile_money",
          ),
          const SizedBox(height: 8),
          _buildPaymentOption(
            icon: LucideIcons.wallet,
            title: "Wallet",
            subtitle: "$walletBalance coins available",
            value: "wallet",
          ),
          if (_paymentMethod == "mobile_money") ...[
            const SizedBox(height: 20),
            const Text("Select Network", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _networks.map((n) {
                final isSelected = _selectedNetwork == n['name'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedNetwork = n['name']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? (n['color'] as Color).withValues(alpha: 0.1) : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? n['color'] as Color : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(n['logo'] as String, height: 18, width: 18, fit: BoxFit.contain),
                        const SizedBox(width: 6),
                        Text(
                          n['name'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isSelected
                                ? (n['color'] == Colors.yellow ? Colors.black87 : n['color'] as Color)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: "Enter Mobile Money number",
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(LucideIcons.phone, size: 20),
              ),
            ),
          ],
          if (_paymentMethod == "wallet") ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.coins, color: Colors.amber, size: 24),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Wallet Balance", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text("$walletBalance coins", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    final isSelected = _paymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.05) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Theme.of(context).primaryColor : Colors.grey, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.onSurface)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            if (isSelected)
              Icon(LucideIcons.checkCircle, color: Theme.of(context).primaryColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderTotal(double subtotal) {
    final fee = _platformFee;
    final delivery = _deliveryFee;
    final total = _total;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Order Total", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(height: 24),
          _buildTotalRow("Subtotal", "K ${subtotal.toStringAsFixed(2)}"),
          const SizedBox(height: 8),
          _buildTotalRow("Platform Fee (5%)", "K ${fee.toStringAsFixed(2)}"),
          if (delivery > 0) ...[
            const SizedBox(height: 8),
            _buildTotalRow("Express Delivery", "K ${delivery.toStringAsFixed(2)}"),
          ],
          if (_deliveryMethod == 'pickup') ...[
            const SizedBox(height: 8),
            _buildTotalRow("Pickup at Church", "FREE", isTotal: false),
          ],
          const Divider(height: 24),
          _buildTotalRow("Total", "K ${total.toStringAsFixed(2)}", isTotal: true),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isTotal ? Theme.of(context).colorScheme.onSurface : Colors.grey,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            fontSize: isTotal ? 16 : 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.bold,
            fontSize: isTotal ? 18 : 14,
            color: isTotal ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButton() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isProcessing ? null : _placeOrder,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.secondary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isProcessing
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text(
                  "PLACE ORDER",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
        ),
      ),
    );
  }

  Widget _buildSuccessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.checkCircle, color: Colors.green, size: 64),
            ),
            const SizedBox(height: 24),
            const Text(
              "Order Placed!",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              "Your order #${_orderReference?.substring(0, 8).toUpperCase() ?? 'N/A'} has been placed successfully.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            if (_orderReference != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Reference: ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      _orderReference!,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => context.go('/'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  "Back to Marketplace",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
