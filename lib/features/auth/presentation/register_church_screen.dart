import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/auth_provider.dart';

class RegisterChurchScreen extends ConsumerStatefulWidget {
  const RegisterChurchScreen({super.key});

  @override
  ConsumerState<RegisterChurchScreen> createState() => _RegisterChurchScreenState();
}

class _RegisterChurchScreenState extends ConsumerState<RegisterChurchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _treasurerPhoneController = TextEditingController();
  String _selectedRole = 'pastor'; // pastor or bishop
  bool _loading = false;

  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final user = ref.read(authProvider).user;
      if (user == null) throw Exception("Please login first");

      final slug = _nameController.text.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');
      
      await Supabase.instance.client.from('churches').insert({
        'name': _nameController.text.trim(),
        'address': _locationController.text.trim(),
        'country': 'Zambia',
        'treasurer_phone': _treasurerPhoneController.text.trim(),
        'slug': slug,
        'status': 'pending',
        'role_requested': _selectedRole,
      });

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSuccessDialog() {
    final fee = _selectedRole == 'pastor' ? 'K 1,500' : 'K 2,000';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Icon(LucideIcons.checkCircle, color: Colors.green, size: 60),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Registration Received!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 15),
            Text(
              "Within 3 days, you are required to pay the onboarding fee of $fee to activate your church management suite.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(15)),
              child: const Column(
                children: [
                  Text("Zamtel/Airtel/MTN Money", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  Text("Merchant ID: 123456", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.blue)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // dialog
                Navigator.of(context).pop(); // screen
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(200, 50)),
              child: const Text("UNDERSTOOD"),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fee = _selectedRole == 'pastor' ? 'K 1,500' : 'K 2,000';

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Register Your Church", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Join Church On App", style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("Empower your ministry with Zambia's leading church management suite.", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 40),
              
              const Text("I am registering as a:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildRoleCard('pastor', 'Pastor', LucideIcons.user),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildRoleCard('bishop', 'Bishop', LucideIcons.crown),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              
              _buildTextField(_nameController, "Church Name", LucideIcons.church),
              const SizedBox(height: 20),
              _buildTextField(_locationController, "Main Location / City", LucideIcons.mapPin),
              const SizedBox(height: 20),
              _buildTextField(_treasurerPhoneController, "Treasurer / Financial Phone #", LucideIcons.phone, keyboardType: TextInputType.phone),
              
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber.shade100)),
                child: Row(
                  children: [
                    const Icon(LucideIcons.wallet, color: Colors.amber),
                    const SizedBox(width: 15),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Required Onboarding Fee", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text(fee, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.amber)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              
              _loading 
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _handleRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text("SUBMIT REGISTRATION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  "By submitting, you agree to our Terms of Service. Church approvals typically take 24-48 hours.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(String role, String title, IconData icon) {
    final active = _selectedRole == role;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: active ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? Colors.black : Colors.grey.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: active ? Colors.white : Colors.black45, size: 30),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(color: active ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: (v) => v!.isEmpty ? "Required" : null,
        decoration: InputDecoration(
          icon: Icon(icon, color: Colors.grey, size: 20),
          labelText: label,
          labelStyle: const TextStyle(fontSize: 14, color: Colors.grey),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

