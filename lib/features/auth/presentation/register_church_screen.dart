import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/code_generator_service.dart';
import '../../../core/utils/country_detection_util.dart';
import '../../../core/services/plan_service.dart';
import '../../../core/config/remote_config.dart';

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
  double? _lat;
  double? _lng;
  String _detectedCountry = 'Zambia';

  @override
  void initState() {
    super.initState();
    _detectLocation();
  }

  Future<void> _detectLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _detectedCountry = detectCountryFromPlacemark(
            placemarks.first.country,
          ) ?? 'Zambia';
        });
      }
    } catch (e) {
      debugPrint("Error detecting location: $e");
    }
  }

  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final user = ref.read(authProvider).user;
      if (user == null) throw Exception("Please login first");

      final slug = _nameController.text.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');
      final client = Supabase.instance.client;

      // Check for duplicate church name
      final existing = await client.from('tenants').select('id').ilike('name', _nameController.text.trim()).maybeSingle();
      if (existing != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A church with this name already exists'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final tenantRes = await client.from('tenants').insert({
        'name': _nameController.text.trim(),
        'type': 'church',
        'country': _detectedCountry,
      }).select('id').single();
      final tenantId = tenantRes['id'] as String;

      await client.from('churches').insert({
        'name': _nameController.text.trim(),
        'address': _locationController.text.trim(),
        'country': _detectedCountry,
        'latitude': _lat,
        'longitude': _lng,
        'contact_phone': _treasurerPhoneController.text.trim(),
        'slug': slug,
        'tenant_id': tenantId,
        'is_verified': false,
        'subscription_ends_at': DateTime.now()
            .add(Duration(days: widgetRemoteConfig(ref).trialDurationDays))
            .toIso8601String(),
      });

      await client.from('profiles').update({
        'tenant_id': tenantId,
        'role': _selectedRole,
      }).eq('id', user.id);

      String? inviteCode;
      try {
        final codeGen = CodeGeneratorService(client);
        inviteCode = await codeGen.generateTenantCode(_detectedCountry);
        await codeGen.registerCode(
          codeType: 'tenant',
          codeValue: inviteCode,
          countryIso: CodeGeneratorService.countryToISO(_detectedCountry),
          userId: user.id,
          metadata: {'tenant_id': tenantId, 'church_name': _nameController.text.trim()},
        );
      } catch (e) {
        debugPrint('Invite code generation failed: $e');
      }

      if (mounted) {
        _showSuccessDialog(inviteCode: inviteCode);
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

  void _showSuccessDialog({String? inviteCode}) {
    final fee = 'K${PlanLimits.onboardingFeeKwacha.toStringAsFixed(0)}';
    final churchName = _nameController.text.trim();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Icon(LucideIcons.checkCircle, color: Colors.green, size: 60),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Registration Received!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 15),
              Text(
                "You're on a 30-day FREE Silver trial! After the trial, pay a one-time onboarding fee of $fee to unlock 30 days of Platinum — or stay on Silver for free forever.",
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
                    Text("Superadmin MoMo: 0976847775", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.blue)),
                  ],
                ),
              ),
              if (inviteCode != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(15)),
                  child: Column(
                    children: [
                      const Text("Share This Invite Code", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      SelectableText(inviteCode, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final link = "https://churchonapp.com/join?code=$inviteCode";
                            SharePlus.instance.share(
                              ShareParams(
                                text: "Join our church $churchName on Church On App!\n\nUse invite code: $inviteCode\nOr open: $link",
                              ),
                            );
                          },
                          icon: const Icon(LucideIcons.share2, size: 18),
                          label: const Text("Share Invite Link"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(ctx).pop();
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
          border: Border.all(color: active ? Colors.black : Colors.grey.withValues(alpha: 0.2)),
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
        textCapitalization: label.contains("Phone") || label.contains("Number") ? TextCapitalization.none : TextCapitalization.words,
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Required';
          if (label == "Church Name" && v.trim().length < 2) return 'Min 2 characters';
          if (label == "Treasurer / Financial Phone #" && v.replaceAll(RegExp(r'\D'), '').length < 10) return 'Min 10 digits';
          return null;
        },
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

