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
import 'bishop_heatmap_screen.dart';
import 'branch_oversight_screen.dart';

/// BISHOP / APOSTLE — ORGANISATION OVERSIGHT.
///
/// This is a network-level command centre: every branch in the organisation
/// with its member count, attendance MTD, giving MTD and health, plus
/// organisation-wide roll-ups and comparison. It deliberately does NOT carry
/// pastor-level, single-branch tools (member management, own ledger, branch
/// attendance capture, invites) — those live on the Pastor Dashboard for the
/// branch pastor. Every number here is real, sourced from server-side RPCs.
class BishopDashboardScreen extends ConsumerStatefulWidget {
  const BishopDashboardScreen({super.key});

  @override
  ConsumerState<BishopDashboardScreen> createState() => _BishopDashboardScreenState();
}

class _BishopDashboardScreenState extends ConsumerState<BishopDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  String? _orgId;
  String? _orgName;

  Map<String, dynamic> _stats = const {};
  Map<String, dynamic> _service = const {};
  List<Map<String, dynamic>> _memberCounts = [];
  List<Map<String, dynamic>> _snapshots = [];
  List<Map<String, dynamic>> _baskets = [];
  List<Map<String, dynamic>> _givingSeries = [];
  List<Map<String, dynamic>> _missions = [];
  List<Map<String, dynamic>> _branches = [];

  @override
  void initState() {
    super.initState();
    ref.listen(profileProvider, (prev, next) {
      if (next.hasValue && next.value != null) _loadDashboard();
      if (next.hasError) {
        setState(() {
          _isLoading = false;
          _error = next.error.toString();
        });
      }
    });
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    final profile = ref.read(profileProvider).value;
    if (profile == null) {
      setState(() => _isLoading = false);
      return;
    }

    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;

    try {
      // Resolve the organisation: the profile's church carries organization_id;
      // otherwise fall back to the organisation this user leads as bishop.
      String? orgId = profile.organizationId;
      String? orgName;
      if (orgId != null && orgId.isNotEmpty) {
        try {
          final org = await client.from('organizations').select('id, name').eq('id', orgId).maybeSingle();
          orgName = org?['name']?.toString();
        } catch (e) {
          debugPrint('org name lookup failed: $e');
        }
      } else if (uid != null) {
        try {
          final org = await client.from('organizations').select('id, name').eq('bishop_id', uid).maybeSingle();
          orgId = org?['id']?.toString();
          orgName = org?['name']?.toString();
        } catch (e) {
          debugPrint('bishop org fallback failed: $e');
        }
      }

      if (orgId == null || orgId.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = "No organisation is assigned to your account yet. Create one to start overseeing branches.";
          });
        }
        return;
      }

      final orgSvc = ref.read(organizationServiceProvider);

      // Independent fetches — a failure in any one degrades that section only.
      Map<String, dynamic> stats = const {};
      try {
        stats = await orgSvc.getOrganizationStats(orgId);
      } catch (e) {
        debugPrint('get_organization_stats failed: $e');
      }
      final memberCounts = await orgSvc.getOrganizationChurchMemberCounts(orgId);
      final snapshots = await orgSvc.getOrgBranchSnapshots(orgId);
      final givingSeries = await orgSvc.getOrgGivingSeries(orgId);
      final missions = await orgSvc.getOrganizationMissions(orgId);
      final service = await _fetchServiceSummary(orgId);
      final baskets = await _fetchBaskets(orgId);
      final branches = await _fetchBranches(orgId);

      if (mounted) {
        setState(() {
          _orgId = orgId;
          _orgName = orgName;
          _stats = stats;
          _memberCounts = memberCounts;
          _snapshots = snapshots;
          _givingSeries = givingSeries;
          _missions = missions;
          _service = service;
          _baskets = baskets;
          _branches = branches;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('bishop dashboard load failed: $e');
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  Future<Map<String, dynamic>> _fetchServiceSummary(String orgId) async {
    try {
      final res = await Supabase.instance.client
          .rpc('get_organization_service_summary', params: {'p_org_id': orgId});
      return (res as Map<String, dynamic>?) ?? const {};
    } catch (e) {
      debugPrint('get_organization_service_summary failed: $e');
      return const {};
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBaskets(String orgId) async {
    try {
      final res = await Supabase.instance.client.rpc('get_basket_summary', params: {
        'p_org_id': orgId,
        'p_days': 30,
      });
      return List<Map<String, dynamic>>.from(res as List? ?? []);
    } catch (e) {
      debugPrint('get_basket_summary(org) failed: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBranches(String orgId) async {
    try {
      final res = await Supabase.instance.client
          .from('churches')
          .select('id, name, is_verified, subscription_ends_at, plan, logo_url, latitude, longitude, tenant_id')
          .eq('organization_id', orgId)
          .order('name');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('org branches fetch failed: $e');
      return [];
    }
  }

  Map<String, dynamic>? _snapshotFor(String? churchId) {
    if (churchId == null) return null;
    for (final s in _snapshots) {
      if (s['church_id']?.toString() == churchId) return s;
    }
    return null;
  }

  int _membersFor(String? churchId) {
    final snap = _snapshotFor(churchId);
    if (snap != null) return (snap['members'] as num?)?.toInt() ?? 0;
    if (churchId != null) {
      for (final m in _memberCounts) {
        if (m['church_id']?.toString() == churchId) return (m['member_count'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  int get _branchCount =>
      _branches.isNotEmpty ? _branches.length : ((_stats['branches'] as num?)?.toInt() ?? _memberCounts.length);

  int get _totalMembers {
    final fromStats = (_stats['members'] as num?)?.toInt();
    if (fromStats != null && fromStats > 0) return fromStats;
    final fromSnapshots = _snapshots.fold<int>(0, (s, e) => s + ((e['members'] as num?)?.toInt() ?? 0));
    if (fromSnapshots > 0) return fromSnapshots;
    return _memberCounts.fold<int>(0, (s, e) => s + ((e['member_count'] as num?)?.toInt() ?? 0));
  }

  int get _totalAttendance {
    final fromSnapshots = _snapshots.fold<int>(0, (s, e) => s + ((e['attendance_mtd'] as num?)?.toInt() ?? 0));
    if (fromSnapshots > 0) return fromSnapshots;
    return (_service['attendance'] as num?)?.toInt() ?? 0;
  }

  double get _totalGiving {
    final fromStats = (_stats['monthly_giving'] as num?)?.toDouble();
    if (fromStats != null && fromStats > 0) return fromStats;
    final fromSnapshots = _snapshots.fold<double>(0, (s, e) => s + ((e['tithes_mtd'] as num?)?.toDouble() ?? 0));
    if (fromSnapshots > 0) return fromSnapshots;
    return (_service['offering'] as num?)?.toDouble() ?? 0;
  }

  int get _activeStreams => (_stats['active_streams'] as num?)?.toInt() ?? 0;

  double get _basketTotal =>
      _baskets.fold<double>(0, (s, e) => s + ((e['total_amount'] as num?)?.toDouble() ?? 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.read(profileProvider).value;
    final role = profile?.role ?? '';
    final isApostle = role == 'apostle';
    final title = isApostle ? "Apostle Dashboard" : "Bishop Dashboard";

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          if (_orgId != null)
            IconButton(
              icon: const Icon(LucideIcons.link),
              tooltip: 'Link a church to this organisation',
              onPressed: _isLoading ? null : _showLinkChurchSheet,
            )
          else if (!isApostle)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              tooltip: 'Create organisation',
              onPressed: _isLoading ? null : _showCreateOrgDialog,
            ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _isLoading ? null : _loadDashboard,
          ),
        ],
      ),
      body: _isLoading
          ? _buildShimmer()
          : _error != null
              ? AppErrorView(error: _error, onRetry: _loadDashboard)
              : RefreshIndicator(
                  onRefresh: _loadDashboard,
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom + 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(theme, isApostle),
                          const SizedBox(height: 20),
                          _buildKpiGrid(theme),
                          const SizedBox(height: 16),
                          _buildEngagementRow(theme),
                          const SizedBox(height: 28),
                          _sectionTitle(theme, 'Network Analytics'),
                          const SizedBox(height: 12),
                          if (_givingSeries.isNotEmpty) ...[
                            _buildGivingTrendCard(theme),
                            const SizedBox(height: 16),
                          ],
                          _buildBranchComparisonCard(theme),
                          const SizedBox(height: 16),
                          _buildBasketMixCard(theme),
                          const SizedBox(height: 28),
                          _sectionTitle(theme, 'Branch Health'),
                          const SizedBox(height: 12),
                          _buildBranches(theme),
                          if (_missions.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _sectionTitle(theme, 'Network Missions'),
                            const SizedBox(height: 12),
                            ..._missions.take(5).map((m) => _buildMissionRow(theme, m)),
                          ],
                          const SizedBox(height: 28),
                          _sectionTitle(theme, 'Organisation'),
                          const SizedBox(height: 12),
                          _buildOrgCard(theme),
                          const SizedBox(height: 28),
                          _sectionTitle(theme, 'Oversight Actions'),
                          const SizedBox(height: 12),
                          _quickAction(theme, LucideIcons.fileText, 'Pastor Reports',
                              'Review weekly service reports from every branch', theme.primaryColor,
                              () => context.push('/pastor-bishop-report')),
                          _quickAction(theme, LucideIcons.megaphone, 'Network Announcement',
                              'Publish an org-wide notice to all branches', Colors.amber,
                              () => context.push('/network-activity')),
                          _quickAction(theme, LucideIcons.barChart3, 'Central Treasury',
                              'Multi-branch financial oversight', Colors.green,
                              () => context.push('/finance-dashboard')),
                          _quickAction(theme, LucideIcons.piggyBank, 'Offering Basket Summary',
                              'Organisation-wide basket collections', Colors.teal,
                              () => context.push('/offering-baskets-summary')),
                          _quickAction(theme, LucideIcons.map, 'Branch Map',
                              'Geographic distribution of branches', Colors.indigo,
                              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BishopHeatmapScreen()))),
                          const SizedBox(height: 140),
                        ],
                      ),
                    ),
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

  Widget _buildHeader(ThemeData theme, bool isApostle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.primaryColor, const Color(0xFF1A1A1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
            Text(isApostle ? 'Network Oversight' : 'Organisation Oversight',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              _orgName?.isNotEmpty == true ? _orgName! : 'Your organisation',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text('$_branchCount branches • ${_formatCompact(_totalMembers)} members',
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
        _kpiCard(theme, 'Branches', '$_branchCount', LucideIcons.building, theme.primaryColor),
        _kpiCard(theme, 'Total Members', _formatCompact(_totalMembers), LucideIcons.users, Colors.indigo),
        _kpiCard(theme, 'Attendance (MTD)', _formatCompact(_totalAttendance), LucideIcons.calendarCheck, Colors.green),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 18),
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEngagementRow(ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _engagementChip(theme, LucideIcons.fileText, '${(_service['service_count'] as num?)?.toInt() ?? 0}', 'Service reports'),
        _engagementChip(theme, LucideIcons.userPlus, '${(_service['visitors'] as num?)?.toInt() ?? 0}', 'Visitors MTD'),
        _engagementChip(theme, LucideIcons.heartPulse, '${(_service['salvations'] as num?)?.toInt() ?? 0}', 'Salvations MTD'),
        _engagementChip(theme, LucideIcons.video, '${(_service['online_viewers'] as num?)?.toInt() ?? 0}', 'Online viewers'),
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
    final total = values.fold<double>(0, (s, v) => s + v);
    return ProChartCard(
      title: 'Network Giving Trend',
      subtitle: 'Last 6 months • ${NumberFormat.compactCurrency(symbol: 'K ').format(total)}',
      height: 180,
      child: ProBarChart(values: values, labels: labels),
    );
  }

  Widget _buildBranchComparisonCard(ThemeData theme) {
    final rows = _snapshots
        .map((s) => (
              name: (s['church_name']?.toString() ?? 'Branch'),
              members: (s['members'] as num?)?.toInt() ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.members.compareTo(a.members));
    final top = rows.take(10).toList();
    if (top.isEmpty) {
      return ProChartCard(
        title: 'Branch Comparison',
        subtitle: 'Members per branch',
        height: 170,
        child: Center(
          child: Text('No branch data yet',
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      );
    }
    return ProChartCard(
      title: 'Branch Comparison',
      subtitle: 'Members per branch • top ${top.length}',
      height: 190,
      child: ProBarChart(
        values: top.map<double>((e) => e.members.toDouble()).toList(),
        labels: top.map<String>((e) => e.name.length > 10 ? '${e.name.substring(0, 10)}…' : e.name).toList(),
        barWidth: 14,
        compactCurrencyLeftTitles: false,
      ),
    );
  }

  Widget _buildBasketMixCard(ThemeData theme) {
    final palette = <Color>[
      theme.primaryColor,
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];
    final rows = _baskets.where((b) => ((b['total_amount'] as num?)?.toDouble() ?? 0) > 0).toList();
    if (rows.isEmpty) {
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
    for (var i = 0; i < rows.length; i++) {
      sections.add(ProPieSection(
        label: rows[i]['basket_name']?.toString() ?? 'Basket',
        value: (rows[i]['total_amount'] as num?)?.toDouble() ?? 0,
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

  Widget _buildBranches(ThemeData theme) {
    if (_branches.isEmpty) {
      return _emptyCard(theme, 'No branches linked to this organisation yet.');
    }
    return Column(children: _branches.map((b) => _buildBranchRow(theme, b)).toList());
  }

  Widget _buildBranchRow(ThemeData theme, Map<String, dynamic> branch) {
    final name = branch['name']?.toString() ?? 'Unnamed branch';
    final churchId = branch['id']?.toString();
    final members = _membersFor(churchId);
    final snapshot = _snapshotFor(churchId);
    final attendance = (snapshot?['attendance_mtd'] as num?)?.toInt() ?? 0;
    final giving = (snapshot?['tithes_mtd'] as num?)?.toDouble() ?? 0;
    final health = _branchHealth(branch);

    return GestureDetector(
      onTap: () => _showBranchSheet(branch, snapshot),
      child: Container(
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
              Row(children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                _healthBadge(health.$1, health.$2),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 12, runSpacing: 4, children: [
                _branchChip(Icons.people_outline, '$members members', theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                _branchChip(LucideIcons.calendarCheck, '$attendance attend', theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                _branchChip(LucideIcons.church, 'K${NumberFormat.compact().format(giving)} MTD', Colors.green.shade700),
              ]),
            ]),
          ),
          Icon(LucideIcons.chevronRight, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
        ]),
      ),
    );
  }

  /// Returns (label, color) for the branch health badge.
  (String, Color) _branchHealth(Map<String, dynamic> branch) {
    final verified = branch['is_verified'] == true;
    final endsAtRaw = branch['subscription_ends_at']?.toString();
    final endsAt = endsAtRaw != null ? DateTime.tryParse(endsAtRaw) : null;
    if (!verified) return ('UNVERIFIED', Colors.orange);
    if (endsAt == null) return ('NO PLAN', Colors.grey);
    if (endsAt.isAfter(DateTime.now())) return ('ACTIVE', Colors.green);
    return ('EXPIRED', Colors.red);
  }

  Widget _healthBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
    );
  }

  Widget _branchChip(IconData icon, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    ]);
  }

  void _showBranchSheet(Map<String, dynamic> branch, Map<String, dynamic>? snapshot) {
    final name = branch['name']?.toString() ?? 'Branch';
    final churchId = branch['id']?.toString();
    final members = _membersFor(churchId);
    final attendance = (snapshot?['attendance_mtd'] as num?)?.toInt() ?? 0;
    final giving = (snapshot?['tithes_mtd'] as num?)?.toDouble() ?? 0;
    final reports = (snapshot?['service_reports_mtd'] as num?)?.toInt() ?? 0;
    final health = _branchHealth(branch);
    final currency = NumberFormat.compactCurrency(symbol: 'K');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(sheetContext).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(height: 5, width: 40, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 18),
            Row(children: [
              Icon(LucideIcons.church, color: Theme.of(sheetContext).primaryColor),
              const SizedBox(width: 12),
              Expanded(child: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              _healthBadge(health.$1, health.$2),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              _drillStat(sheetContext, '$members', 'Members', Icons.people_outline),
              _drillStat(sheetContext, '$attendance', 'Attendance', LucideIcons.calendarCheck),
              _drillStat(sheetContext, currency.format(giving), 'Giving MTD', LucideIcons.church),
              _drillStat(sheetContext, '$reports', 'Reports', LucideIcons.fileText),
            ]),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  if (churchId == null) return;
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => BranchOversightScreen(
                      tenantId: churchId,
                      name: name,
                      isVerified: branch['is_verified'] == true,
                      logoUrl: branch['logo_url']?.toString(),
                    ),
                  ));
                },
                icon: const Icon(LucideIcons.layoutDashboard, size: 16),
                label: const Text('OPEN BRANCH OVERSIGHT'),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    context.push('/branch-locator');
                  },
                  icon: const Icon(LucideIcons.map, size: 16),
                  label: const Text('MAP'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    context.push('/pastor-bishop-report');
                  },
                  icon: const Icon(LucideIcons.fileText, size: 16),
                  label: const Text('PASTOR REPORTS'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _drillStat(BuildContext context, String value, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: Theme.of(context).primaryColor),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
        ]),
      ),
    );
  }

  Widget _buildOrgCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(LucideIcons.globe, color: theme.primaryColor, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_orgName?.isNotEmpty == true ? _orgName! : 'Organisation',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 3),
            Text('$_branchCount branches • ${_formatCompact(_totalMembers)} members • $_activeStreams live',
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.55), fontSize: 11)),
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

  Widget _emptyCard(ThemeData theme, String msg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(20)),
        child: Center(child: Text(msg, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.45)))),
      );

  void _showLinkChurchSheet() {
    final orgId = _orgId;
    if (orgId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => LinkChurchSheet(orgId: orgId, onLinked: () {
        Navigator.pop(sheetContext);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Church linked to the organisation')));
        _loadDashboard();
      }),
    );
  }

  void _showCreateOrgDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Create Organisation'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            "Your church becomes the HQ of a new organisation network. You'll be its bishop, and you can link more churches to it.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Organisation name',
              hintText: 'e.g. Kingdom Chapel International',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final orgId = await ref.read(organizationServiceProvider).createOrganization(name);
              if (!mounted) return;
              if (orgId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not create organisation. Only bishops/pastors can create one.')),
                );
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Organisation created — your church is its HQ')),
              );
              ref.invalidate(profileProvider);
              _loadDashboard();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  String _formatCompact(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : n.toString();
}

class LinkChurchSheet extends StatefulWidget {
  final String orgId;
  final VoidCallback onLinked;

  const LinkChurchSheet({super.key, required this.orgId, required this.onLinked});

  @override
  State<LinkChurchSheet> createState() => LinkChurchSheetState();
}

class LinkChurchSheetState extends State<LinkChurchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _churches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_loadChurches);
    _loadChurches();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChurches() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final query = _searchCtrl.text.trim();
      var req = client
          .from('churches')
          .select('id, name, is_verified')
          .eq('is_verified', true)
          .isFilter('organization_id', null);
      if (query.isNotEmpty) req = req.ilike('name', '%$query%');
      final res = await req.order('name').limit(50);
      if (mounted) {
        setState(() {
          _churches = List<Map<String, dynamic>>.from(res);
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _link(Map<String, dynamic> church) async {
    final id = church['id']?.toString();
    if (id == null) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.rpc('link_church_to_org', params: {
        'p_church_id': id,
        'p_org_id': widget.orgId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${church['name']} linked to the organisation')),
      );
      widget.onLinked();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(children: [
        Container(margin: const EdgeInsets.all(15), height: 5, width: 40, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Row(children: [
            Icon(LucideIcons.link, color: theme.primaryColor),
            const SizedBox(width: 12),
            const Expanded(child: Text('LINK A CHURCH', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.1))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search verified churches…',
              prefixIcon: const Icon(LucideIcons.search, size: 20),
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
                  : _churches.isEmpty
                      ? const Center(child: Text('No unlinked verified churches found.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _churches.length,
                          itemBuilder: (context, index) {
                            final c = _churches[index];
                            return Card(
                              elevation: 0,
                              color: theme.colorScheme.surface,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              child: ListTile(
                                leading: Icon(LucideIcons.church, color: theme.primaryColor),
                                title: Text(c['name']?.toString() ?? 'Unnamed', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: const Text('Verified church — not yet linked'),
                                trailing: FilledButton(onPressed: () => _link(c), child: const Text('LINK')),
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
