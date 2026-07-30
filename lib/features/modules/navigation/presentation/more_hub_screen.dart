import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../events/presentation/events_screen.dart';
import '../../jobs/presentation/jobs_portal_screen.dart';
import '../../logistics/presentation/map_screen.dart';
import '../../kids/presentation/kids_zone_screen.dart';
import '../../media/presentation/radio_screen.dart';
import 'package:church_on_app/features/admin/presentation/admin_hub_screen.dart';
import 'package:church_on_app/features/transport/presentation/rider_onboarding_screen.dart';
import '../../bible_quiz/presentation/bible_quiz_hub_screen.dart';
import 'package:church_on_app/features/logistics/presentation/church_commute_screen.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class MoreHubScreen extends ConsumerWidget {
  const MoreHubScreen({super.key});

  bool _isFeatureEnabled(Tenant? tenant, String key) {
    if (tenant == null) return true;
    return tenant.settings?[key] ?? true;
  }

  void _handleNavigation(BuildContext context, Tenant? tenant, String label, String key, Widget destination) {
    if (!_isFeatureEnabled(tenant, key)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("'$label' has been disabled for this church by the Superadmin. 🔒"),
        backgroundColor: Colors.amber,
      ));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => destination));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Life & Modules", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Logistics & Life", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              childAspectRatio: 1.1,
              children: [
                _buildModuleCard(context, "Events & Calendars", LucideIcons.calendar, Colors.blue, () => _handleNavigation(context, tenant, "Events", "events_management", const EventsScreen())),
                _buildModuleCard(context, "Maps", LucideIcons.map, Colors.orange, () => _handleNavigation(context, tenant, "Maps", "logistics_&_tracking", const MapScreen())),
                _buildModuleCard(context, "Jobs & Serve", LucideIcons.briefcase, Colors.green, () => _handleNavigation(context, tenant, "Jobs & Serve", "jobs_portal", const JobsPortalScreen())),
                _buildModuleCard(context, "Church Commute", LucideIcons.car, Colors.indigo, () => _handleNavigation(context, tenant, "Church Commute", "logistics_&_tracking", const ChurchCommuteScreen())),
              ],
            ),
            const SizedBox(height: 40),
            const Text("Spiritual & Media", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              childAspectRatio: 1.1,
              children: [
                _buildModuleCard(context, "Kids Zone", LucideIcons.gamepad2, Colors.purple, () => _handleNavigation(context, tenant, "Kids Zone", "kids_zone", const KidsZoneScreen())),
                _buildModuleCard(context, "Radio", LucideIcons.radio, Colors.red, () => _handleNavigation(context, tenant, "Radio", "kingdom_radio", const RadioScreen())),
                _buildModuleCard(context, "Bible Quizzing", LucideIcons.brainCircuit, Colors.pink, () => _handleNavigation(context, tenant, "Bible Quizzing", "game_arena", const BibleQuizHubScreen())),
                _buildModuleCard(context, "Drive & Earn", LucideIcons.car, Colors.teal, () => _handleNavigation(context, tenant, "Drive & Earn", "logistics_&_tracking", const RiderOnboardingScreen())),
                _buildModuleCard(context, "Kael AI Assistance", LucideIcons.zap, Colors.amber, () => context.push('/kael-chat')),
                _buildModuleCard(context, "Testimonies", LucideIcons.flame, Colors.orange, () => context.push('/testimonies')),
                _buildModuleCard(context, "Prayer Wall", LucideIcons.helpingHand, Colors.blue, () => context.push('/prayer-wall')),
                _buildModuleCard(context, "Communities", LucideIcons.users, Colors.indigo, () => context.push('/communities')),
                _buildModuleCard(context, "Kingdom Klips", LucideIcons.video, Colors.purple, () => context.push('/kingdom-klips')),
              ],
            ),
            const SizedBox(height: 40),
            const Text("Administration", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildAdminBanner(context),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleCard(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 15),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminHubScreen())),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(15)),
              child: const Icon(LucideIcons.shieldCheck, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 20),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Admin Hub", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text("Manage members, finance & streams", style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

