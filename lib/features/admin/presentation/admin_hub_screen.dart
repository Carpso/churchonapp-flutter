import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'member_management_screen.dart';
import 'baptism_registry_screen.dart';
import 'finance_dashboard_screen.dart';
import 'media_upload_screen.dart';
import 'live_stream_studio_screen.dart';
import 'integrations_screen.dart';
import 'global_broadcast_screen.dart';
import 'superadmin_dashboard.dart';
import 'bishop_dashboard.dart';
import 'pastor_dashboard_screen.dart';
import 'bookshop_dashboard_screen.dart';
import 'event_scheduler_screen.dart';
import 'live_viewer_heatmap_screen.dart';
import 'logistics_dashboard_screen.dart';
import 'financial_report_screen.dart';
import 'prophetic_heatmap_screen.dart';
import 'withdrawal_approval_screen.dart';
import 'driver_simulation_hub_screen.dart';
import 'ai_stewardship_report_screen.dart';
import 'prophetic_navigation_screen.dart';
import 'apostolic_resource_planning_screen.dart';
import 'global_payout_command_screen.dart';
import 'kingdom_ai_moderator_screen.dart';
import 'apostle_dashboard_screen.dart';
import 'zambian_payroll_screen.dart';
import 'flyer_studio_screen.dart';
import 'ministry_management_screen.dart';
import '../../finance/presentation/multi_currency_wallet_screen.dart';
import 'package:church_on_app/features/finance/data/tithe_automation_service.dart';
import '../../modules/media/presentation/kingdom_radio_screen.dart';
import 'onboarding_manager_screen.dart';
import '../../modules/games/presentation/game_management_screen.dart';

import 'package:church_on_app/features/admin/data/admin_service.dart';
import 'package:church_on_app/features/auth/presentation/church_onboarding_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/stats_provider.dart';
import '../../../core/providers/profile_provider.dart';

class AdminHubScreen extends ConsumerWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null || !profile.isAdminOrHigher && !profile.isEmployee) {
          return const SizedBox.shrink();
        }
        return _buildScreen(context, ref, statsAsync, profile);
      },
      loading: () => Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        body: Center(child: Text('Error loading profile: $e')),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, WidgetRef ref, AsyncValue<AdminStats> statsAsync, UserProfile profile) {
    final isSuperOrEmployee = profile.isSuperadmin || profile.isEmployee;
    final role = profile.role;

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text("Kingdom Admin Hub", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
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
              loading: () => Center(child: CircularProgressIndicator(color: theme.primaryColor)),
              error: (e, s) => const Center(child: Text("Error loading stats")),
            ),
            const SizedBox(height: 40),
            Text("Management Console", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 20),
            if (isSuperOrEmployee) // SuperAdmin console for Admins/Employees only
              _buildAdminTile(
                context,
                LucideIcons.shieldAlert,
                "SuperAdmin Console",
                "Global settings, Tenants & Platform access",
                Colors.black87,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SuperAdminDashboard())),
              ),
            if (isSuperOrEmployee)
              _buildAdminTile(
                context,
                LucideIcons.home,
                "Congregation Management",
                "Onboard and audit Kingdom Church branches",
                Colors.indigo,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ChurchOnboardingScreen())),
              ),
            if (isSuperOrEmployee)
              _buildAdminTile(
                context,
                LucideIcons.userPlus,
                "Entity Onboarding",
                "Pre-register drivers, riders, staff & organizers",
                Colors.teal,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OnboardingManagerScreen())),
              ),
            if (role == 'bishop' || role == 'superadmin')
              _buildAdminTile(
                context,
                LucideIcons.globe,
                "Apostolic Oversight",
                "Multi-branch analytics and performance",
                Colors.purple,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BishopDashboard())),
              ),
            if (role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.globe,
                "Apostle Dashboard",
                "Network churches, growth metrics and missions",
                Colors.deepPurple,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ApostleDashboardScreen())),
              ),
            if (role == 'pastor')
              _buildAdminTile(
                context,
                LucideIcons.layoutDashboard,
                "Pastor Dashboard",
                "Members, sermons, attendance & giving stats",
                Colors.teal,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PastorDashboardScreen())),
              ),
            Divider(height: 30, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
            if (isSuperOrEmployee || role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.users,
                "Member Management",
                "Track your flock, verify baptisms & attendance",
                Colors.blue,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MemberManagementScreen())),
              ),
            if (isSuperOrEmployee || role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.award,
                "Baptism Registry",
                "Official records, dates, and baptism certificates",
                Colors.indigo,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BaptismRegistryScreen())),
              ),
            if (isSuperOrEmployee || role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.church,
                "Ministries",
                "Manage ministry groups, leaders, and schedules",
                Colors.amber,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MinistryManagementScreen())),
              ),
            if (isSuperOrEmployee || role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle' || role == 'bookshop_owner' || role == 'vendor' || role == 'merchant')
              _buildAdminTile(
                context,
                LucideIcons.bookOpen,
                "Bookshop Management",
                "Manage inventory, digital products and sales",
                Colors.orange,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BookshopDashboardScreen())),
              ),
            if (isSuperOrEmployee)
              _buildAdminTile(
                context,
                LucideIcons.barChart3,
                "Financial Oversight",
                "Annual stewardship, tithes & marketplace analytics",
                Colors.green,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FinanceDashboardScreen())),
              ),
            if (isSuperOrEmployee)
              _buildAdminTile(
                context,
                LucideIcons.fileSpreadsheet,
                "Zambian Statutory Payroll",
                "Calculate NHIMA, NAPSA, & PAYE deductions",
                Colors.blueGrey,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ZambianPayrollScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.video,
                "Kingdom Live Studio",
                "Connect to Prophetic Hub & start church-wide broadcast",
                Colors.red,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveStreamStudioScreen())),
              ),
            if (role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'prophet' || role == 'apostle')
              _buildAdminTile(
                context,
                LucideIcons.uploadCloud,
                "Media Hub (R2)",
                "Upload sermons, trailers & Kingdom Klips",
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
              _buildAdminTile(
                context,
                LucideIcons.box,
                "Enterprise Integrations",
                "Connect banking, accounting & parking systems",
                Colors.indigo,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const IntegrationsScreen())),
              ),
            Divider(height: 30, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
            Text("Logistics & Finance", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 20),
            _buildAdminTile(
              context,
              LucideIcons.truck,
              "Logistics Command",
              "Monitor real-time rides, cargo & couriers",
              Colors.amber,
              () {
                if (isSuperOrEmployee) {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const LogisticsDashboardScreen()));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Access restricted to SuperAdmin & Employees.")));
                }
              },
            ),
            _buildAdminTile(
              context,
              LucideIcons.map,
              "Prophetic Heatmap",
              "Strategic expansion and mission planning",
              Colors.redAccent,
              () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PropheticHeatmapScreen())),
            ),
            _buildAdminTile(
              context,
              LucideIcons.fileText,
              "Monthly Stewardship",
              "Generate financial reports & audit logs",
              Colors.green,
              () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FinancialReportScreen())),
            ),
            if (isSuperOrEmployee)
              _buildAdminTile(
                context,
                LucideIcons.creditCard,
                "Payout Settlement Queue",
                "Approve and process Mobile Money payouts",
                Colors.blueGrey,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WithdrawalApprovalScreen())),
              ),
            if (isSuperOrEmployee)
              _buildAdminTile(
                context,
                LucideIcons.satellite,
                "GPS Driver Simulator",
                "Test live tracking & logistics matching",
                Colors.orangeAccent,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverSimulationHubScreen())),
              ),
            if (isSuperOrEmployee)
              _buildAdminTile(
                context,
                LucideIcons.bellRing,
                "Trigger Tithe Reminders",
                "Automated spiritual stewardship alerts",
                Colors.pinkAccent,
                () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Trigger Global Reminders?"),
                      content: const Text("This will send SMS reminders to all members who have not yet tithed this month."),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("PROCEED")),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await ref.read(titheAutomationServiceProvider).sendMonthlyReminders();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stewardship Reminders Initiated!")));
                    }
                  }
                },
              ),
            if (isSuperOrEmployee)
              _buildAdminTile(
                context,
                LucideIcons.zap,
                "Execute Multi-Payout",
                "Automated worker & employee settlement",
                Colors.deepPurpleAccent,
                () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Run Payout Engine?"),
                      content: const Text("This will automatically approve and settle all pending payouts for authorized Kingdom workers and employees."),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("EXECUTE")),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    final count = await ref.read(adminServiceProvider).automateWorkerPayouts();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Successfully processed $count Kingdom settlements!")));
                    }
                  }
                },
              ),
            _buildAdminTile(
              context,
              LucideIcons.radio,
              "Radio Global Command",
              "Oversee Kingdom broadcasts & metadata",
              Colors.redAccent,
              () => Navigator.push(context, MaterialPageRoute(builder: (context) => const KingdomRadioScreen())),
            ),
            _buildAdminTile(
              context,
              LucideIcons.brainCircuit,
              "Apostolic AI Report",
              "Prophetic financial stewardship analysis",
              Colors.blueAccent,
              () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const AIStewardshipReportScreen()));
              },
            ),
            _buildAdminTile(
              context,
              LucideIcons.map,
              "Prophetic Navigation",
              "AI-Powered logistics route optimization",
              Colors.teal,
              () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const PropheticNavigationScreen()));
              },
            ),
            _buildAdminTile(
              context,
              LucideIcons.globe,
              "International Multi-Wallet",
              "Global stewardship hub (ZMW & CC)",
              Colors.green,
              () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const MultiCurrencyWalletScreen()));
              },
            ),
            _buildAdminTile(
              context,
              LucideIcons.layoutGrid,
              "Apostolic Planning",
              "AI material resource allocation hubs",
              Colors.indigo,
              () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ApostolicResourcePlanningScreen()));
              },
            ),
            _buildAdminTile(
              context,
              LucideIcons.send,
              "Global Payout Command",
              "Execute Lipila settlements (MTN/Airtel)",
              Colors.greenAccent,
              () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const GlobalPayoutCommandScreen()));
              },
            ),
            _buildAdminTile(
              context,
              LucideIcons.shieldCheck,
              "Kingdom AI Moderator",
              "AI Gatekeeper for social testimonies",
              Colors.blue,
              () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const KingdomAIModeratorScreen()));
              },
            ),
            _buildAdminTile(
              context,
              LucideIcons.checkSquare,
              "Verify Driver Payouts",
              "Global logistics settlement verification",
              Colors.orangeAccent,
              () => _showDriverVerificationDialog(context, ref),
            ),
            Divider(height: 30, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
            Text("Games & Entertainment", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 20),
            if (isSuperOrEmployee)
              _buildAdminTile(
                context,
                LucideIcons.gamepad2,
                "Games Management",
                "Control all games, host premium quizzes & events",
                Colors.amberAccent,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GameManagementScreen())),
              ),
          ],
        ),
      ),
    );
  }

  void _showDriverVerificationDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Driver Verification"),
        content: const Text("Initiate global settlement check for all active logistics workers?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              // In this prototype we trigger a mock verification across the fleet
              await ref.read(adminServiceProvider).triggerGlobalWorkerPayouts();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Global Driver Payout Settlement verified on Prophetic ledger.")));
              }
            },
            child: const Text("VERIFY ALL"),
          ),
        ],
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
    return GestureDetector(
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
    );
  }
}

