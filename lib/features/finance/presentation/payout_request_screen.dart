import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/admin/data/admin_service.dart';
import '../../../core/providers/profile_provider.dart';

class PayoutRequestScreen extends ConsumerStatefulWidget {
  const PayoutRequestScreen({super.key});

  @override
  ConsumerState<PayoutRequestScreen> createState() => _PayoutRequestScreenState();
}

class _PayoutRequestScreenState extends ConsumerState<PayoutRequestScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String _selectedNetwork = "MTN";
  bool _submitting = false;

  void _submitRequest() async {
    if (_amountController.text.isEmpty || _phoneController.text.isEmpty) return;
    
    final amount = double.tryParse(_amountController.text) ?? 0;
    final profile = ref.read(profileProvider).value;
    
    if (amount <= 0 || amount > (profile?.coins ?? 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid amount or insufficient balance")));
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(adminServiceProvider).requestPayout(
        amount: amount,
        mobileNumber: _phoneController.text,
        network: _selectedNetwork,
      );
      
      // Deduct coins locally/optimistically (real deduction usually happens on server)
      await ref.read(profileProvider.notifier).addCoins(-amount.toInt());

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payout request sent! Processing usually takes 1-2 hours.")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final balance = profile?.coins ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Mobile Money Payout", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBalanceCard(balance),
            const SizedBox(height: 30),
            const Text("Withdraw Funds", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _buildInputField("Amount to Withdraw (K)", _amountController, LucideIcons.banknote, TextInputType.number),
            const SizedBox(height: 15),
            _buildInputField("Mobile Money Number", _phoneController, LucideIcons.phone, TextInputType.phone),
            const SizedBox(height: 15),
            _buildNetworkSelector(),
            const SizedBox(height: 40),
            _buildSubmitButton(),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                "Secure Payout via Kingdom Settlement Engine",
                style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(int balance) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("TOTAL EARNINGS", style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 5),
          Text("K ${balance.toDouble()}", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, IconData icon, TextInputType type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child: TextField(
            controller: controller,
            keyboardType: type,
            decoration: InputDecoration(
              icon: Icon(icon, color: Colors.amber, size: 20),
              border: InputBorder.none,
              hintText: "Enter $label",
              hintStyle: TextStyle(color: Colors.grey[300], fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkSelector() {
    final networks = ["MTN", "Airtel", "Zamtel"];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Select Network", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: networks.map((net) {
            final isSelected = _selectedNetwork == net;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedNetwork = net),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.amber : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      net,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submitRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: _submitting 
          ? const CircularProgressIndicator(color: Colors.black)
          : const Text("REQUEST PAYOUT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}
