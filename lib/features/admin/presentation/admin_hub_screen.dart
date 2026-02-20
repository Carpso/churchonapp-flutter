import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'member_management_screen.dart';
import 'finance_dashboard_screen.dart';
import 'media_upload_screen.dart';
import 'go_live_screen.dart';
import 'superadmin_dashboard.dart';
import 'bishop_dashboard.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/stats_provider.dart';

class AdminHubScreen extends ConsumerWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Admin Hub", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            statsAsync.when(
              data: (stats) => _buildStatGrid(stats),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => const Center(child: Text("Error loading stats")),
            ),
            const SizedBox(height: 40),
            const Text("Management Console", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _buildAdminTile(
              context,
              LucideIcons.shieldAlert,
              "SuperAdmin Console",
              "Global settings, Tenants & Platform access",
              Colors.black87,
              () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SuperAdminDashboard())),
            ),
            _buildAdminTile(
              context,
              LucideIcons.globe,
              "Apostolic Oversight",
              "Multi-branch analytics and performance",
              Colors.purple,
              () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BishopDashboard())),
            ),
            const Divider(height: 30),
            _buildAdminTile(
              context,
              LucideIcons.users,
              "Member Management",
              "Track your flock, verify baptisms & attendance",
              Colors.blue,
              () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MemberManagementScreen())),
            ),
            _buildAdminTile(
              context,
              LucideIcons.barChart3,
              "Financial Oversight",
              "Annual stewardship, tithes & marketplace analytics",
              Colors.green,
              () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FinanceDashboardScreen())),
            ),
            _buildAdminTile(
              context,
              LucideIcons.video,
              "Kingdom Live Studio",
              "Connect to VPS & start church-wide broadcast",
              Colors.red,
              () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GoLiveScreen())),
            ),
            _buildAdminTile(
              context,
              LucideIcons.uploadCloud,
              "Media Hub (R2)",
              "Upload sermons, trailers & Kingdom Klips",
              Colors.orange,
              () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MediaUploadScreen())),
            ),
            _buildAdminTile(
              context,
              LucideIcons.megaphone,
              "Global Broadcast",
              "Send push notifications & church-wide alerts",
              Colors.purple,
              () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Broadcast feature coming soon!")),
                );
              },
            ),
            _buildAdminTile(
              context,
              LucideIcons.calendarDays,
              "Event Scheduling",
              "Coordinate services, missions & conferences",
              Colors.red,
              () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Scheduler coming soon!")),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatGrid(AdminStats stats) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard("Total Members", stats.totalMembers.toString(), LucideIcons.users, Colors.blue),
        _buildStatCard("Growth Rate", stats.growthRate, LucideIcons.trendingUp, Colors.green),
        _buildStatCard("Recent Giving", stats.recentGiving, LucideIcons.heartPulse, Colors.red),
        _buildStatCard("Live Viewers", stats.liveViewers, LucideIcons.video, Colors.orange),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildAdminTile(BuildContext context, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
