import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'member_management_screen.dart';
import 'baptism_registry_screen.dart';
import 'media_upload_screen.dart';
import 'global_broadcast_screen.dart';
import 'bookshop_dashboard_screen.dart';
import 'writer_dashboard_screen.dart';
import 'driver_dashboard_screen.dart';
import 'rider_dashboard_screen.dart';
import 'event_scheduler_screen.dart';
import 'live_viewer_heatmap_screen.dart';
import 'logistics_dashboard_screen.dart';
import 'church_branding_screen.dart';
import 'pastoral_followup_screen.dart';
import 'member_directory_screen.dart';
import 'kyc_review_screen.dart';
import 'news_management_screen.dart';
import 'radio_station_management_screen.dart';
import '../../../features/modules/crm_donor_management/presentation/crm_donor_screen.dart';
import '../../../features/modules/volunteer_scheduling/presentation/volunteer_scheduling_screen.dart';
import '../../../features/data_import/presentation/data_import_screen.dart';

import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/admin/presentation/widgets/admin_navigation_registry.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/stats_provider.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';
import 'package:church_on_app/features/finance/data/tithe_automation_service.dart';

class AdminHubScreen extends ConsumerWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);
    final profileAsync = ref.watch(profileProvider);
    final tenant = ref.watch(currentTenantProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null || !profile.isLeadershipTeam) {
          return const SizedBox.shrink();
        }
        return _buildScreen(context, ref, statsAsync, profile, tenant);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        body: ErrorRetryWidget(
          message: "Failed to load profile",
          onRetry: () => ref.invalidate(profileProvider),
        ),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, WidgetRef ref, AsyncValue<AdminStats> statsAsync, UserProfile profile, Tenant? tenant) {
    final role = profile.role;
    final isLeadership = profile.isLeadershipTeam;
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
              data: (stats) {
                final isCoaTeam = profile.isSuperadmin || profile.role == 'coa_employee' || profile.role == 'employee';
                return _buildStatGridFor(context, stats, isCoaTeam);
              },
              loading: () => GridView.count(
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
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.users,
                "Member Management",
                "Track your flock, verify baptisms & attendance",
                theme.primaryColor,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MemberManagementScreen())),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.award,
                "Baptism Registry",
                "Official records, dates, and baptism certificates",
                theme.primaryColor,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BaptismRegistryScreen())),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.church,
                "Ministries",
                "Manage ministry groups, leaders, and schedules",
                Colors.amber,
                 () => context.push('/ministry-management'),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.calendarClock,
                "Service Schedule",
                "Set weekly service days & Carpso Ride prompts",
                theme.primaryColor,
                () => context.push('/church-schedule'),
              ),
            if (role == 'bookshop_owner' || role == 'store_manager' || role == 'cashier' || role == 'assistant')
              _buildAdminTile(
                context,
                LucideIcons.bookOpen,
                "Bookshop Dashboard",
                "Manage inventory, digital products and sales",
                Colors.orange,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BookshopDashboardScreen())),
              ),
            if (role == 'writer' || role == 'author')
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
                theme.primaryColor,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverDashboardScreen())),
              ),
            if (role == 'rider')
              _buildAdminTile(
                context,
                LucideIcons.map,
                "Rider Dashboard",
                "Trip history, stats and saved places",
                theme.primaryColor,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RiderDashboardScreen())),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.video,
                "Live Studio",
                "Connect to Prophetic Hub & start church-wide broadcast",
                Colors.red,
                 () => context.push('/live-studio'),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.uploadCloud,
                "Media Hub (R2)",
                "Upload sermons, trailers & Klips",
                Colors.orange,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MediaUploadScreen())),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.barChart3,
                "Ministry Reports",
                "Service dashboard, attendance & offerings",
                Colors.teal,
                () => context.push('/service-report'),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.bookOpen,
                "Finance Dashboard",
                "Professional ledger — trends, distribution, payouts & HQ remittance",
                Colors.indigo,
                () => context.push('/finance-dashboard'),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.paintbrush,
                "Flyer Studio",
                "Design visual announcement templates for events",
                Colors.amber,
                 () => context.push('/flyer-studio'),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.image,
                "Church Branding",
                "Set your hero banner & logo shown on the home screen",
                Colors.purple,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ChurchBrandingScreen())),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.globe,
                "Church Website",
                "Build & publish your public website (churchonapp.com/c/...)",
                Colors.teal,
                () => context.push('/church-website/${tenant?.id ?? ''}'),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.heartHandshake,
                "Pastoral Follow-ups",
                "Log visits, calls & WhatsApp check-ins with members",
                Colors.deepOrange,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PastoralFollowupScreen())),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.megaphone,
                "Global Broadcast",
                "Send push notifications & church-wide alerts",
                theme.primaryColor,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GlobalBroadcastScreen())),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.calendarDays,
                "Event Scheduling",
                "Coordinate services, missions & conferences",
                Colors.red,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const EventSchedulerScreen())),
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
            if (role == 'admin' || role == 'pastor' || role == 'treasurer')
              _buildAdminTile(
                context,
                LucideIcons.truck,
                "Logistics Command",
                "Monitor church bus trips, routes & deliveries",
                Colors.amber,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LogisticsDashboardScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.map,
                "Member Live Heatmap",
                "See where members are watching from",
                Colors.redAccent,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveViewerHeatmapScreen())),
              ),
            Divider(height: 30, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
            Text("Ministry Tools", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 20),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle' || role == 'treasurer')
              _buildAdminTile(
                context,
                LucideIcons.contact,
                "Member Directory",
                "Browse every member of the church",
                theme.primaryColor,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberDirectoryScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle' || role == 'coa_employee')
              _buildAdminTile(
                context,
                LucideIcons.fingerprint,
                "KYC Review",
                "Verify member identity verifications",
                Colors.orange,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KycReviewScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle' || role == 'treasurer')
              _buildAdminTile(
                context,
                LucideIcons.heartHandshake,
                "CRM Donors",
                "Manage donor relationships & giving insights",
                Colors.teal,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => CRMDonorScreen(tenantId: tenant?.id ?? ''))),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.newspaper,
                "News Management",
                "Publish & manage church news articles",
                Colors.orange,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewsManagementScreen())),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.radio,
                "Radio Stations",
                "Manage church radio stations & streams",
                Colors.redAccent,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RadioStationManagementScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle' || role == 'employee' || role == 'coa_employee')
              _buildAdminTile(
                context,
                LucideIcons.fileUp,
                "Data Import",
                "Bulk import members, transactions & events",
                Colors.green,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataImportScreen())),
              ),
            if (isLeadership)
              _buildAdminTile(
                context,
                LucideIcons.calendarCheck,
                "Volunteer Schedule",
                "Plan volunteer shifts & roles",
                Colors.purple,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => VolunteerSchedulingScreen(tenantId: tenant?.id ?? ''))),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle' || role == 'treasurer')
              _buildAdminTile(
                context,
                LucideIcons.bellRing,
                "Tithe Reminders",
                "SMS reminders to members who haven't tithed",
                Colors.brown,
                () => _sendTitheReminders(context, ref),
              ),
          ],
        ),
      ),
    );
}

  Future<void> _sendTitheReminders(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Send Tithe Reminders"),
        content: const Text(
            "Send SMS reminders to all members who haven't tithed this month? This may use SMS credits."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Send")),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(titheAutomationServiceProvider).sendMonthlyReminders();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Tithe reminders sent!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed: ${e.toString().replaceFirst('Exception: ', '')}"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ignore: unused_element
  Widget _buildStatGrid(BuildContext ctx, AdminStats stats) {
    // Legacy entry — defaults to tenant view (Fleet Buses). COA view uses _buildStatGridFor.
    return _buildStatGridFor(ctx, stats, false);
  }

  Widget _buildStatGridFor(BuildContext ctx, AdminStats stats, bool isCoaTeam) {
    final theme = Theme.of(ctx);
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 2,
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(theme, "Total Members", stats.totalMembers.toString(), LucideIcons.users, theme.primaryColor.withValues(alpha: 0.7)),
        _buildStatCard(theme, "Active Missions", stats.totalMissions.toString(), LucideIcons.zap, Colors.amber),
        _buildStatCard(theme, "Monthly Revenue", stats.recentGiving, LucideIcons.heartPulse, Colors.red),
        _buildStatCard(theme, isCoaTeam ? "Active Couriers" : "Fleet Buses", stats.activeCouriers.toString(), isCoaTeam ? LucideIcons.truck : LucideIcons.bus, Colors.green),
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
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
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

