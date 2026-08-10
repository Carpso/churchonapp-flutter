import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'church_invite_screen.dart';
import 'finance_dashboard_screen.dart';
import 'member_management_screen.dart';
import 'service_report_screen.dart';
import 'live_viewer_heatmap_screen.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';

class BishopDashboardScreen extends ConsumerStatefulWidget {
  const BishopDashboardScreen({super.key});

  @override
  ConsumerState<BishopDashboardScreen> createState() => _BishopDashboardScreenState();
}

class _BishopDashboardScreenState extends ConsumerState<BishopDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  int _branchCount = 0;
  int _totalAttendance = 0;
  int _lastMonthAttendance = 0;
  double _totalTithes = 0;
  int _totalMembers = 0;
  List<Map<String, dynamic>> _branches = [];
  List<HierarchyNode> _presbyteries = [];
  List<Map<String, dynamic>> _missions = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    final profile = ref.read(profileProvider).value;
    if (profile == null) {
      setState(() {
        _isLoading = false;
        _error = "Profile not found";
      });
      return;
    }

    final tenantId = profile.tenantId;
    final orgId = profile.organizationId;

    if (tenantId == null && orgId == null) {
      setState(() {
        _isLoading = false;
        _error = "No oversight jurisdiction assigned";
      });
      return;
    }
    try {
      final client = Supabase.instance.client;
      final orgSvc = ref.read(organizationServiceProvider);

      if (orgId != null && orgId.isNotEmpty) {
        // GLOBAL EXECUTIVE MODE: Aggregate stats across entire organization (server-side RPC)
        final stats = await orgSvc.getOrganizationStats(orgId);

        // Hierarchy nodes (Presbyteries) — bounded tree lookup
        final nodes = await orgSvc.getOrganizationNodes(orgId);
        final presbyteries = nodes.where((n) => n.parentNodeId != null && n.tenantId == null).toList();

        // Bounded branches list (top 50, newest first) — avoids unbounded fetch + IN-clause
        final branchesRes = await client
            .from('churches')
            .select('id, name, created_at')
            .eq('organization_id', orgId)
            .order('created_at', ascending: false)
            .limit(50);

        // Network-wide missions via single server-side RPC (replaces client IN-clause scan)
        final missionsRes = await orgSvc.getOrganizationMissions(orgId);

        if (mounted) {
          setState(() {
            _branchCount = (stats['branches'] as num?)?.toInt() ?? 0;
            _totalAttendance = (stats['members'] as num?)?.toInt() ?? 0;
            _totalTithes = (stats['monthly_giving'] as num?)?.toDouble() ?? 0;
            _totalMembers = (stats['members'] as num?)?.toInt() ?? 0;
            _branches = List<Map<String, dynamic>>.from(branchesRes as List);
            _missions = missionsRes;
            _presbyteries = presbyteries;
            _isLoading = false;
            _error = null;
          });
        }
      } else {
        // LOCAL BISHOP MODE: Single tenant oversight
        // Single server-side call replaces 4 parallel unbounded scans (attendance x2,
        // transactions, profiles) and a broken last-month attendance query.
        final stats = await orgSvc.getChurchMonthlyStats(tenantId!);

        // Bounded branch list (just this church)
        final branchesRes = await client
            .from('tenants')
            .select('id, name, created_at')
            .eq('id', tenantId);

        // Bounded missions list
        final missionsRes = await client
            .from('missions')
            .select('id, title, status')
            .eq('tenant_id', tenantId)
            .order('created_at', ascending: false)
            .limit(5);

        if (mounted) {
          setState(() {
            _branchCount = (branchesRes as List).length;
            _totalAttendance = (stats['attendance_mtd'] as num?)?.toInt() ?? 0;
            _lastMonthAttendance = (stats['attendance_previous'] as num?)?.toInt() ?? 0;
            _totalTithes = (stats['tithes_mtd'] as num?)?.toDouble() ?? 0;
            _totalMembers = (stats['members'] as num?)?.toInt() ?? 0;
            _branches = List<Map<String, dynamic>>.from(branchesRes);
            _missions = List<Map<String, dynamic>>.from(missionsRes);
            _isLoading = false;
            _error = null;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.read(profileProvider).value;
    final role = profile?.role ?? '';
    final isApostle = role == 'apostle';
    final title = isApostle ? "Apostle Dashboard" : "Bishop Dashboard";
    final headerTitle = isApostle ? "Network Oversight" : "Apostolic Oversight";

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _isLoading ? null : _loadDashboard,
          ),
        ],
      ),
      body: _isLoading
          ? _buildShimmer()
          : _error != null
              ? _buildErrorView()
              : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(25),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildHeader(theme, headerTitle),
                  const SizedBox(height: 25),
                  _buildStatsGrid(theme),
                  const SizedBox(height: 35),
                  if (_presbyteries.isNotEmpty) ...[
                    Text("Regional Presbyteries", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 15),
                    ..._presbyteries.map((p) => _buildPresbyteryRow(theme, p)),
                    const SizedBox(height: 35),
                  ],
                  Text("All Branches", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 15),
                  ..._branchCount > 0 ? _branches.map((b) => _buildBranchRow(theme, b, context)) : [_emptyCard(theme, "No branches found")],
                  if (_missions.isNotEmpty) ...[
                    const SizedBox(height: 35),
                    Text("Active Missions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 15),
                    ..._missions.map((m) => _buildMissionRow(theme, m)),
                  ],
                  const SizedBox(height: 35),
                  Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 15),
                  _quickAction(theme, LucideIcons.fileText, "Pastor Reports", "Review weekly reports from branches", Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ServiceReportScreen()))),
                  _quickAction(theme, LucideIcons.map, "Map", "Geographic view of all branches", Colors.amber, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveViewerHeatmapScreen()))),
                  _quickAction(theme, LucideIcons.barChart3, "Central Treasury", "Multi-branch financial oversight", Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FinanceDashboardScreen()))),
                  _quickAction(theme, LucideIcons.users, "Clergy Management", "Manage pastors and ministry leaders", Colors.purple, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MemberManagementScreen()))),
                  _quickAction(theme, LucideIcons.userPlus, "Invite Members", "Share invite link, QR & quick share", Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChurchInviteScreen()))),
                  const SizedBox(height: 100),
                ]),
              ),
            ),
    );
  }

  Widget _buildShimmer() => SingleChildScrollView(
    padding: const EdgeInsets.all(25),
    child: Column(children: [
      ShimmerLoader.rectangular(height: 140, width: double.infinity),
      const SizedBox(height: 20), Row(children: [Expanded(child: ShimmerLoader.rectangular(height: 100)), const SizedBox(width: 12), Expanded(child: ShimmerLoader.rectangular(height: 100))]),
      const SizedBox(height: 12), Row(children: [Expanded(child: ShimmerLoader.rectangular(height: 100)), const SizedBox(width: 12), Expanded(child: ShimmerLoader.rectangular(height: 100))]),
      const SizedBox(height: 12), Row(children: [Expanded(child: ShimmerLoader.rectangular(height: 100)), const SizedBox(width: 12), Expanded(child: ShimmerLoader.rectangular(height: 100))]),
    ]),
  );

  Widget _buildErrorView() => AppErrorView(error: _error, onRetry: _loadDashboard);

  Widget _buildHeader(ThemeData theme, String headerTitle) {
    final attGrowth = _lastMonthAttendance > 0 ? ((_totalAttendance - _lastMonthAttendance) / _lastMonthAttendance * 100).round() : 0;
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)), child: const Icon(LucideIcons.globe, color: Colors.white, size: 30)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(headerTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
          Text("$_branchCount branches • $attGrowth% growth", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w500)),
        ])),
      ]),
    );
  }

  Widget _buildStatsGrid(ThemeData theme) {
    final currency = NumberFormat.compactCurrency(symbol: 'K');
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.2,
      children: [
        _statCard("Branches", "$_branchCount", LucideIcons.building, Colors.indigo),
        _statCard("Attendance", _formatCompact(_totalAttendance), LucideIcons.calendarCheck, Colors.green),
        _statCard("Tithes (MTD)", currency.format(_totalTithes), LucideIcons.church, Colors.purple),
        _statCard("Total Members", _formatCompact(_totalMembers), LucideIcons.users, Colors.blue),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPresbyteryRow(ThemeData theme, HierarchyNode p) {
    return GestureDetector(
      onTap: () => _showPresbyteryDrilldown(p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(LucideIcons.map, color: theme.primaryColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  FutureBuilder<Map<String, dynamic>>(
                    future: ref.read(organizationServiceProvider).getNodeAggregatedStats(p.id),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox.shrink();
                      final stats = snapshot.data!;
                      return Text(
                        "${stats['branches']} branches • K${NumberFormat.compact().format(stats['giving'])} MTD",
                        style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11),
                      );
                    },
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          ],
        ),
      ),
    );
  }

  void _showPresbyteryDrilldown(HierarchyNode p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.all(15), height: 5, width: 40, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            Padding(
              padding: const EdgeInsets.all(25),
              child: Row(
                children: [
                  Icon(LucideIcons.map, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 15),
                  Text(p.name.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<HierarchyNode>>(
                future: ref.read(organizationServiceProvider).getChildrenNodes(p.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  final branches = snapshot.data ?? [];
                  if (branches.isEmpty) return const Center(child: Text("No branches found in this presbytery."));
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    itemCount: branches.length,
                    itemBuilder: (context, index) {
                      final b = branches[index];
                      return ListTile(
                        leading: const Icon(LucideIcons.church, size: 18),
                        title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text("Verified Branch"),
                        trailing: const Icon(LucideIcons.chevronRight, size: 16),
                        onTap: () {
                          // TODO: Detailed branch view
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchRow(ThemeData theme, Map<String, dynamic> branch, BuildContext context) {
    final name = branch['name'] as String? ?? 'Unnamed';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(LucideIcons.church, color: theme.primaryColor, size: 18)),
          const SizedBox(width: 14),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          Icon(LucideIcons.chevronRight, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
        ],
      ),
    );
  }

  Widget _buildMissionRow(ThemeData theme, Map<String, dynamic> mission) {
    final title = mission['title'] as String? ?? 'Unnamed Mission';
    final status = mission['status'] as String? ?? 'unknown';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)]),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(LucideIcons.map, color: Colors.amber, size: 18)),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: status == 'active' ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: status == 'active' ? Colors.green : Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _quickAction(ThemeData theme, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
        ])),
        Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
      ]),
    ),
  );

  Widget _emptyCard(ThemeData theme, String msg) => Container(
    width: double.infinity, padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(20)),
    child: Center(child: Text(msg, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4)))),
  );

  String _formatCompact(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : n.toString();
}
