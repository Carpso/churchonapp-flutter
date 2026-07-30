import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'member_management_screen.dart';
import 'baptism_registry_screen.dart';
import 'media_upload_screen.dart';
import 'package:church_on_app/features/modules/live_streaming/presentation/live_stream_studio_screen.dart';
import 'global_broadcast_screen.dart';
import 'bookshop_dashboard_screen.dart';
import 'writer_dashboard_screen.dart';
import 'driver_dashboard_screen.dart';
import 'rider_dashboard_screen.dart';
import 'event_scheduler_screen.dart';
import 'live_viewer_heatmap_screen.dart';
import 'logistics_dashboard_screen.dart';
import 'prophetic_heatmap_screen.dart';
import 'flyer_studio_screen.dart';
import 'ministry_management_screen.dart';

import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/admin/presentation/widgets/admin_navigation_registry.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/stats_provider.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/tenant_service.dart';

class AdminHubScreen extends ConsumerWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);
    final profileAsync = ref.watch(profileProvider);
    final tenant = ref.watch(currentTenantProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null || !profile.isTenantAdmin) {
          return const SizedBox.shrink();
        }
        return _buildScreen(context, ref, statsAsync, profile, tenant);
      },
      loading: () => Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        body: Center(child: Text('Error loading profile: $e')),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, WidgetRef ref, AsyncValue<AdminStats> statsAsync, UserProfile profile, Tenant? tenant) {
    final role = profile.role;
    final churchName = tenant?.name ?? 'Church';

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Admin Hub", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, fontSize: 20)),
            Text("ADMIN - $churchName", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: theme.colorScheme.primary, letterSpacing: 0.8)),
          ],
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            statsAsync.when(
              data: (stats) => _buildStatGrid(context, stats),
              loading: () => GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                childAspectRatio: 1.5,
                children: List.generate(4, (_) => const ShimmerLoader.rectangular(height: 100)),
              ),
              error: (e, s) => const Center(child: Text("Error loading stats")),
            ),
            const SizedBox(height: 40),
            Text("Management Console", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 20),
            // Tenant-scoped features only - no SuperAdmin/Employee features
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.users,
                "Member Management",
                "Track your flock, verify baptisms & attendance",
                Colors.blue,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MemberManagementScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.award,
                "Baptism Registry",
                "Official records, dates, and baptism certificates",
                Colors.indigo,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BaptismRegistryScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.church,
                "Ministries",
                "Manage ministry groups, leaders, and schedules",
                Colors.amber,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MinistryManagementScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle' || role == 'bookshop_owner' || role == 'vendor' || role == 'merchant')
              _buildAdminTile(
                context,
                LucideIcons.bookOpen,
                "Bookshop Dashboard",
                "Manage inventory, digital products and sales",
                Colors.orange,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BookshopDashboardScreen())),
              ),
            if (role == 'admin' || role == 'writer' || role == 'author')
              _buildAdminTile(
                context,
                LucideIcons.feather,
                "Writer Dashboard",
                "Manage articles, books, and publishing",
                Colors.amber,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WriterDashboardScreen())),
              ),
            if (role == 'driver')
              _buildAdminTile(
                context,
                LucideIcons.truck,
                "Driver Dashboard",
                "Ride history, earnings, and deliveries",
                Colors.blue,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverDashboardScreen())),
              ),
            if (role == 'rider')
              _buildAdminTile(
                context,
                LucideIcons.map,
                "Rider Dashboard",
                "Trip history, stats and saved places",
                Colors.teal,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RiderDashboardScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.video,
                "Live Studio",
                "Connect to Prophetic Hub & start church-wide broadcast",
                Colors.red,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveStreamStudioScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.uploadCloud,
                "Media Hub (R2)",
                "Upload sermons, trailers & Klips",
                Colors.orange,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MediaUploadScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.paintbrush,
                "Flyer Studio",
                "Design visual announcement templates for events",
                Colors.amber,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FlyerStudioScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.megaphone,
                "Global Broadcast",
                "Send push notifications & church-wide alerts",
                Colors.purple,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GlobalBroadcastScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.calendarDays,
                "Event Scheduling",
                "Coordinate services, missions & conferences",
                Colors.red,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const EventSchedulerScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.map,
                "Member Live Heatmap",
                "See where members are watching from",
                Colors.redAccent,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveViewerHeatmapScreen())),
              ),
            Divider(height: 30, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
            ...AdminNavigationRegistry.buildAccessibleTiles(
              context,
              isSuperadmin: false,
              isPastor: role == 'pastor',
              isBishop: role == 'bishop',
              isTreasurer: role == 'treasurer',
            ),
            Divider(height: 30, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
            Text("Logistics & Finance", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 20),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle' || role == 'treasurer')
              _buildAdminTile(
                context,
                LucideIcons.truck,
                "Logistics Command",
                "Monitor real-time rides, cargo & couriers",
                Colors.amber,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LogisticsDashboardScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.map,
                "Prophetic Heatmap",
                "Strategic expansion and mission planning",
                Colors.redAccent,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PropheticHeatmapScreen())),
              ),
          ],
        ),
      ),
    );
}

  Widget _buildStatGrid(BuildContext ctx, AdminStats stats) {
    final theme = Theme.of(ctx);
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(theme, "Total Members", stats.totalMembers.toString(), LucideIcons.users, Colors.blue),
        _buildStatCard(theme, "Active Missions", stats.totalMissions.toString(), LucideIcons.zap, Colors.amber),
        _buildStatCard(theme, "Monthly Revenue", stats.recentGiving, LucideIcons.heartPulse, Colors.red),
        _buildStatCard(theme, "Active Couriers", stats.activeCouriers.toString(), LucideIcons.truck, Colors.green),
      ],
    );
  }

  Widget _buildStatCard(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildAdminTile(BuildContext context, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Semantics(
      label: "$title, $subtitle",
      button: true,
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                  Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
    ),
    );
  }
}

