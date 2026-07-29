import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'finance_dashboard_screen.dart';
import 'member_management_screen.dart';
import 'service_report_screen.dart';
import 'live_viewer_heatmap_screen.dart';
import 'package:church_on_app/features/admin/data/role_hierarchy_service.dart';

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
  double _totalGiving = 0;
  int _totalMembers = 0;
  int _missionsActive = 0;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _missions = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    final profile = ref.read(profileProvider).value;
    if (profile == null) { setState(() { _isLoading = false; _error = "Profile not found"; }); return; }

    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final firstOfLastMonth = DateTime(now.year, now.month - 1, 1);

    try {
      final client = Supabase.instance.client;

      final tenantsRes = await client
          .from('tenants')
          .select('id, name, created_at')
          .eq('type', 'church');

      final attThisMonth = await client
          .from('attendance_logs')
          .select('id, tenant_id')
          .gte('created_at', firstOfMonth.toIso8601String());

      final attLastMonth = await client
          .from('attendance_logs')
          .select('id')
          .gte('created_at', firstOfLastMonth.toIso8601String())
          .lt('created_at', firstOfMonth.toIso8601String());

      final txsRes = await client
          .from('transactions')
          .select('amount, type')
          .inFilter('type', ['tithe', 'giving'])
          .gte('created_at', firstOfMonth.toIso8601String());

      final profilesRes = await client
          .from('profiles')
          .select('tenant_id')
          .not('tenant_id', 'is', null);

      final missionsRes = await client
          .from('missions')
          .select('id, title, status')
          .limit(5);

      double tithes = 0, giving = 0;
      for (final t in txsRes) {
        final amount = (t['amount'] as num?)?.toDouble() ?? 0;
        if (t['type'] == 'tithe') { tithes += amount; } else { giving += amount; }
      }

      final branches = (tenantsRes as List).map((t) => t as Map<String, dynamic>).toList();
      final memberSet = <String>{};
      for (final p in profilesRes) {
        final tid = p['tenant_id']?.toString();
        if (tid != null) memberSet.add(tid);
      }

      if (mounted) {
        setState(() {
          _branchCount = branches.length;
          _totalAttendance = (attThisMonth as List).length;
          _lastMonthAttendance = (attLastMonth as List).length;
          _totalTithes = tithes;
          _totalGiving = giving;
          _totalMembers = memberSet.length;
          _branches = branches;
          _missions = List<Map<String, dynamic>>.from(missionsRes);
          _missionsActive = missionsRes.where((m) => m['status'] == 'active').length;
          _isLoading = false; _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = ref.read(profileProvider).value?.role ?? '';
    final isApostle = role == 'apostle';
    final title = isApostle ? "Apostle Dashboard" : "Bishop Dashboard";
    final headerTitle = isApostle ? "Network Oversight" : "Apostolic Oversight";

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFFAEB),
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _loadDashboard)],
      ),
      body: _isLoading ? _buildShimmer() : _error != null ? _buildError()
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
                  _quickAction(theme, LucideIcons.userPlus, "Create Department Leader", "Assign a member as department leader or assistant", Colors.deepOrange, () async {
                    final nameCtrl = TextEditingController();
                    final roleCtrl = TextEditingController(text: 'department_leader');
                    String elevatedRole = 'department_leader';

                    final result = await showDialog<Map<String, String>>(
                      context: context,
                      builder: (ctx) => StatefulBuilder(
                        builder: (ctx, setDialogState) => AlertDialog(
                          title: const Text("Create Department Leader"),
                          content: SingleChildScrollView(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "User ID (UUID)", hintText: "Paste the user's ID")),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: elevatedRole,
                                items: ['department_leader', 'assistant', 'usher', 'treasurer', 'worship_leader', 'praise_team_leader'].map((r) => DropdownMenuItem(value: r, child: Text(r.replaceAll('_', ' ')))).toList(),
                                onChanged: (v) {
                                  setDialogState(() => elevatedRole = v ?? 'department_leader');
                                  roleCtrl.text = v ?? 'department_leader';
                                },
                                decoration: const InputDecoration(labelText: "Role", hintText: "Select department role"),
                              ),
                              const SizedBox(height: 12),
                              const Text("For pastor or bishop elevation, use the Role Approval workflow instead.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ]),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                            ElevatedButton(onPressed: () => Navigator.pop(ctx, {'userId': nameCtrl.text.trim(), 'role': elevatedRole}), child: const Text("Assign")),
                          ],
                        ),
                      ),
                    );
                    if (result != null) {
                      final uid = result['userId'];
                      final role = result['role'];
                      if (uid != null && uid.isNotEmpty && role != null && role.isNotEmpty) {
                        final svc = ref.read(roleHierarchyServiceProvider);
                        try {
                          await svc.elevateRole(userId: uid, roleName: role);
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$role assigned successfully!"), backgroundColor: Colors.green));
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                        }
                      }
                    }
                  }),
                  _quickAction(theme, LucideIcons.flag, "Request Pastor/Bishop Elevation", "Submit a pending approval request for higher role", Colors.indigo, () async {
                    final nameCtrl = TextEditingController();
                    String targetRole = 'pastor';

                    final result = await showDialog<Map<String, String>>(
                      context: context,
                      builder: (ctx) => StatefulBuilder(
                        builder: (ctx, setDialogState) => AlertDialog(
                          title: const Text("Request Role Elevation"),
                          content: SingleChildScrollView(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "User ID (UUID)", hintText: "Paste the user's ID")),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: targetRole,
                                items: ['pastor', 'bishop'].map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase()))).toList(),
                                onChanged: (v) => setDialogState(() => targetRole = v ?? 'pastor'),
                                decoration: const InputDecoration(labelText: "Target Role", hintText: "Select role to request"),
                              ),
                              const SizedBox(height: 12),
                              const Text("This will create a pending approval request for COA/superadmin review.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ]),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                            ElevatedButton(onPressed: () => Navigator.pop(ctx, {'userId': nameCtrl.text.trim(), 'role': targetRole}), child: const Text("Submit Request")),
                          ],
                        ),
                      ),
                    );
                    if (result != null) {
                      final uid = result['userId'];
                      final role = result['role'];
                      if (uid != null && uid.isNotEmpty && role != null && role.isNotEmpty) {
                        final svc = ref.read(roleHierarchyServiceProvider);
                        try {
                          await svc.assignRole(userId: uid, roleName: role);
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Approval request submitted for $role!"), backgroundColor: Colors.blue));
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                        }
                      }
                    }
                  }),
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
      const SizedBox(height: 25), ShimmerLoader.rectangular(height: 18, width: 120),
      const SizedBox(height: 15), ...List.generate(3, (_) => Padding(padding: const EdgeInsets.only(bottom: 10), child: ShimmerLoader.rectangular(height: 70))),
    ]),
  );

  Widget _buildError() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(LucideIcons.wifiOff, size: 48, color: Colors.grey.shade300),
    const SizedBox(height: 12), Text("Could not load", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
    const SizedBox(height: 20), ElevatedButton.icon(onPressed: _loadDashboard, icon: const Icon(LucideIcons.refreshCw, size: 16), label: const Text("Retry")),
  ]));

  Widget _buildHeader(ThemeData theme, String headerTitle) {
    final attGrowth = _lastMonthAttendance > 0 ? ((_totalAttendance - _lastMonthAttendance) / _lastMonthAttendance * 100).round() : 0;
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.purple.shade800, Colors.purple.shade500], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.purple.shade200.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)), child: const Icon(LucideIcons.globe, color: Colors.white, size: 28)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(headerTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
            Text("$_branchCount branches • $attGrowth% growth", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          ])),
        ]),
      ]),
    );
  }

  Widget _buildStatsGrid(ThemeData theme) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    return GridView.count(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.2,
      children: [
        _statCard("Branches", "$_branchCount", LucideIcons.building, Colors.indigo),
        _statCard("Attendance", _formatCompact(_totalAttendance), LucideIcons.calendarCheck, Colors.green),
        _statCard("Tithes (MTD)", currency.format(_totalTithes), LucideIcons.church, Colors.purple),
        _statCard("Giving (MTD)", currency.format(_totalGiving), LucideIcons.heart, Colors.red),
        _statCard("Total Members", _formatCompact(_totalMembers), LucideIcons.users, Colors.blue),
        _statCard("Missions", "$_missionsActive", LucideIcons.map, Colors.amber),
      ],
    );
  }

  Widget _buildMissionRow(ThemeData theme, Map<String, dynamic> mission) {
    final title = mission['title'] as String? ?? 'Unnamed Mission';
    final status = mission['status'] as String? ?? 'unknown';
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(LucideIcons.map, color: Colors.amber, size: 18)),
        const SizedBox(width: 14),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: status == 'active' ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: status == 'active' ? Colors.green : Colors.grey)),
        ),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: color, size: 20), const Spacer(),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
    ]),
  );

  Widget _buildBranchRow(ThemeData theme, Map<String, dynamic> branch, BuildContext context) {
    final name = branch['name'] as String? ?? 'Unnamed';
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ServiceReportScreen())),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(LucideIcons.church, color: Colors.purple, size: 18)),
          const SizedBox(width: 14),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          Icon(LucideIcons.chevronRight, size: 16, color: Colors.grey.shade400),
        ]),
      ),
    );
  }

  Widget _quickAction(ThemeData theme, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
        ])),
        Icon(LucideIcons.chevronRight, size: 18, color: Colors.grey.shade300),
      ]),
    ),
  );

  Widget _emptyCard(ThemeData theme, String msg) => Container(
    width: double.infinity, padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: Center(child: Text(msg, style: TextStyle(color: Colors.grey.shade400))),
  );

  String _formatCompact(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : n.toString();
}
