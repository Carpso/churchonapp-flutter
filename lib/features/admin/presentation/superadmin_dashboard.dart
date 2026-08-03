import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'coa_employee_dashboard.dart';
import 'member_management_screen.dart';
import 'finance_dashboard_screen.dart';
import 'event_scheduler_screen.dart';
import 'logistics_dashboard_screen.dart';
import 'withdrawal_approval_screen.dart';
import 'global_payout_command_screen.dart';
import 'zambian_payroll_screen.dart';
import 'zambian_compliance_dashboard.dart';
import 'employee_management_screen.dart';
import 'payroll_processing_screen.dart';
import 'payroll_reports_screen.dart';
import 'ad_management_screen.dart';
import 'manage_partners_screen.dart';
import 'role_approval_screen.dart';
import 'writer_approval_screen.dart';
import 'kyc_review_screen.dart';
import 'carpso_driver_approval_screen.dart';
import 'driver_simulation_hub_screen.dart';
import 'export_data_screen.dart';
import 'database_setup_screen.dart';
import 'live_viewer_heatmap_screen.dart';
import 'emergency_shutdown_screen.dart';
import 'kingdom_ai_moderator_screen.dart';
import 'promo_campaign_screen.dart';
import 'reward_management_screen.dart';
import 'integrations_screen.dart';
import 'subscription_pricing_screen.dart';
import 'tenant_lease_management_screen.dart';
import 'unified_financial_audit_screen.dart';
import 'system_security_panel_screen.dart';
final _superStatsProvider = FutureProvider((ref) async {
  final client = Supabase.instance.client;
  try {
    final tenantsRes = await client.from('tenants').select('id, type, created_at');
    final profilesRes = await client.from('profiles').select('id, role');
    final churchesRes = await client.from('churches').select('id, is_verified');
    final txsRes = await client.from('transactions').select('amount, platform_fee');

    final activeChurches = (churchesRes as List).where((c) => c['is_verified'] == true).length;
    final pendingChurches = (churchesRes as List).where((c) => c['is_verified'] == false).length;
    final totalUsers = profilesRes.length;

    double revenue = 0;
    double platformFees = 0;
    for (final t in txsRes) {
      revenue += (t['amount'] as num?)?.toDouble() ?? 0;
      platformFees += (t['platform_fee'] as num?)?.toDouble() ?? 0;
    }

    return _SuperStats(
      tenants: (tenantsRes as List).length,
      activeChurches: activeChurches,
      pendingChurches: pendingChurches,
      totalUsers: totalUsers,
      revenue: revenue,
      platformFees: platformFees,
    );
  } catch (e) {
    debugPrint('SuperAdmin stats error: $e');
    rethrow;
  }
});

class _SuperStats {
  final int tenants;
  final int activeChurches;
  final int pendingChurches;
  final int totalUsers;
  final double revenue;
  final double platformFees;
  const _SuperStats({required this.tenants, required this.activeChurches, required this.pendingChurches, required this.totalUsers, required this.revenue, required this.platformFees});
}

class SuperAdminDashboard extends ConsumerWidget {
  const SuperAdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(_superStatsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("SuperAdmin Console", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: statsAsync.when(
        data: (stats) => SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGlobalBanner(theme, stats),
              const SizedBox(height: 30),
              _buildStatsGrid(theme, stats),
              const SizedBox(height: 35),
              Text("Platform Management", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 20),
              ..._buildManagementTiles(context, theme),
              const SizedBox(height: 35),
              Text("Danger Zone", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
              const SizedBox(height: 20),
              _buildDangerTiles(context, theme),
              const SizedBox(height: 40),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.wifiOff, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text("Could not load stats", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(e.toString(), style: const TextStyle(color: Colors.grey, fontSize: 10), textAlign: TextAlign.center),
            ],
          ),
        )),
      ),
    );
  }

  Widget _buildGlobalBanner(ThemeData theme, _SuperStats stats) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700, Colors.red.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.red.shade200.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
                child: const Icon(LucideIcons.shield, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Global Systems Live", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.greenAccent)),
                        const SizedBox(width: 6),
                        Text("All Sub-Tenants and DBs Operational", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _bannerStat("${stats.activeChurches}", "Active Churches"),
              _bannerStat("${stats.pendingChurches}", "Pending"),
              _bannerStat(_formatCompact(stats.totalUsers), "Users"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10)),
      ],
    );
  }

  Widget _buildStatsGrid(ThemeData theme, _SuperStats stats) {
    final currencyFormat = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: 1.3,
      children: [
        _statCard(theme, "Tenants", "${stats.tenants}", LucideIcons.building, Colors.indigo),
        _statCard(theme, "Total Users", _formatCompact(stats.totalUsers), LucideIcons.users, Colors.blue),
        _statCard(theme, "Platform Revenue", currencyFormat.format(stats.platformFees), LucideIcons.banknote, Colors.green),
        _statCard(theme, "Transaction Volume", currencyFormat.format(stats.revenue), LucideIcons.heartPulse, Colors.red),
      ],
    );
  }

  Widget _statCard(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 10)),
        ],
      ),
    );
  }

  List<Widget> _buildManagementTiles(BuildContext context, ThemeData theme) {
    return [
      _tile(context, theme, LucideIcons.home, "Congregation Management", "Onboard and audit Church branches", Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoaEmployeeDashboard()))),
      _tile(context, theme, LucideIcons.users, "Member Management", "Track your flock, verify baptisms & attendance", Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberManagementScreen()))),
      _tile(context, theme, LucideIcons.barChart3, "Financial Oversight", "Annual stewardship, tithes & marketplace analytics", Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceDashboardScreen()))),
      _tile(context, theme, LucideIcons.calendarDays, "Event Scheduling", "Coordinate services, missions & conferences", Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EventSchedulerScreen()))),
      _tile(context, theme, LucideIcons.truck, "Logistics Command", "Monitor real-time rides, cargo & couriers", Colors.amber, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogisticsDashboardScreen()))),
      _tile(context, theme, LucideIcons.creditCard, "Payout Settlement", "Approve and process Mobile Money payouts", Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WithdrawalApprovalScreen()))),
      _tile(context, theme, LucideIcons.send, "Global Payout Command", "Execute Lipila settlements (MTN/Airtel)", Colors.greenAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalPayoutCommandScreen()))),
      _tile(context, theme, LucideIcons.users, "Employee Management", "Add staff, set salaries, manage departments", Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeManagementScreen()))),
      _tile(context, theme, LucideIcons.calculator, "Payroll Processing", "Process monthly payroll with PAYE, NAPSA, NHIMA", Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayrollProcessingScreen()))),
      _tile(context, theme, LucideIcons.barChart3, "Payroll Reports", "Annual summaries, remittance schedules, compliance", Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayrollReportsScreen()))),
      _tile(context, theme, LucideIcons.fileSpreadsheet, "Zambian Statutory Payroll", "Calculate NHIMA, NAPSA, & PAYE deductions", Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ZambianPayrollScreen()))),
      _tile(context, theme, LucideIcons.clipboardCheck, "Zambian Compliance Dashboard", "ZRA, NAPSA, NHIMA, ECZ — full statutory view", Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ZambianComplianceDashboard()))),
      _tile(context, theme, LucideIcons.megaphone, "Ad Campaigns", "Manage platform ads and promotions", Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdManagementScreen()))),
      _tile(context, theme, LucideIcons.store, "Partner Management", "Manage partner tenants for coin redemption", Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagePartnersScreen()))),
      _tile(context, theme, LucideIcons.userCheck, "Role Approvals", "Approve or elevate user roles", Colors.purple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoleApprovalScreen()))),
      _tile(context, theme, LucideIcons.penTool, "Writer Approvals", "Approve writer applications", Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WriterApprovalScreen()))),
      _tile(context, theme, LucideIcons.shieldCheck, "KYC Review", "Verify user identity documents", Colors.deepOrange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KycReviewScreen()))),
      _tile(context, theme, LucideIcons.car, "Carpso Driver Approvals", "Approve driver applications for Carpso Ride", Colors.deepPurple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CarpsoDriverApprovalScreen()))),
      _tile(context, theme, LucideIcons.gift, "Promo Campaigns", "Discount codes, coin bonuses & promotions", Colors.pink, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PromoCampaignScreen()))),
      _tile(context, theme, LucideIcons.award, "Rewards & Badges", "Configure rewards, badges and coin grants", Colors.amber, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RewardManagementScreen()))),
      _tile(context, theme, LucideIcons.map, "Member Live Heatmap", "See where members are watching from", Colors.redAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveViewerHeatmapScreen()))),
      _tile(context, theme, LucideIcons.shieldCheck, "AI Moderator", "AI Gatekeeper for social testimonies", Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KingdomAIModeratorScreen()))),
      _tile(context, theme, LucideIcons.satellite, "GPS Driver Simulator", "Test live tracking & logistics matching", Colors.orangeAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverSimulationHubScreen()))),
      _tile(context, theme, LucideIcons.puzzle, "Integrations", "Configure third-party integrations", Colors.cyan, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntegrationsScreen()))),
      _tile(context, theme, LucideIcons.dollarSign, "Subscription Pricing", "Configure subscription tiers and pricing", Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionPricingScreen()))),
      _tile(context, theme, LucideIcons.database, "Database Setup", "Migration and schema management tools", Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DatabaseSetupScreen()))),
      _tile(context, theme, LucideIcons.fileDown, "Export Data", "Export platform data to CSV/PDF/Excel", Colors.brown, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportDataScreen()))),
      const SizedBox(height: 12),
      Text("Governance & Security", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
      const SizedBox(height: 10),
      _tile(context, theme, LucideIcons.building, "Tenant Lease Management", "Approve churches, extend trials, suspend tenants", Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TenantLeaseManagementScreen()))),
      _tile(context, theme, LucideIcons.barChart3, "Financial Audit Engine", "Unified view: transactions, fundraising, wallets", Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UnifiedFinancialAuditScreen()))),
      _tile(context, theme, LucideIcons.shield, "System Security Panel", "Freeze switch, audit logs, security events", Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SystemSecurityPanelScreen()))),
    ];
  }

  Widget _buildDangerTiles(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        _tile(context, theme, LucideIcons.shieldOff, "Emergency Shutdown", "Immediately disable all platform services", Colors.red, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyShutdownScreen()));
        }),
      ],
    );
  }

  Widget _tile(BuildContext context, ThemeData theme, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                  Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }

  String _formatCompact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
