import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/platform_settings_service.dart';
import 'package:church_on_app/core/config/env.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/finance/presentation/lipila_payment_gateway.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class CoaMissionsDonateScreen extends ConsumerStatefulWidget {
  const CoaMissionsDonateScreen({super.key});

  @override
  ConsumerState<CoaMissionsDonateScreen> createState() => _CoaMissionsDonateScreenState();
}

class _CoaMissionsDonateScreenState extends ConsumerState<CoaMissionsDonateScreen> {
  final _amountCtrl = TextEditingController(text: "50");
  bool _isProcessing = false;
  String _selectedPurpose = "missions";

  final List<Map<String, dynamic>> _purposes = [
    {"id": "missions", "label": "In-House Missions", "icon": LucideIcons.globe},
    {"id": "development", "label": "App Development", "icon": LucideIcons.code},
    {"id": "outreach", "label": "Community Outreach", "icon": LucideIcons.heart},
    {"id": "general", "label": "General Support", "icon": LucideIcons.hand},
  ];

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  /// Lipila expects the international 260XXXXXXXXX form, but admins often
  /// save the local 09XXXXXXXX / 9XXXXXXXX variant.
  String _normalizePhone(String raw) {
    var s = raw.replaceAll(RegExp(r'\D'), '');
    if (s.startsWith('260')) return s;
    if (s.startsWith('0')) {
      s = '260${s.substring(1)}';
    } else if (s.length == 9) {
      s = '260$s';
    }
    return s;
  }

  void _donate() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
    if (amount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Minimum donation is K1.00"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isProcessing = true);

    final purpose = _purposes.firstWhere((p) => p['id'] == _selectedPurpose);

    // Use the number superadmins configure in the hub (platform_settings
    // `coa_treasury_phone`); the compiled-in .env value is only a fallback.
    final settings = ref.read(platformSettingsProvider).value;
    final treasuryPhone = _normalizePhone(
      (settings?.coaTreasuryPhone ?? '').trim().isNotEmpty
          ? settings!.coaTreasuryPhone.trim()
          : Env.coaTreasuryPhone,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => LipilaPaymentGateway(
        amount: amount,
        description: "${purpose['label']} - Church On App Support",
        category: 'giving',
        recipientName: "Church On App Team",
        recipientAccount: treasuryPhone,
        paymentReason: "missions_donate_${purpose['id']}",
        onComplete: (success, transactionId) async {
          Navigator.pop(sheetCtx);
          if (success && transactionId != null) {
            // Record the donation in the database
            try {
              final supabase = ref.read(supabaseServiceProvider);
              final profile = ref.read(profileProvider).value;
              final tenant = ref.read(currentTenantProvider);

              await supabase.client.from('transactions').insert({
                'user_id': profile?.id,
                'tenant_id': tenant?.id,
                'amount': amount,
                'type': 'donation',
                'category': 'missions',
                'status': 'completed',
                'reference': transactionId,
                'description': "${purpose['label']} - Church On App Support",
                'recipient_name': 'Church On App Team',
                'created_at': DateTime.now().toIso8601String(),
              });

              // Send a notification to the COA team
              final token = supabase.client.auth.currentSession?.accessToken;
              if (token != null) {
                await supabase.client.functions.invoke('push-notifications', body: {
                  'userId': Env.treasuryId.isNotEmpty ? Env.treasuryId : (profile?.id ?? ''),
                  'title': 'New Missions Donation',
                  'body': '${profile?.name ?? "A supporter"} donated K${amount.toStringAsFixed(2)} for ${purpose['label']}',
                  'data': {
                    'type': 'missions_donation',
                    'reference_id': transactionId,
                    'channel_id': 'coa_missions',
                  },
                });
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Thank you! Your donation of K${amount.toStringAsFixed(2)} was received."),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e) {
              debugPrint('Error recording donation: $e');
            }
          }
        },
      ),
    );

    setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("Support Church On App", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.heart, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    "Support Our Missions",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Your donation helps fuel Church On App's in-house missions, app development, and community outreach programs.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Purpose selection
            Text(
              "Select Purpose",
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _purposes.map((p) {
                final isSelected = _selectedPurpose == p['id'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedPurpose = p['id']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? const Color(0xFF0F172A) : Colors.grey.withValues(alpha: 0.2), width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 5)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(p['icon'], color: isSelected ? Colors.white : const Color(0xFF0F172A), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          p['label'],
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF0F172A),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 30),

            // Amount input
            Text(
              "Donation Amount (ZMW)",
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: "Enter amount",
                prefixIcon: const Icon(LucideIcons.banknote, color: Colors.grey),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFF0F172A), width: 2),
                ),
              ),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 30),

            // Quick amount buttons
            Wrap(
              spacing: 12,
              children: ["25", "50", "100", "250", "500"].map((amt) {
                return GestureDetector(
                  onTap: () => setState(() => _amountCtrl.text = amt),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Text("K$amt", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 40),

            // Donate button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _donate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: _isProcessing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.heart, color: Colors.red, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          "DONATE K${_amountCtrl.text.isEmpty ? '0' : _amountCtrl.text}",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
              ),
            ),

            const SizedBox(height: 30),

            // Info section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "About Church On App Missions",
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem("In-House Missions", "Supporting COA's internal missionaries and evangelism efforts"),
                  _buildInfoItem("App Development", "Funding ongoing feature development and platform improvements"),
                  _buildInfoItem("Community Outreach", "Enabling free digital ministry tools for underserved churches"),
                  _buildInfoItem("Platform Sustainability", "Keeping Church On App free for all users"),
                  const SizedBox(height: 15),
                  const Text(
                    "Payments are processed securely via Lipila Mobile Money (MTN/Airtel/Zamtel). A 1% platform fee is retained for transaction processing. Regulated by Bank of Zambia.",
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.check, color: Colors.green, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(description, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
