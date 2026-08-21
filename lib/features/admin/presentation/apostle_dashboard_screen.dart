import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/pro_charts.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';
import 'member_management_screen.dart';
import 'service_report_screen.dart';
import 'global_broadcast_screen.dart';

class ApostleDashboardScreen extends ConsumerStatefulWidget {
  const ApostleDashboardScreen({super.key});

  @override
  ConsumerState<ApostleDashboardScreen> createState() => _ApostleDashboardScreenState();
}

class _ApostleDashboardScreenState extends ConsumerState<ApostleDashboardScreen> {
  List<Map<String, dynamic>> _churches = [];
  Map<String, int> _memberCounts = {};
  List<Map<String, dynamic>> _activeDeliveries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final client = Supabase.instance.client;
      final profile = ref.read(profileProvider).value;
      final orgId = profile?.organizationId;

      if (orgId != null && orgId.isNotEmpty) {
        // NETWORK MODE: server-side aggregation — no full-profiles scan.
        final orgSvc = ref.read(organizationServiceProvider);
        final counts = await orgSvc.getOrganizationChurchMemberCounts(orgId);

        final memberCounts = <String, int>{};
        final branches = <Map<String, dynamic>>[];
        for (final c in counts) {
          final cid = (c['church_id'] as String?)?.toString() ?? '';
          if (cid.isNotEmpty) {
            memberCounts[cid] = (c['member_count'] as num?)?.toInt() ?? 0;
            branches.add({'id': cid, 'name': c['church_name']?.toString() ?? 'Unknown Church', 'city': '', 'country': ''});
          }
        }
        _churches = branches;
        _memberCounts = memberCounts;
      } else {
        // Fallback: bounded church list only (no unbounded profile scan).
        final churchesRes = await client
            .from('churches')
            .select('id, name, city, country')
            .order('created_at', ascending: false)
            .limit(50);
        _churches = List<Map<String, dynamic>>.from(churchesRes as List);
        _memberCounts = {};
      }

      // Real active cargo missions (bounded).
      final deliveriesRes = await client
          .from('deliveries')
          .select('id, pickup_address, delivery_address, status, created_at')
          .or('status.eq.pending,status.eq.assigned,status.eq.picked_up,status.eq.in_transit')
          .order('created_at', ascending: false)
          .limit(20);
      _activeDeliveries = List<Map<String, dynamic>>.from(deliveriesRes);

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint("ApostleDashboard error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _totalMembers =>
      _churches.fold(0, (sum, c) => sum + (_memberCounts[c['id']?.toString()] ?? 0));

  int get _activeMissions => _activeDeliveries.length;

  int get _avgMembersPerChurch => _churches.isEmpty ? 0 : (_totalMembers / _churches.length).round();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          "Apostle Dashboard",
          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _loading ? null : _loadData)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Network Metrics",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 15),
                    GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 15,
                      crossAxisSpacing: 15,
                      childAspectRatio: 1.2,
                      children: [
                        _buildMetricCard(context, "Network Churches", _churches.length.toString(), LucideIcons.church),
                        _buildMetricCard(context, "Total Members", _totalMembers.toString(), LucideIcons.users),
                        _buildMetricCard(context, "Missions Active", _activeMissions.toString(), LucideIcons.zap),
                        _buildMetricCard(context, "Avg Members/Church", _avgMembersPerChurch.toString(), LucideIcons.trendingUp),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Text(
                      "Network Overview",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 15),
                    if (_churches.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: Text(
                            "No churches in your network yet.",
                            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                          ),
                        ),
                      )
                    else
                      ...List.generate(_churches.length, (i) {
                        final church = _churches[i];
                        final cid = church['id']?.toString() ?? '';
                        final members = _memberCounts[cid] ?? 0;
                        final name = church['name']?.toString() ?? 'Unknown Church';
                        final location = church['city']?.toString() ?? church['country']?.toString() ?? '';
                        return _buildChurchRow(context, theme, name, members, location);
                      }),
                    if (_churches.length > 1) ...[
                      const SizedBox(height: 40),
                      Text(
                        "Members by Church",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                      ),
                      const SizedBox(height: 15),
                      _buildMembersChart(context, theme),
                    ],
                    const SizedBox(height: 40),
                    Text(
                      "Active Missions",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 15),
                    if (_activeDeliveries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: Text(
                            "No active cargo missions right now.",
                            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                          ),
                        ),
                      )
                    else
                      ..._activeDeliveries.map((d) => _buildMissionItem(context, theme, d)),
                    const SizedBox(height: 40),
                    Text(
                      "Quick Actions",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 15),
                    _buildQuickAction(context, LucideIcons.church, "Member Management", Theme.of(context).primaryColor, () {
                      final tenant = ref.read(currentTenantProvider);
                      if (tenant == null) {
                        _noTenantSnack(context);
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberManagementScreen()));
                    }),
                    _buildQuickAction(context, LucideIcons.fileText, "Ministry Reports", Theme.of(context).primaryColor, () {
                      final tenant = ref.read(currentTenantProvider);
                      if (tenant == null) {
                        _noTenantSnack(context);
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ServiceReportScreen()));
                    }),
                    _buildQuickAction(context, LucideIcons.megaphone, "Send Broadcast", Colors.amber, () {
                      final tenant = ref.read(currentTenantProvider);
                      if (tenant == null) {
                        _noTenantSnack(context);
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalBroadcastScreen()));
                    }),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  void _noTenantSnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Select a church first — open a church from the home screen.")),
    );
  }

  Widget _buildMetricCard(BuildContext context, String title, String value, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.primaryColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: theme.colorScheme.onSecondary, size: 28),
          const Spacer(),
          Text(
            value,
            style: TextStyle(color: theme.colorScheme.onSecondary, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          Text(
            title,
            style: TextStyle(color: theme.colorScheme.onSecondary.withValues(alpha: 0.7), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildChurchRow(BuildContext context, ThemeData theme, String name, int members, String location) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                if (location.isNotEmpty)
                  Text(location, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              "$members members",
              style: TextStyle(color: const Color(0xFF7A5C00), fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Real per-church member counts (top 12) rendered as professional bars.
  Widget _buildMembersChart(BuildContext context, ThemeData theme) {
    final sorted = _churches.map((c) {
      final cid = c['id']?.toString() ?? '';
      return (name: c['name']?.toString() ?? 'Unknown', members: _memberCounts[cid] ?? 0);
    }).toList()
      ..sort((a, b) => b.members.compareTo(a.members));

    final top = sorted.take(12).toList();
    if (top.isEmpty) {
      return ProChartCard(
        title: 'Members by Church',
        subtitle: 'Top 12 branches',
        height: 180,
        child: Center(child: Text('No member data yet', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w600))),
      );
    }
    final values = top.map<double>((e) => e.members.toDouble()).toList();
    final labels = top.map<String>((e) => e.name.length > 10 ? '${e.name.substring(0, 10)}…' : e.name).toList();
    return ProChartCard(
      title: 'Members by Church',
      // ignore: unnecessary_brace_in_string_interps
      subtitle: 'Top 12 • avg ${_avgMembersPerChurch} per church • ${_totalMembers} total',
      height: 200,
      child: ProBarChart(values: values, labels: labels, barWidth: 14),
    );
  }

  Widget _buildMissionItem(BuildContext context, ThemeData theme, Map<String, dynamic> d) {
    final pickup = d['pickup_address']?.toString() ?? 'Pickup';
    final dropoff = d['delivery_address']?.toString() ?? 'Destination';
    final status = (d['status'] ?? '').toString().toUpperCase();
    final color = status == 'IN_TRANSIT'
        ? Colors.orange
        : status == 'PICKED_UP'
            ? Theme.of(context).primaryColor
            : Colors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.mapPin, color: color, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$pickup → $dropoff',
                  style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Cargo delivery • ${d['created_at']?.toString().split('T').first ?? ''}',
                  style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11),
                ),
              ],
            ),
          ),
          Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildQuickAction(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
