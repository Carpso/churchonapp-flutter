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
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile not loaded yet. Please wait.")));
      return;
    }
    
    if (amount <= 0 || amount > profile.coins) {
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
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      data: (profile) => _buildScreen(context, profile),
      loading: () => const Scaffold(
        backgroundColor: Color(0xFFFFFAEB),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: Color(0xFFFFFAEB),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, UserProfile? profile) {
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

  String detectZambianNetwork(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    String localNumber = clean;
    if (clean.startsWith('260')) {
      localNumber = '0${clean.substring(3)}';
    } else if (!clean.startsWith('0') && clean.length == 9) {
      localNumber = '0$clean';
    }
    
    if (localNumber.startsWith('096') || localNumber.startsWith('076')) {
      return "MTN";
    } else if (localNumber.startsWith('097') || localNumber.startsWith('077')) {
      return "Airtel";
    } else if (localNumber.startsWith('095') || localNumber.startsWith('075')) {
      return "Zamtel";
    }
    return "MTN";
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
            onChanged: (val) {
              if (type == TextInputType.phone) {
                final detected = detectZambianNetwork(val);
                if (detected != _selectedNetwork) {
                  setState(() => _selectedNetwork = detected);
                }
              }
            },
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
    final networks = [
      {"name": "MTN", "logo": "assets/logo_mtn.png"},
      {"name": "Airtel", "logo": "assets/logo_airtel.png"},
      {"name": "Zamtel", "logo": "assets/logo_zamtel.png"},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Select Network", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: networks.map((net) {
            final isSelected = _selectedNetwork == net['name'];
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedNetwork = net['name']!),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.amber : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? Colors.amber : Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(net['logo']!, height: 16, width: 16, fit: BoxFit.contain),
                      const SizedBox(width: 6),
                      Text(
                        net['name']!,
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
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

