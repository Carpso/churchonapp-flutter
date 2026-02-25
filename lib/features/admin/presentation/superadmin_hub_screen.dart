import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/utils/db_seeder.dart';

class SuperadminHubScreen extends ConsumerStatefulWidget {
  const SuperadminHubScreen({super.key});

  @override
  ConsumerState<SuperadminHubScreen> createState() => _SuperadminHubScreenState();
}

class _SuperadminHubScreenState extends ConsumerState<SuperadminHubScreen> {
  bool _isAuthenticated = false;
  final _passController = TextEditingController();
  String? _error;

  final List<String> _allFeatures = [
    'Kingdom Radio',
    'Marketplace',
    'Kingdom Klips',
    'Jobs Portal',
    'Logistics & Tracking',
    'Kids Zone',
    'Game Arena',
    'Events Management',
    'Giving & Tithes',
    'Bible Quiz'
  ];

  void _verifyPassword() {
    if (_passController.text == "1000%Dollar") {
      setState(() {
        _isAuthenticated = true;
        _error = null;
      });
    } else {
      setState(() => _error = "Incorrect God-Mode Password");
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final profile = ref.watch(profileProvider).value;

    if (profile == null || !profile.isSuperadmin) {
       return const Scaffold(body: Center(child: Text("Unauthorized Access")));
    }

    if (!_isAuthenticated) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(40),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.shieldAlert, color: Colors.red, size: 80),
                const SizedBox(height: 30),
                const Text("GOD-MODE VERIFICATION", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const SizedBox(height: 10),
                const Text("Enter the superadmin secret key to proceed.", style: TextStyle(color: Colors.white30, fontSize: 12)),
                const SizedBox(height: 40),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Secret Key",
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _verifyPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text("UNLOCKED ACCESS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark mode for superadmin
      appBar: AppBar(
        title: const Text("Superadmin God-Mode", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatCards(),
            const SizedBox(height: 30),
            Text("Tenant Management: ${tenant?.name ?? 'Global'}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildFeatureToggles(tenant),
            const SizedBox(height: 40),
            const Text("Global Overrides", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildGlobalAction(LucideIcons.refreshCw, "Force Data Sync", "Triggers re-fetch for all CDN assets", Colors.blue, () {}),
            _buildGlobalAction(LucideIcons.shieldAlert, "Emergency Lockdown", "Instantly disable app for maintenance", Colors.red, () {}),
            _buildGlobalAction(LucideIcons.database, "Clear Tenant Cache", "Wipe local storage for current church", Colors.amber, () {}),
            _buildGlobalAction(LucideIcons.sparkles, "Seed Mock Data", "Populate all tables with demo data", Colors.green, () async {
              try {
                await DbSeeder.seedAll();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mock data seeded successfully! ✅")));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Seeding failed: $e"), backgroundColor: Colors.red));
                }
              }
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCards() {
    return Row(
      children: [
        _buildStatItem("Active Tenants", "42", LucideIcons.building, Colors.blue),
        const SizedBox(width: 15),
        _buildStatItem("Total Users", "12.5k", LucideIcons.users, Colors.green),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 15),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureToggles(Tenant? tenant) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white10)),
      child: Column(
        children: _allFeatures.map((feature) {
          final isEnabled = tenant?.settings?[feature.toLowerCase().replaceAll(' ', '_')] ?? true;
          return SwitchListTile(
            title: Text(feature, style: const TextStyle(color: Colors.white, fontSize: 14)),
            value: isEnabled,
            activeColor: Colors.greenAccent,
            subtitle: Text("Enabled for ${tenant?.name ?? 'all'}", style: const TextStyle(color: Colors.white30, fontSize: 10)),
            onChanged: (val) {
              // In real app, update Supabase tenant settings
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$feature toggled to $val")));
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGlobalAction(IconData icon, String title, String sub, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text(sub, style: const TextStyle(color: Colors.white30, fontSize: 11)),
            ]),
          ),
          Icon(LucideIcons.chevronRight, color: Colors.white24, size: 16),
        ],
      ),
    ),
  );
}
}

