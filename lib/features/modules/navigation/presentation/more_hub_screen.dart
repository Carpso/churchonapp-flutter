import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../events/presentation/events_screen.dart';
import '../../jobs/presentation/jobs_portal_screen.dart';
import '../../logistics/presentation/map_screen.dart';
import '../../kids/presentation/kids_zone_screen.dart';
import '../../media/presentation/radio_screen.dart';
import 'package:church_on_app/features/transport/presentation/rider_onboarding_screen.dart';
import '../../bible_quiz/presentation/bible_quiz_hub_screen.dart';
import 'package:church_on_app/features/logistics/presentation/church_commute_screen.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/home/presentation/discover_screen.dart';
import 'package:church_on_app/features/disciple/presentation/discipleship_screen.dart';
import 'package:church_on_app/features/connect/presentation/interchurch_network_screen.dart';
import 'package:church_on_app/features/connect/presentation/network_activity_screen.dart';
import 'package:church_on_app/features/home/presentation/song_lyrics_screen.dart';
import 'package:church_on_app/features/finance/presentation/tithe_card_screen.dart';
import 'package:church_on_app/features/connect/presentation/pastors_corner_screen.dart';
import 'package:church_on_app/features/modules/jobs/presentation/my_jobs_screen.dart';
import 'package:church_on_app/features/modules/jobs/presentation/my_applications_screen.dart';
import 'package:church_on_app/features/connect/presentation/poll_creator_screen.dart';
import 'package:church_on_app/features/connect/presentation/create_klip_screen.dart';
import 'package:church_on_app/features/transport/presentation/ride_history_screen.dart';
import 'package:church_on_app/features/home/presentation/news_list_screen.dart';
import 'package:church_on_app/features/home/presentation/branch_locator_screen.dart';
import 'package:church_on_app/features/transport/presentation/sos_trigger_screen.dart';
import 'life_hub_screen.dart';

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
    final profile = ref.watch(profileProvider).value;
    final isAdmin = profile?.isAdminOrHigher ?? false;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                _buildModuleCard(context, "Events & Calendars", LucideIcons.calendar, Theme.of(context).primaryColor, () => _handleNavigation(context, tenant, "Events", "events_management", const EventsScreen())),
                _buildModuleCard(context, "Maps", LucideIcons.map, Colors.orange, () => _handleNavigation(context, tenant, "Maps", "logistics_&_tracking", const MapScreen())),
                _buildModuleCard(context, "Jobs & Serve", LucideIcons.briefcase, Colors.green, () => _handleNavigation(context, tenant, "Jobs & Serve", "jobs_portal", const JobsPortalScreen())),
                _buildModuleCard(context, "Church Commute", LucideIcons.car, Theme.of(context).primaryColor.withValues(alpha: 0.7), () => _handleNavigation(context, tenant, "Church Commute", "logistics_&_tracking", const ChurchCommuteScreen())),
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
                _buildModuleCard(context, "Kids Zone", LucideIcons.gamepad2, Theme.of(context).primaryColor.withValues(alpha: 0.8), () => _handleNavigation(context, tenant, "Kids Zone", "kids_zone", const KidsZoneScreen())),
                _buildModuleCard(context, "Radio", LucideIcons.radio, Colors.red, () => _handleNavigation(context, tenant, "Radio", "kingdom_radio", const RadioScreen())),
                _buildModuleCard(context, "Bible Quizzing", LucideIcons.brainCircuit, Theme.of(context).primaryColor.withValues(alpha: 0.55), () => _handleNavigation(context, tenant, "Bible Quizzing", "game_arena", const BibleQuizHubScreen())),
                _buildModuleCard(context, "Drive & Earn", LucideIcons.car, Theme.of(context).primaryColor.withValues(alpha: 0.45), () => _handleNavigation(context, tenant, "Drive & Earn", "logistics_&_tracking", const RiderOnboardingScreen())),
                _buildModuleCard(context, "Kael AI Assistance", LucideIcons.zap, Colors.amber, () => context.push('/kael-chat')),
                _buildModuleCard(context, "Testimonies", LucideIcons.flame, Colors.orange, () => context.push('/testimonies')),
                _buildModuleCard(context, "Prayer Wall", LucideIcons.helpingHand, Theme.of(context).primaryColor.withValues(alpha: 0.75), () => context.push('/prayer-wall')),
                _buildModuleCard(context, "Communities", LucideIcons.users, Theme.of(context).primaryColor.withValues(alpha: 0.6), () => context.push('/communities')),
                _buildModuleCard(context, "Klips", LucideIcons.video, Theme.of(context).primaryColor.withValues(alpha: 0.45), () => context.push('/kingdom-klips')),
              ],
            ),
            const SizedBox(height: 40),
            const Text("More to Explore", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              childAspectRatio: 1.1,
              children: [
                _buildModuleCard(context, "Discover", LucideIcons.compass, Theme.of(context).primaryColor.withValues(alpha: 0.8), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverScreen()))),
                _buildModuleCard(context, "Discipleship", LucideIcons.graduationCap, Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscipleshipScreen()))),
                _buildModuleCard(context, "Interchurch Network", LucideIcons.network, Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InterchurchNetworkScreen()))),
                _buildModuleCard(context, "Network Activity", LucideIcons.activity, Colors.cyan, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NetworkActivityScreen()))),
                _buildModuleCard(context, "Song Lyrics", LucideIcons.music, Colors.pink, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SongLyricsScreen()))),
                _buildModuleCard(context, "Tithe Card", LucideIcons.creditCard, Colors.amber, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TitheCardScreen()))),
                _buildModuleCard(context, "Pastors Corner", LucideIcons.mic2, Colors.deepOrange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PastorsCornerScreen()))),
                _buildModuleCard(context, "My Jobs", LucideIcons.briefcase, Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyJobsScreen()))),
                _buildModuleCard(context, "My Applications", LucideIcons.fileText, Colors.lightBlue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyApplicationsScreen()))),
                _buildModuleCard(context, "Poll Creator", LucideIcons.vote, Colors.deepPurple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PollCreatorScreen()))),
                _buildModuleCard(context, "Create Klip", LucideIcons.clapperboard, Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateKlipScreen()))),
                _buildModuleCard(context, "Ride History", LucideIcons.car, Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RideHistoryScreen()))),
                _buildModuleCard(context, "News", LucideIcons.newspaper, Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewsListScreen()))),
                _buildModuleCard(context, "Branch Locator", LucideIcons.mapPin, Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BranchLocatorScreen()))),
                _buildModuleCard(context, "SOS Emergency", LucideIcons.siren, Colors.redAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SosTriggerScreen()))),
                _buildModuleCard(context, "Life Hub", LucideIcons.heart, Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LifeHubScreen()))),
                _buildModuleCard(context, "Year Planner", LucideIcons.calendarDays, Colors.indigo, () => context.push('/year-planner')),
              ],
            ),
            const SizedBox(height: 40),
            if (isAdmin) ...[
              const Text("Administration", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              _buildAdminBanner(context),
              const SizedBox(height: 50),
            ],
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
      onTap: () => context.push('/admin-hub'),
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

