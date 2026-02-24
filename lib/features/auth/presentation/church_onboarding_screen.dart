import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ChurchOnboardingScreen extends ConsumerStatefulWidget {
  const ChurchOnboardingScreen({super.key});

  @override
  ConsumerState<ChurchOnboardingScreen> createState() => _ChurchOnboardingScreenState();
}

class _ChurchOnboardingScreenState extends ConsumerState<ChurchOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Form Fields
  final _nameController = TextEditingController();
  final _pastorController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  String _selectedThemeColor = "#8B5CF6";
  bool _isSubmitting = false;

  void _next() {
    if (_currentStep < 2) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      final supabase = Supabase.instance.client;
      final slug = _nameController.text.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');
      
      await supabase.from('churches').insert({
        'name': _nameController.text,
        'slug': slug,
        'pastor_name': _pastorController.text,
        'contact_phone': _phoneController.text,
        'address': _addressController.text,
        'primary_color': _selectedThemeColor,
        'is_verified': true, // Auto-verified for this demo
      });

      if (mounted) {
        _showSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.checkCircle, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text("Kingdom Gateway Active!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
            const SizedBox(height: 10),
            Text("${_nameController.text} is now live on the Church On App ecosystem.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Exit onboarding
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("ENTER DASHBOARD"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Church Onboarding", style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          _buildProgressIndicator(),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentStep = i),
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBasicInfoStep(),
                _buildLeaderInfoStep(),
                _buildBrandingStep(),
              ],
            ),
          ),
          _buildBottomNavigation(),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.all(25),
      child: Row(
        children: List.generate(3, (index) {
          final active = index <= _currentStep;
          return Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: active ? Colors.amber : Colors.grey[200],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBasicInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Church Identity", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const Text("Tell us about your congregation.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
          _buildFormLabel("Church Registered Name"),
          _buildTextField(_nameController, "e.g. Grace Chapel International", LucideIcons.church),
          const SizedBox(height: 20),
          _buildFormLabel("Physical Address in Zambia"),
          _buildTextField(_addressController, "e.g. Plot 123, Great East Road", LucideIcons.mapPin),
        ],
      ),
    );
  }

  Widget _buildLeaderInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Apostolic Oversight", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const Text("Who is the lead visionary?", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
          _buildFormLabel("Lead Pastor / Bishop Name"),
          _buildTextField(_pastorController, "e.g. Rev. John Banda", LucideIcons.user),
          const SizedBox(height: 20),
          _buildFormLabel("Administrative Phone Number"),
          _buildTextField(_phoneController, "e.g. +260 977 ...", LucideIcons.phone),
        ],
      ),
    );
  }

  Widget _buildBrandingStep() {
    final colors = ["#8B5CF6", "#F59E0B", "#10B981", "#EF4444", "#3B82F6", "#000000"];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Kingdom Branding", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const Text("Customize your digital sanctuary.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
          _buildFormLabel("Primary Theme Color"),
          const SizedBox(height: 15),
          Wrap(
            spacing: 15,
            runSpacing: 15,
            children: colors.map((col) {
              final isSelected = _selectedThemeColor == col;
              return GestureDetector(
                onTap: () => setState(() => _selectedThemeColor = col),
                child: Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    color: Color(int.parse(col.replaceAll('#', '0xFF'))),
                    shape: BoxShape.circle,
                    border: isSelected ? Border.all(color: Colors.amber, width: 4) : null,
                  ),
                  child: isSelected ? const Icon(LucideIcons.check, color: Colors.white) : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 40),
          const Center(
            child: Column(
              children: [
                Icon(LucideIcons.shieldCheck, color: Colors.amber, size: 40),
                SizedBox(height: 10),
                Text("AUTO-VERIFICATION ENABLED", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                Text("VPS Multi-Tenant Isolation Secure", style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -10))],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("BACK"),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 15),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                minimumSize: const Size(0, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
              child: _isSubmitting
                ? const CircularProgressIndicator(color: Colors.black)
                : Text(_currentStep == 2 ? "FINALIZE ONBOARDING" : "NEXT STEP", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[200]!)),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          icon: Icon(icon, size: 20, color: Colors.amber),
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[300], fontSize: 14),
        ),
      ),
    );
  }
}
