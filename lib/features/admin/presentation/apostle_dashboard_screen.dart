import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'package:church_on_app/core/widgets/pro_charts.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';
import 'pastor_bishop_report_screen.dart';
import 'bishop_heatmap_screen.dart';
import 'global_broadcast_screen.dart';

/// APOSTLE — NETWORK OVERSIGHT ACROSS ONE OR MORE ORGANISATIONS.
///
/// An apostle is distinct from a bishop: a bishop oversees ONE organisation
/// (its branches), while an apostle may lead / be linked to SEVERAL
/// organisations and therefore sees the network as a whole, with a per
/// organisation breakdown. Every number comes from the same server-side org
/// rollup RPCs the bishop dashboard uses — never a client-side table scan.
class ApostleDashboardScreen extends ConsumerStatefulWidget {
  const ApostleDashboardScreen({super.key});

  @override
  ConsumerState<ApostleDashboardScreen> createState() => _ApostleDashboardScreenState();
}

class _OrgRollup {
  final Map<String, dynamic> org;
  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> snapshots;
  final Map<String, dynamic> service;
  final List<Map<String, dynamic>> baskets;

  const _OrgRollup({
    required this.org,
    required this.stats,
    required this.snapshots,
    required this.service,
    required this.baskets,
  });

  String get id => org['id']?.toString() ?? '';
  String get name => org['name']?.toString() ?? 'Organisation';
  int get branches =>
      snapshots.isNotEmpty ? snapshots.length : ((stats['branches'] as num?)?.toInt() ?? 0);
  int get members => (stats['members'] as num?)?.toInt() ??
      snapshots.fold<int>(0, (s, e) => s + ((e['members'] as num?)?.toInt() ?? 0));
  int get attendance =>
      (service['attendance'] as num?)?.toInt() ??
      snapshots.fold<int>(0, (s, e) => s + ((e['attendance_mtd'] as num?)?.toInt() ?? 0));
  double get giving => (stats['monthly_giving'] as num?)?.toDouble() ??
      snapshots.fold<double>(0, (s, e) => s + ((e['tithes_mtd'] as num?)?.toDouble() ?? 0));
  int get activeStreams => (stats['active_streams'] as num?)?.toInt() ?? 0;
  double get basketTotal =>
      baskets.fold<double>(0, (s, e) => s + ((e['total_amount'] as num?)?.toDouble() ?? 0));
}

class _ApostleDashboardScreenState extends ConsumerState<ApostleDashboardScreen> {
  bool _loading = true;
  bool _noOrg = false;
  String? _error;
  final List<_OrgRollup> _rollups = [];
  List<Map<String, dynamic>> _givingSeries = [];
  List<Map<String, dynamic>> _missions = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final profile = ref.read(profileProvider).value;
    if (profile == null) {
      setState(() => _loading = false);
      return;
    }
    final orgSvc = ref.read(organizationServiceProvider);
    try {
      final orgs = await orgSvc.resolveMyOrganisations(tenantId: profile.tenantId);
      if (orgs.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _noOrg = true;
            _error = null;
            _rollups.clear();
            _givingSeries = [];
            _missions = [];
          });
        }
        return;
      }

      final rollups = <_OrgRollup>[];
      final missions = <Map<String, dynamic>>[];
      // Aggregate the monthly giving series across every organisation so the
      // network trend is real, not a single-org slice.
      final monthTotals = <String, double>{};

      for (final org in orgs) {
        final orgId = org['id']?.toString() ?? '';
        if (orgId.isEmpty) continue;
        Map<String, dynamic> stats = const {};
        try {
          stats = await orgSvc.getOrganizationStats(orgId);
        } catch (e) {
          debugPrint('apostle get_organization_stats($orgId) failed: $e');
        }
        final snapshots = await orgSvc.getOrgBranchSnapshots(orgId);
        Map<String, dynamic> service = const {};
        try {
          service = await _fetchServiceSummary(orgId);
        } catch (e) {
          debugPrint('apostle get_organization_service_summary($orgId) failed: $e');
        }
        final baskets = await _fetchBaskets(orgId);
        final series = await orgSvc.getOrgGivingSeries(orgId);
        for (final point in series) {
          final month = point['month']?.toString() ?? '';
          if (month.isEmpty) continue;
          monthTotals[month] =
              (monthTotals[month] ?? 0) + ((point['total'] as num?)?.toDouble() ?? 0);
        }
        try {
          missions.addAll(await orgSvc.getOrganizationMissions(orgId, limit: 20));
        } catch (e) {
          debugPrint('apostle get_organization_missions($orgId) failed: $e');
        }
        rollups.add(_OrgRollup(
          org: org,
          stats: stats,
          snapshots: snapshots,
          service: service,
          baskets: baskets,
        ));
      }

      final sortedMonths = monthTotals.keys.toList()..sort();
      final series = sortedMonths
          .map((m) => {'month': m, 'total': monthTotals[m]})
          .toList();

      if (mounted) {
        setState(() {
          _rollups
            ..clear()
            ..addAll(rollups);
          _givingSeries = series;
          _missions = missions;
          _loading = false;
          _noOrg = false;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('apostle dashboard load failed: $e');
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<Map<String, dynamic>> _fetchServiceSummary(String orgId) async {
    final res = await Supabase.instance.client
        .rpc('get_organization_service_summary', params: {'p_org_id': orgId});
    return (res as Map<String, dynamic>?) ?? const {};
  }

  Future<List<Map<String, dynamic>>> _fetchBaskets(String orgId) async {
    try {
      final res = await Supabase.instance.client.rpc('get_basket_summary', params: {
        'p_org_id': orgId,
        'p_days': 30,
      });
      return List<Map<String, dynamic>>.from(res as List? ?? []);
    } catch (e) {
      debugPrint('apostle get_basket_summary($orgId) failed: $e');
      return [];
    }
  }

  int get _orgCount => _rollups.length;
  int get _branchCount => _rollups.fold<int>(0, (s, e) => s + e.branches);
  int get _totalMembers => _rollups.fold<int>(0, (s, e) => s + e.members);
  int get _totalAttendance => _rollups.fold<int>(0, (s, e) => s + e.attendance);
  double get _totalGiving => _rollups.fold<double>(0, (s, e) => s + e.giving);
  int get _activeStreams => _rollups.fold<int>(0, (s, e) => s + e.activeStreams);
  double get _basketTotal => _rollups.fold<double>(0, (s, e) => s + e.basketTotal);
  int get _serviceCount => _rollups.fold<int>(0, (s, e) => (e.service['service_count'] as num?)?.toInt() ?? 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Apostle Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _loading ? null : _loadData),
        ],
      ),
      body: _loading
          ? _buildShimmer()
          : _noOrg
              ? _buildNoOrgState(theme)
              : _error != null
                  ? AppErrorView(error: _error, onRetry: _loadData)
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom + 20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _buildHeader(theme),
                          const SizedBox(height: 20),
                          _buildKpiGrid(theme),
                          const SizedBox(height: 16),
                          _buildEngagementRow(theme),
                          const SizedBox(height: 28),
                          _sectionTitle(theme, 'Network Analytics'),
                          const SizedBox(height: 12),
                          _buildGivingTrendCard(theme),
                          const SizedBox(height: 16),
                          _buildBasketMixCard(theme),
                          const SizedBox(height: 28),
                          _sectionTitle(theme, _orgCount == 1 ? 'Organisation' : 'Organisations'),
                          const SizedBox(height: 12),
                          ..._rollups.map((r) => _buildOrgCard(theme, r)),
                          const SizedBox(height: 28),
                          _sectionTitle(theme, 'Branch Health'),
                          const SizedBox(height: 12),
                          _buildBranches(theme),
                          if (_missions.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _sectionTitle(theme, 'Network Missions'),
                            const SizedBox(height: 12),
                            ..._missions.take(6).map((m) => _buildMissionRow(theme, m)),
                          ],
                          const SizedBox(height: 28),
                          _sectionTitle(theme, 'Oversight Actions'),
                          const SizedBox(height: 12),
                          _quickAction(theme, LucideIcons.fileText, 'Pastor Reports',
                              'Review weekly service reports from every branch', theme.primaryColor,
                              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PastorBishopReportScreen()))),
                          _quickAction(theme, LucideIcons.megaphone, 'Network Announcement',
                              'Publish an org-wide notice to all branches', Colors.amber,
                              () => context.push('/network-activity')),
                          _quickAction(theme, LucideIcons.barChart3, 'Central Treasury',
                              'Multi-branch financial oversight', Colors.green,
                              () => context.push('/finance-dashboard')),
                          _quickAction(theme, LucideIcons.piggyBank, 'Offering Basket Summary',
                              'Network-wide basket collections', Colors.teal,
                              () => context.push('/offering-baskets-summary')),
                          _quickAction(theme, LucideIcons.map, 'Branch Map',
                              'Geographic distribution of the network', Colors.indigo,
                              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BishopHeatmapScreen()))),
                          const SizedBox(height: 140),
                        ]),
                      ),
                    ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) =>
      Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface));

  Widget _buildShimmer() => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          ShimmerLoader.rectangular(height: 150, width: double.infinity),
          const SizedBox(height: 20),
          Row(children: [Expanded(child: ShimmerLoader.rectangular(height: 100)), const SizedBox(width: 12), Expanded(child: ShimmerLoader.rectangular(height: 100))]),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: ShimmerLoader.rectangular(height: 100)), const SizedBox(width: 12), Expanded(child: ShimmerLoader.rectangular(height: 100))]),
          const SizedBox(height: 24),
          ShimmerLoader.rectangular(height: 200, width: double.infinity),
        ]),
      );

  Widget _buildHeader(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [theme.primaryColor, const Color(0xFF1A1A1A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.28), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(18)),
          child: const Icon(LucideIcons.globe, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Apostolic Network', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 4),
            Text('$_orgCount organisation${_orgCount == 1 ? '' : 's'} • $_branchCount branches',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${_formatCompact(_totalMembers)} members across the network',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildKpiGrid(ThemeData theme) {
    final currency = NumberFormat.compactCurrency(symbol: 'K');
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.3,
      children: [
        _kpiCard(theme, 'Organisations', '$_orgCount', LucideIcons.globe, theme.primaryColor),
        _kpiCard(theme, 'Branches', '$_branchCount', LucideIcons.building, Colors.indigo),
        _kpiCard(theme, 'Total Members', _formatCompact(_totalMembers), LucideIcons.users, Colors.green),
        _kpiCard(theme, 'Giving (MTD)', currency.format(_totalGiving), LucideIcons.church, Colors.orange),
      ],
    );
  }

  Widget _kpiCard(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 18),
        ),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildEngagementRow(ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _engagementChip(theme, LucideIcons.fileText, '$_serviceCount', 'Service reports'),
        _engagementChip(theme, LucideIcons.calendarCheck, _formatCompact(_totalAttendance), 'Attendance MTD'),
        _engagementChip(theme, LucideIcons.radio, '$_activeStreams', 'Live now'),
        _engagementChip(theme, LucideIcons.piggyBank, NumberFormat.compactCurrency(symbol: 'K').format(_basketTotal), 'Baskets 30d'),
      ],
    );
  }

  Widget _engagementChip(ThemeData theme, IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: theme.primaryColor),
        const SizedBox(width: 8),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
      ]),
    );
  }

  Widget _buildGivingTrendCard(ThemeData theme) {
    final values = _givingSeries.map<double>((e) => (e['total'] as num?)?.toDouble() ?? 0).toList();
    final labels = _givingSeries.map<String>((e) {
      final m = e['month']?.toString() ?? '';
      if (m.length >= 7) {
        try {
          return DateFormat.MMM().format(DateTime.parse('$m-01'));
        } catch (_) {
          return m.substring(5, 7);
        }
      }
      return '';
    }).toList();
    if (values.isEmpty) {
      return ProChartCard(
        title: 'Network Giving Trend',
        subtitle: 'Last 6 months',
        height: 170,
        child: Center(
          child: Text('No giving data yet',
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      );
    }
    final total = values.fold<double>(0, (s, v) => s + v);
    return ProChartCard(
      title: 'Network Giving Trend',
      subtitle: 'Last 6 months • ${NumberFormat.compactCurrency(symbol: 'K ').format(total)}',
      height: 180,
      child: ProBarChart(values: values, labels: labels),
    );
  }

  Widget _buildBasketMixCard(ThemeData theme) {
    final palette = <Color>[theme.primaryColor, Colors.green, Colors.blue, Colors.orange, Colors.purple, Colors.teal];
    final rows = <Map<String, dynamic>>[];
    for (final r in _rollups) {
      rows.addAll(r.baskets);
    }
    final nonZero = rows.where((b) => ((b['total_amount'] as num?)?.toDouble() ?? 0) > 0).toList();
    if (nonZero.isEmpty) {
      return ProChartCard(
        title: 'Offering Basket Mix',
        subtitle: 'Last 30 days',
        height: 170,
        child: Center(
          child: Text('No basket collections yet',
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      );
    }
    final sections = <ProPieSection>[];
    for (var i = 0; i < nonZero.length; i++) {
      sections.add(ProPieSection(
        label: nonZero[i]['basket_name']?.toString() ?? 'Basket',
        value: (nonZero[i]['total_amount'] as num?)?.toDouble() ?? 0,
        color: palette[i % palette.length],
      ));
    }
    return ProChartCard(
      title: 'Offering Basket Mix',
      subtitle: 'Last 30 days • ${NumberFormat.compactCurrency(symbol: 'K ').format(_basketTotal)}',
      height: 220,
      child: ProPieChart(
        sections: sections,
        centerLabel: 'BASKETS',
        centerValue: NumberFormat.compactCurrency(symbol: 'K').format(_basketTotal),
      ),
    );
  }

  Widget _buildOrgCard(ThemeData theme, _OrgRollup r) {
    final currency = NumberFormat.compactCurrency(symbol: 'K');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.15)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(LucideIcons.globe, color: theme.primaryColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (r.org['led'] == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: const Text('LEADING', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.w900)),
            ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 6, children: [
          _branchChip(Icons.people_outline, '${_formatCompact(r.members)} members', theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          _branchChip(LucideIcons.building, '${r.branches} branches', theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          _branchChip(LucideIcons.church, '${currency.format(r.giving)} MTD', Colors.green.shade700),
          if (r.activeStreams > 0) _branchChip(LucideIcons.radio, '${r.activeStreams} live', Colors.red),
        ]),
      ]),
    );
  }

  Widget _branchChip(IconData icon, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _buildBranches(ThemeData theme) {
    final rows = <(String orgName, Map<String, dynamic> branch)>[];
    for (final r in _rollups) {
      for (final b in r.snapshots) {
        rows.add((r.name, b));
      }
    }
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(LucideIcons.building, color: Colors.amber, size: 18),
            const SizedBox(width: 10),
            const Expanded(child: Text('No branches linked yet', style: TextStyle(fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 8),
          Text(
            'No churches are attached to your organisation(s) yet. Link a church from the bishop dashboard to see branch metrics roll up here.',
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12, height: 1.4),
          ),
        ]),
      );
    }
    return Column(children: rows.map((e) => _buildBranchRow(theme, e.$1, e.$2)).toList());
  }

  Widget _buildBranchRow(ThemeData theme, String orgName, Map<String, dynamic> branch) {
    final name = branch['church_name']?.toString() ?? 'Branch';
    final members = (branch['members'] as num?)?.toInt() ?? 0;
    final attendance = (branch['attendance_mtd'] as num?)?.toInt() ?? 0;
    final giving = (branch['tithes_mtd'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(LucideIcons.church, color: theme.primaryColor, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(orgName, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 10)),
            const SizedBox(height: 6),
            Wrap(spacing: 12, runSpacing: 4, children: [
              _branchChip(Icons.people_outline, '$members members', theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              _branchChip(LucideIcons.calendarCheck, '$attendance attend', theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              _branchChip(LucideIcons.church, 'K${NumberFormat.compact().format(giving)} MTD', Colors.green.shade700),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _buildMissionRow(ThemeData theme, Map<String, dynamic> mission) {
    final title = mission['title']?.toString() ?? 'Mission';
    final church = mission['church_name']?.toString() ?? '';
    final status = mission['status']?.toString() ?? 'unknown';
    final color = status == 'active' ? Colors.green : status == 'completed' ? theme.primaryColor : Colors.amber;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(LucideIcons.map, color: color, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (church.isNotEmpty)
              Text(church, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
          ]),
        ),
        Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _buildNoOrgState(ThemeData theme) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [theme.primaryColor, const Color(0xFF1A1A1A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(LucideIcons.globe, color: Colors.white, size: 30),
              const SizedBox(height: 14),
              const Text('No organisation linked yet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                'Your apostolic network is built from the organisations your church belongs to (or that you lead). Once a church is linked to an organisation, its branches and metrics appear here.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 12, height: 1.45),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          _quickAction(theme, LucideIcons.refreshCw, 'Check Again',
              'Already linked by COA? Re-check your organisations', Colors.teal, _loadData),
          _quickAction(theme, LucideIcons.map, 'Branch Map', 'See churches already on the map', Colors.indigo,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BishopHeatmapScreen()))),
          _quickAction(theme, LucideIcons.megaphone, 'Send Broadcast',
              'Notify your church while your network is being set up', Colors.amber,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalBroadcastScreen()))),
        ]),
      ),
    );
  }

  Widget _quickAction(ThemeData theme, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
              ]),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          ]),
        ),
      );

  String _formatCompact(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : n.toString();
}
