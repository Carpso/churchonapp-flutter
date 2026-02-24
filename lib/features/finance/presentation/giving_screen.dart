import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/features/admin/data/admin_service.dart';
import 'tithe_history_screen.dart';
import 'lenco_payment_gateway.dart';
import 'package:church_on_app/features/finance/presentation/qr_payment_screen.dart' as qps;
import 'package:church_on_app/core/services/tenant_service.dart';

class GivingScreen extends ConsumerStatefulWidget {
  const GivingScreen({super.key});

  @override
  ConsumerState<GivingScreen> createState() => _GivingScreenState();
}

class _GivingScreenState extends ConsumerState<GivingScreen> {
  String _selectedCategory = "Tithe";
  final TextEditingController _amountController = TextEditingController();

  final List<String> _categories = ["Tithe", "Offering", "Mission", "Building Fund", "Other"];

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Giving", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const TitheHistoryScreen())),
            icon: const Icon(LucideIcons.history, size: 16),
            label: const Text("HISTORY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            _buildTotalGivenCard(profile),
            const SizedBox(height: 30),
            _buildCategorySelector(),
            const SizedBox(height: 30),
            _buildAmountInput(),
            const SizedBox(height: 40),
            _buildPaymentMethods(),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(_amountController.text) ?? 0.0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a valid amount")));
                  return;
                }
                
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) {
                    final tenant = ref.read(currentTenantProvider);
                    return LencoPaymentGateway(
                      amount: amount * 1.06, // Including fee
                      description: "Kingdom Giving: $_selectedCategory",
                      category: _selectedCategory.toLowerCase(),
                      recipientName: tenant?.name ?? "Local Church",
                      recipientAccount: tenant?.treasurerPhone ?? "CHURCH-OFFICIAL-AC",
                      paymentReason: "$_selectedCategory Support",
                    onComplete: (success, txId) async {
                      Navigator.pop(context); // Close gateway
                      if (success) {
                        await ref.read(financeServiceProvider).logTransaction(
                          amount, 
                          _selectedCategory.toLowerCase(), 
                          txId!,
                          tenantId: tenant?.id,
                        );
                        if (mounted) _showSuccessDialog(txId);
                      }
                    },
                  );
                },
              );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text("PROCEED TO SECURE PAYMENT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            ),
            const SizedBox(height: 15),
            TextButton(
              onPressed: () {
                final amount = double.tryParse(_amountController.text) ?? 0.0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a valid amount")));
                  return;
                }
                Navigator.push(context, MaterialPageRoute(builder: (context) => qps.QrPaymentScreen(
                  amount: amount,
                  description: "Giving: $_selectedCategory",
                  recipient: ref.read(currentTenantProvider)?.name ?? "Kingdom Local Church",
                )));
              },
              child: const Text("Pay via Kingdom QR Code", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _showGivingKey(),
              child: const Text("Generate Offline Giving Key", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(String txId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Icon(LucideIcons.checkCircle, color: Colors.green, size: 50),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Transaction Successful!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 10),
            Text("Reference: $txId", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 20),
            const Text("Your seed has been received. God bless your faithfulness.", textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("AMEN")),
        ],
      ),
    );
  }

  Widget _buildTotalGivenCard(UserProfile? profile) {
    final balanceZmw = profile?.balanceZmw ?? 0.0;
    final balanceCc = profile?.balanceCc ?? 0.0;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("STEWARDSHIP REWARDS", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text("K ${balanceZmw.toInt()}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                   const Text("ZMW BALANCE", style: TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                   Text("${balanceCc.toInt()} CC", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                   const Text("REWARDS CC", style: TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Text("Sovereign Material Rewards Active", style: TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildCategorySelector() {
    return SizedBox(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedCategory == _categories[index];
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = _categories[index]),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
              ),
              child: Center(
                child: Text(
                  _categories[index],
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAmountInput() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Enter Amount (K)", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            onChanged: (v) => setState(() {}),
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary),
            decoration: const InputDecoration(
              hintText: "0.00",
              prefixText: "K ",
              border: InputBorder.none,
            ),
          ),
          if (_amountController.text.isNotEmpty) ...[
             const SizedBox(height: 10),
             Row(
               children: [
                 const Icon(LucideIcons.info, size: 12, color: Colors.blue),
                 const SizedBox(width: 5),
                 Text("+ 6% Transaction Fee (K${(double.parse(_amountController.text) * 0.06).toStringAsFixed(2)})", style: const TextStyle(color: Colors.blue, fontSize: 10)),
               ],
             )
          ]
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Select Method", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        _buildPaymentOption("Mobile Money", LucideIcons.smartphone, true),
        const SizedBox(height: 10),
        _buildPaymentOption("Church Wallet", LucideIcons.wallet, false),
        const SizedBox(height: 10),
        _buildPaymentOption("Credit/Debit Card", LucideIcons.creditCard, false),
      ],
    );
  }

  Widget _buildPaymentOption(String title, IconData icon, bool isSelected) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isSelected ? Theme.of(context).primaryColor : Colors.transparent, width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).primaryColor, size: 24),
          const SizedBox(width: 15),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          if (isSelected) const Icon(LucideIcons.checkCircle, color: Colors.green, size: 20),
        ],
      ),
    );
  }

  void _showGivingKey() {
    if (_amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter an amount first.")));
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        backgroundColor: const Color(0xFF1E293B), // Premium dark theme for the key
        title: const Text("OFFICIAL GIVING KEY", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Present this at any verified COA hub or use in USSD checkout.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 11)),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)),
              child: const Text("COA-GIVE-8822-XP", style: TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
            const SizedBox(height: 25),
            const Icon(LucideIcons.qrCode, color: Colors.white, size: 100),
            const SizedBox(height: 20),
            Text("Amount: K${_amountController.text}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              child: const Text("DONE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
