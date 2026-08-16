import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/presentation/register_church_screen.dart';

class OnboardingManagerScreen extends ConsumerStatefulWidget {
  const OnboardingManagerScreen({super.key});

  @override
  ConsumerState<OnboardingManagerScreen> createState() => _OnboardingManagerScreenState();
}

class _OnboardingManagerScreenState extends ConsumerState<OnboardingManagerScreen> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _selectedRole = 'writer'; // 'writer', 'rider', 'driver', 'coa_employee', 'usher', 'event_organizer'
  bool _isSubmitting = false;
  Map<String, dynamic>? _lastOnboarded;

  final List<Map<String, dynamic>> _roles = [
    {'id': 'church', 'label': 'New Ministry', 'icon': LucideIcons.church, 'desc': 'Register a new church tenant'},
    {'id': 'writer', 'label': 'Church Writer', 'icon': LucideIcons.penTool, 'desc': 'Can publish News'},
    {'id': 'rider', 'label': 'Rider', 'icon': LucideIcons.bike, 'desc': 'Delivery personnel'},
    {'id': 'driver', 'label': 'Driver', 'icon': LucideIcons.car, 'desc': 'Transport driver'},
    {'id': 'event_organizer', 'label': 'Event Organizer', 'icon': LucideIcons.calendarDays, 'desc': 'Can create & manage events'},
    {'id': 'coa_employee', 'label': 'COA Employee', 'icon': LucideIcons.briefcase, 'desc': 'Global app operations'},
    {'id': 'usher', 'label': 'Church Usher', 'icon': LucideIcons.userCheck, 'desc': 'Service reporting & finance'},
  ];

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("Entity Onboarding", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 30),
            Text("Assign New Role", style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildRoleSelector(),
            const SizedBox(height: 30),
            TextField(
              controller: _nameCtrl,
              decoration: _inputDecoration("Full Name *", LucideIcons.user),
            ),
            if (_selectedRole != 'church') ...[
              const SizedBox(height: 15),
              TextField(
                controller: _phoneCtrl,
                decoration: _inputDecoration("Phone Number (e.g. 0977123456)", LucideIcons.phone),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _emailCtrl,
                decoration: _inputDecoration("Email Address (optional)", LucideIcons.mail),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _notesCtrl,
                decoration: _inputDecoration("Notes (optional)", LucideIcons.fileText),
                maxLines: 2,
              ),
            ],
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _handleOnboarding,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                minimumSize: const Size(double.infinity, 65),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: _isSubmitting
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text("ONBOARD ENTITY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, color: Theme.of(context).primaryColor, size: 16),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Users without accounts are pre-registered and automatically linked when they sign up with the same phone number.",
                      style: TextStyle(color: Color(0xFF7A5C00), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            if (_lastOnboarded != null) ...[
              const SizedBox(height: 25),
              _buildSuccessCard(_lastOnboarded!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.userPlus, color: Colors.white, size: 40),
          const SizedBox(height: 15),
          const Text(
            "Global Staff Manager",
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            "Pre-register riders, drivers, writers, event organizers and employees into the Ecosystem — even before they have an account.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Column(
      children: _roles.map((role) {
        bool isSelected = _selectedRole == role['id'];
        return GestureDetector(
          onTap: () => setState(() => _selectedRole = role['id']),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? Theme.of(context).primaryColor : const Color(0xFFF1F5F9), width: 2),
            ),
            child: Row(
              children: [
                Icon(role['icon'], color: isSelected ? Theme.of(context).primaryColor : Colors.grey),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(role['label'], style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Theme.of(context).primaryColor : Colors.black)),
                      Text(role['desc'], style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
                if (isSelected) const Icon(LucideIcons.checkCircle2, color: Colors.green, size: 20),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSuccessCard(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.checkCircle2, color: Colors.green, size: 20),
              SizedBox(width: 10),
              Text("Pre-Registration Successful", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow("Name", data['full_name'] ?? ''),
          if ((data['phone_number'] ?? '').isNotEmpty) _infoRow("Phone", data['phone_number']),
          if ((data['email'] ?? '').isNotEmpty) _infoRow("Email", data['email']),
          _infoRow("Role", data['role'].toString().toUpperCase()),
          const SizedBox(height: 8),
          Text(
            "They will be linked automatically when they sign up with the same phone number.",
            style: TextStyle(color: Colors.grey[600], fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: Colors.grey),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFF1F5F9))),
    );
  }

  Future<void> _handleOnboarding() async {
    if (_selectedRole == 'church') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterChurchScreen()));
      return;
    }

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Full name is required"), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final client = Supabase.instance.client;
      final currentUser = client.auth.currentUser;

      final preRegData = {
        'full_name': name,
        'phone_number': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'role': _selectedRole,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'onboarded_by': currentUser?.id,
      };

      // Insert into pre_registrations table
      await client.from('pre_registrations').insert(preRegData);

      // For drivers/riders: also add a pre-registration row to ride_registrations
      if (_selectedRole == 'driver' || _selectedRole == 'rider') {
        await client.from('ride_registrations').insert({
          'type': _selectedRole,
          'status': 'offline',
          'pre_registered_name': name,
          'pre_registered_phone': _phoneCtrl.text.trim(),
          'pre_registered_role': _selectedRole,
        });
      }

      if (mounted) {
        setState(() {
          _lastOnboarded = preRegData;
          _nameCtrl.clear();
          _emailCtrl.clear();
          _phoneCtrl.clear();
          _notesCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Onboarding failed: $e"),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
