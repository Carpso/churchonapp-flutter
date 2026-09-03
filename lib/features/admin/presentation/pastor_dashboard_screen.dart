import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'package:church_on_app/features/admin/data/organization_service.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/features/admin/presentation/widgets/pastor_telemetry_widget.dart';
import 'package:go_router/go_router.dart';
import 'church_invite_screen.dart';
import 'global_broadcast_screen.dart';
import 'member_management_screen.dart';
import 'media_upload_screen.dart';
import 'event_scheduler_screen.dart';
import 'service_report_screen.dart';
import 'ministry_management_screen.dart';
import 'baptism_registry_screen.dart';
import 'content_moderation_screen.dart';
import 'church_financial_hub_screen.dart';
import 'attendance_checkin_screen.dart';

class PastorDashboardScreen extends ConsumerStatefulWidget {
  const PastorDashboardScreen({super.key});

  @override
  ConsumerState<PastorDashboardScreen> createState() => _PastorDashboardScreenState();
}

class _PastorDashboardScreenState extends ConsumerState<PastorDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  String? _activeTenantId;
  List<Map<String, dynamic>> _adminChurches = [];
  int _memberCount = 0;
  int _sermonCount = 0;
  int _attendanceCount = 0;
  int _avgAttendance = 0;
  int _lastMonthAttendance = 0;
  double _givingTotal = 0.0;
  double _lastMonthGiving = 0.0;
  double _totalTithes = 0.0;
  double _totalOfferings = 0.0;
  bool _isMonthVerified = false;
  bool _isVerifying = false;
  List<Map<String, dynamic>> _recentMembers = [];
  List<Map<String, dynamic>> _upcomingEvents = [];
  List<Map<String, dynamic>> _givingSeries = [];
  List<Map<String, dynamic>> _recentGivers = [];
  Map<String, dynamic>? _latestServiceReport;
  int _visitorsMtd = 0;
  int _salvationsMtd = 0;
  int _followUpsDue = 0;

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
    // Superadmin/COA staff have no tenant — let them pick a church to view.
    final tenantId = _activeTenantId ?? profile.tenantId;
    if (tenantId == null) {
      try {
        final churches = await Supabase.instance.client
            .from('churches')
            .select('id, name')
            .eq('is_verified', true)
            .order('name');
        if (!mounted) return;
        if (churches.isEmpty) {
          setState(() { _isLoading = false; _error = "No verified churches found"; });
          return;
        }
        setState(() {
          _adminChurches = (churches as List).cast<Map<String, dynamic>>();
          _activeTenantId = _adminChurches.first['id'] as String;
        });
        await _loadDashboard();
        return;
      } catch (e) {
        if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
        return;
      }
    }

    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final firstOfLastMonth = DateTime(now.year, now.month - 1, 1);

    try {
      final client = Supabase.instance.client;

      // Check if current month is verified
      final verification = await client
          .from('local_monthly_verifications')
          .select('id')
          .eq('tenant_id', tenantId)
          .eq('month_year', DateFormat('yyyy-MM-01').format(now))
          .maybeSingle();

      final memberRes = await client
          .from('profiles')
          .select('id, created_at')
          .eq('tenant_id', tenantId);

      // "Sermons This Month" — real `sermons` table (NOT klips short-videos).
      int sermonCount = 0;
      try {
        final sermonsRes = await client
            .from('sermons')
            .select('id, created_at')
            .eq('tenant_id', tenantId);
        sermonCount = (sermonsRes as List)
            .where((s) {
              final c = s['created_at']?.toString();
              final dt = c != null ? DateTime.tryParse(c) : null;
              return dt != null && !dt.isBefore(firstOfMonth);
            })
            .length;
      } catch (e) {
        debugPrint("sermons count failed (fallback klips): $e");
        try {
          final sermonRes = await client
              .from('klips')
              .select('id')
              .eq('tenant_id', tenantId)
              .gte('created_at', firstOfMonth.toIso8601String());
          sermonCount = (sermonRes as List).length;
        } catch (_) {}
      }

      final attThisMonth = await client
          .from('attendance_logs')
          .select('id, created_at')
          .eq('tenant_id', tenantId)
          .gte('created_at', firstOfMonth.toIso8601String());

      final attLastMonth = await client
          .from('attendance_logs')
          .select('id')
          .eq('tenant_id', tenantId)
          .gte('created_at', firstOfLastMonth.toIso8601String())
          .lt('created_at', firstOfMonth.toIso8601String());

      final givingRes = await client
          .from('transactions')
          .select('amount, category')
          .eq('tenant_id', tenantId)
          .inFilter('category', ['giving', 'tithe', 'offering'])
          .gte('created_at', firstOfMonth.toIso8601String());

      final givingLastRes = await client
          .from('transactions')
          .select('amount')
          .eq('tenant_id', tenantId)
          .inFilter('category', ['giving', 'tithe', 'offering'])
          .gte('created_at', firstOfLastMonth.toIso8601String())
          .lt('created_at', firstOfMonth.toIso8601String());

      final recentMembersRes = await client
          .from('profiles')
          .select('id, full_name, role, avatar_url')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false)
          .limit(5);

      final eventsRes = await client
          .from('events')
          .select('id, title, date, location')
          .eq('tenant_id', tenantId)
          .gte('date', now.toIso8601String())
          .order('date', ascending: true)
          .limit(5);

      double totalGiving = 0, tithes = 0, offerings = 0;
      for (final item in givingRes) {
        final amt = (item['amount'] as num?)?.toDouble() ?? 0;
        totalGiving += amt;
        if (item['category'] == 'tithe') tithes += amt;
        if (item['category'] == 'offering') offerings += amt;
      }
      
      double lastGiving = 0;
      for (final item in givingLastRes) {
        lastGiving += (item['amount'] as num?)?.toDouble() ?? 0;
      }

      List<Map<String, dynamic>> givingSeries = [];
      List<Map<String, dynamic>> recentGivers = [];
      try {
        givingSeries = await ref
            .read(organizationServiceProvider)
            .getChurchGivingSeries(tenantId);
        final overview = await ref
            .read(financeServiceProvider)
            .getChurchGivingOverview(tenantId);
        final givers = overview.givers;
        recentGivers = givers.take(8).map((g) => {
              'name': g.name,
              'amount': g.amount,
              'created_at': g.createdAt.toIso8601String(),
            }).toList();
      } catch (e) {
        debugPrint("pastor giving series failed: $e");
      }

      // Average attendance: total check-ins ÷ distinct service-days this month.
      int avgAttendance = 0;
      try {
        final rows = attThisMonth as List;
        final dates = rows
            .map((a) {
              final c = a['created_at']?.toString() ?? '';
              return c.length >= 10 ? c.substring(0, 10) : c;
            })
            .where((d) => d.isNotEmpty)
            .toSet();
        if (dates.isNotEmpty) avgAttendance = (rows.length / dates.length).round();
      } catch (_) {}

      // Latest service report snapshot + MTD visitors/salvations + follow-ups.
      Map<String, dynamic>? latestReport;
      int visitorsMtd = 0, salvationsMtd = 0, followUps = 0;
      try {
        final report = await client
            .from('service_reports')
            .select('id, service_date, attendance, offering, visitors, salvations, title')
            .eq('tenant_id', tenantId)
            .order('service_date', ascending: false)
            .limit(1)
            .maybeSingle();
        latestReport = report != null ? Map<String, dynamic>.from(report) : null;
        final svcMonth = await client
            .from('service_reports')
            .select('visitors, salvations')
            .eq('tenant_id', tenantId)
            .gte('service_date', firstOfMonth.toIso8601String());
        for (final r in (svcMonth as List)) {
          visitorsMtd += (r['visitors'] as num?)?.toInt() ?? 0;
          salvationsMtd += (r['salvations'] as num?)?.toInt() ?? 0;
        }
      } catch (e) {
        debugPrint('service report fetch failed: $e');
      }
      try {
        final fu = await client
            .from('pastoral_followups')
            .select('id')
            .eq('tenant_id', tenantId)
            .eq('status', 'pending');
        followUps = (fu as List).length;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _memberCount = (memberRes as List).length;
          _sermonCount = sermonCount;
          _attendanceCount = (attThisMonth as List).length;
          _avgAttendance = avgAttendance;
          _lastMonthAttendance = (attLastMonth as List).length;
          _givingTotal = totalGiving;
          _totalTithes = tithes;
          _totalOfferings = offerings;
          _lastMonthGiving = lastGiving;
          _isMonthVerified = verification != null;
          _recentMembers = List<Map<String, dynamic>>.from(recentMembersRes);
          _upcomingEvents = List<Map<String, dynamic>>.from(eventsRes);
          _givingSeries = givingSeries;
          _recentGivers = recentGivers;
          _latestServiceReport = latestReport;
          _visitorsMtd = visitorsMtd;
          _salvationsMtd = salvationsMtd;
          _followUpsDue = followUps;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.value;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Pastor Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          if (profile?.tenantId == null && _adminChurches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _activeTenantId,
                  isDense: true,
                  items: _adminChurches
                      .map((c) => DropdownMenuItem(
                            value: c['id'] as String,
                            child: Text(
                              c['name']?.toString() ?? 'Church',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null && v != _activeTenantId) {
                      setState(() => _activeTenantId = v);
                      _loadDashboard();
                    }
                  },
                ),
              ),
            ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _isLoading ? null : _loadDashboard,
          ),
        ],
      ),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) return const Center(child: Text("Profile not found"));
          return _buildBody(theme);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(error: e, onRetry: _loadDashboard),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) return _buildShimmer();
    if (_error != null) return AppErrorView(error: _error, onRetry: _loadDashboard);

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeHeader(theme),
            const SizedBox(height: 20),
            if (!_isMonthVerified) _buildVerificationBanner(theme),
            const SizedBox(height: 25),
            _buildSummaryRow(theme),
            const SizedBox(height: 25),
            _buildGivingTrend(theme),
            const SizedBox(height: 25),
            _buildEngagementRow(theme),
            const SizedBox(height: 25),
            if (_recentGivers.isNotEmpty) ...[
              _buildRecentGivers(theme),
              const SizedBox(height: 35),
            ],
            PastorTelemetryWidget(
              totalTithes: _totalTithes,
              totalOfferings: _totalOfferings,
              totalPledges: _givingTotal - _totalTithes - _totalOfferings,
              activeMembersCount: _memberCount,
              averageAttendance: _avgAttendance,
            ),
            const SizedBox(height: 35),
            if (_latestServiceReport != null) ...[
              _buildLatestServiceReport(theme),
              const SizedBox(height: 35),
            ],
            Text("Recent Members", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 15),
            _buildRecentMembers(theme),
            const SizedBox(height: 35),
            Text("Upcoming Events", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 15),
            _buildUpcomingEvents(theme),
            const SizedBox(height: 35),
            Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 15),
            _buildQuickActions(theme),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.alertTriangle, color: Colors.amber, size: 18),
              const SizedBox(width: 10),
              const Expanded(child: Text("Monthly Reports Pending Sign-off", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              TextButton(
                onPressed: _showMonthlySignOff,
                child: const Text("SIGN OFF", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.amber)),
              ),
            ],
          ),
          const Text("Monthly metrics must be verified locally before network-wide aggregation.", style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  void _showMonthlySignOff() async {
    final now = DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy').format(now);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Monthly Verification: $monthLabel", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            const Text("I confirm that the following totals for this assembly are accurate and audited.", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 25),
            _signOffMetric("Total Attendance", "$_attendanceCount"),
            _signOffMetric("Total Tithes", "K ${NumberFormat.decimalPattern().format(_totalTithes)}"),
            _signOffMetric("Total Offerings", "K ${NumberFormat.decimalPattern().format(_totalOfferings)}"),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isVerifying
                  ? null
                  : () async {
                      if (_isVerifying) return;
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);
                      setState(() => _isVerifying = true);
                      final profile = ref.read(profileProvider).value;
                      if (profile == null) {
                        setState(() => _isVerifying = false);
                        return;
                      }
                      try {
                        // LOCK: upsert an immutable snapshot row. The
                        // UNIQUE(tenant_id, month_year) constraint is the
                        // lock — once written, the month cannot be
                        // re-verified or edited by another session.
                        final monthKey = DateFormat('yyyy-MM-01').format(now);
                        await Supabase.instance.client
                            .from('local_monthly_verifications')
                            .upsert({
                          'tenant_id': profile.tenantId,
                          'month_year': monthKey,
                          'verified_by': profile.id,
                          'total_attendance': _attendanceCount,
                          'total_tithes': _totalTithes,
                          'total_offerings': _totalOfferings,
                        }, onConflict: 'tenant_id,month_year');
                        navigator.pop();
                        await _loadDashboard();
                        if (mounted) {
                          messenger.showSnackBar(const SnackBar(content: Text("Monthly data verified, signed off & locked! 🚀"), backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        debugPrint('Sign-off error: $e');
                        if (mounted) setState(() => _isVerifying = false);
                        messenger.showSnackBar(const SnackBar(content: Text("Sign-off failed — please retry."), backgroundColor: Colors.red));
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              child: _isVerifying
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text("AUDIT & SIGN OFF", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _signOffMetric(String label, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        Text(val, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7A5C00), fontSize: 15)),
      ],
    ),
  );

  Widget _buildShimmer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        children: [
          ShimmerLoader.rectangular(height: 140, width: double.infinity),
          const SizedBox(height: 25),
          Row(children: [
            Expanded(child: ShimmerLoader.rectangular(height: 100)),
            const SizedBox(width: 15),
            Expanded(child: ShimmerLoader.rectangular(height: 100)),
          ]),
          const SizedBox(height: 15),
          Row(children: [
            Expanded(child: ShimmerLoader.rectangular(height: 100)),
            const SizedBox(width: 15),
            Expanded(child: ShimmerLoader.rectangular(height: 100)),
          ]),
          const SizedBox(height: 30),
          ShimmerLoader.rectangular(height: 18, width: 150),
          const SizedBox(height: 15),
          ...List.generate(3, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ShimmerLoader.rectangular(height: 70),
          )),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeader(ThemeData theme) {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF128C7E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF1A1A1A).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                const Text("Pastor Dashboard", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                const SizedBox(height: 6),
                Text("$_memberCount members • $_sermonCount sermons this month", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
            child: const Icon(LucideIcons.church, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }

  double _calcGrowth(int current, int previous) {
    if (previous == 0) return current > 0 ? 100 : 0;
    return ((current - previous) / previous * 100);
  }

  Widget _buildSummaryRow(ThemeData theme) {
    final currencyFormat = NumberFormat.compactCurrency(symbol: 'K ', decimalDigits: 1);
    final attGrowth = _calcGrowth(_attendanceCount, _lastMonthAttendance);
    final givingGrowth = _calcGrowth(
      _givingTotal.isFinite ? _givingTotal.round() : 0,
      _lastMonthGiving.isFinite ? _lastMonthGiving.round() : 0,
    );

    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: 1.1,
      children: [
        _statCard(theme, "Total Members", _formatNumber(_memberCount), LucideIcons.users, theme.primaryColor, null),
        _statCard(theme, "Sermons This Month", _formatNumber(_sermonCount), LucideIcons.bookOpen, Colors.amber, null),
        _statCard(theme, "Attendance", _formatNumber(_attendanceCount), LucideIcons.calendarCheck, Colors.green, attGrowth),
        _statCard(theme, "Giving This Month", currencyFormat.format(_givingTotal), LucideIcons.heartPulse, Colors.red, givingGrowth),
      ],
    );
  }

  Widget _statCard(ThemeData theme, String label, String value, IconData icon, Color color, double? growth) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 22),
              if (growth != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: growth >= 0 ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(growth >= 0 ? LucideIcons.trendingUp : LucideIcons.trendingDown, size: 10, color: growth >= 0 ? Colors.green : Colors.red),
                      const SizedBox(width: 2),
                      Text(
                        "${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(0)}%",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: growth >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngagementRow(ThemeData theme) {
    return Row(
      children: [
        _engagementCard(theme, LucideIcons.userPlus, "$_visitorsMtd", "Visitors MTD", Colors.teal),
        const SizedBox(width: 12),
        _engagementCard(theme, LucideIcons.heartPulse, "$_salvationsMtd", "Salvations MTD", Colors.green),
        const SizedBox(width: 12),
        _engagementCard(theme, LucideIcons.clipboardList, "$_followUpsDue", "Follow-ups", Colors.orange),
      ],
    );
  }

  Widget _engagementCard(ThemeData theme, IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.55), fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestServiceReport(ThemeData theme) {
    final report = _latestServiceReport;
    if (report == null) return const SizedBox.shrink();
    final dateStr = report['service_date']?.toString();
    final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
    final title = report['title']?.toString() ?? 'Latest Service';
    final attendance = (report['attendance'] as num?)?.toInt() ?? 0;
    final offering = (report['offering'] as num?)?.toDouble() ?? 0;
    final visitors = (report['visitors'] as num?)?.toInt() ?? 0;
    final salvations = (report['salvations'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServiceReportScreen())),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [theme.primaryColor.withValues(alpha: 0.12), theme.primaryColor.withValues(alpha: 0.04)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Icon(LucideIcons.fileText, color: theme.primaryColor, size: 16)),
                const SizedBox(width: 10),
                Expanded(child: Text("Latest Service Report", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface))),
                if (date != null) Text(DateFormat('MMM d').format(date), style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
              ],
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 10),
            Row(
              children: [
                _reportStat(theme, "$attendance", "Attended", LucideIcons.calendarCheck, Colors.green),
                _reportStat(theme, NumberFormat.compactCurrency(symbol: 'K ').format(offering), "Offering", LucideIcons.church, theme.primaryColor),
                _reportStat(theme, "$visitors", "Visitors", LucideIcons.userPlus, Colors.teal),
                _reportStat(theme, "$salvations", "Saved", LucideIcons.heartPulse, Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportStat(ThemeData theme, String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildGivingTrend(ThemeData theme) {
    final currencyFormat = NumberFormat.compactCurrency(symbol: 'K ', decimalDigits: 1);
    final series = _givingSeries;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.trendingUp, color: theme.primaryColor, size: 18),
              const SizedBox(width: 8),
              Text("Giving Trend (6 months)", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 16),
          if (series.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text("No giving data yet", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 13)),
              ),
            )
          else
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in series)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            currencyFormat.format((point['total'] as num?)?.toDouble() ?? 0),
                            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 9),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: ((point['total'] as num?)?.toDouble() ?? 0) <= 0
                                ? 4
                                : 8 + (point['total'] as num).toDouble().clamp(0, 200) / 2,
                            decoration: BoxDecoration(
                              color: theme.primaryColor,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            point['month']?.toString() ?? '',
                            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentGivers(ThemeData theme) {
    final currencyFormat = NumberFormat.compactCurrency(symbol: 'K ', decimalDigits: 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Top Givers This Month", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        const SizedBox(height: 15),
        for (final giver in _recentGivers)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: theme.colorScheme.shadow.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(LucideIcons.heartPulse, color: Colors.green, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    giver['name']?.toString() ?? 'Anonymous',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: theme.colorScheme.onSurface),
                  ),
                ),
                Text(
                  currencyFormat.format((giver['amount'] as num?)?.toDouble() ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.green),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRecentMembers(ThemeData theme) {
    if (_recentMembers.isEmpty) return _emptyCard(theme, "No members found");
    return Column(
      children: _recentMembers.map((member) {
        final name = member['full_name'] ?? 'Unknown';
        final role = member['role'] ?? 'member';
        final avatarUrl = member['avatar_url'];
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberManagementScreen())),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 44, height: 44,
                  child: ClipOval(
                    child: avatarUrl != null
                        ? CachedNetworkImage(imageUrl: avatarUrl, width: 44, height: 44, memCacheWidth: 88, memCacheHeight: 88, fit: BoxFit.cover, errorWidget: (_, __, ___) => _avatarFallback(theme))
                        : _avatarFallback(theme),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
                      Text(role, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _avatarFallback(ThemeData theme) {
    return Container(color: theme.colorScheme.primary.withValues(alpha: 0.1), child: Icon(LucideIcons.user, size: 20, color: theme.colorScheme.primary));
  }

  Widget _buildUpcomingEvents(ThemeData theme) {
    if (_upcomingEvents.isEmpty) return _emptyCard(theme, "No upcoming events");
    return Column(
      children: _upcomingEvents.map((event) {
        final title = event['title'] ?? 'Untitled';
        final dateStr = event['date'];
        final location = event['location'] ?? '';
        final date = dateStr is String ? DateTime.tryParse(dateStr) : (dateStr is DateTime ? dateStr : null);
        final formattedDate = date != null ? DateFormat('MMM d, yyyy').format(date) : '';
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EventSchedulerScreen())),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(LucideIcons.calendarDays, color: Colors.amber, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
                      const SizedBox(height: 3),
                      Text(formattedDate, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                      if (location.isNotEmpty)
                        Text(
                          location,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuickActions(ThemeData theme) {
    return Column(
      children: [
            _actionTile(theme, LucideIcons.radio, "Go Live", "Start an HD live stream to your congregation", Colors.red,
              () => context.push('/live-studio'),),
            _actionTile(theme, LucideIcons.video, "Upload Sermon", "Record or upload a sermon message", Colors.orange,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaUploadScreen()))),
        _actionTile(theme, LucideIcons.megaphone, "Send Broadcast", "Push notification to your congregation", theme.primaryColor,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalBroadcastScreen()))),
        _actionTile(theme, LucideIcons.church, "Manage Ministries", "Oversee ministry groups and leaders", Colors.amber,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MinistryManagementScreen()))),
        _actionTile(theme, LucideIcons.award, "Baptism Registry", "Official baptism records and certificates", theme.primaryColor,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BaptismRegistryScreen()))),
        _actionTile(theme, LucideIcons.fileText, "Service Reports", "Record and view service reports", theme.primaryColor,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServiceReportScreen()))),
        _actionTile(theme, LucideIcons.bookOpen, "Finance Dashboard", "Church income, expenses & payouts", Colors.indigo,
          () => context.push('/finance-dashboard')),
        _actionTile(theme, LucideIcons.shieldCheck, "Content Moderation", "Review prayers & testimonies", theme.primaryColor,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContentModerationScreen()))),
        _actionTile(theme, LucideIcons.qrCode, "QR Check-in", "Scan QR codes for attendance tracking", theme.primaryColor,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceCheckinScreen()))),
         _actionTile(theme, LucideIcons.piggyBank, "Church Financial Hub", "Building funds, group contributions & goals", Colors.green,
           () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChurchFinancialHubScreen()))),
         _actionTile(theme, LucideIcons.userPlus, "Invite Members", "Share church invite link, QR code & more", theme.primaryColor,
           () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChurchInviteScreen()))),
       ],
     );
   }

  Widget _actionTile(ThemeData theme, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
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

  Widget _emptyCard(ThemeData theme, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(child: Text(message, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4)))),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}k';
    return number.toString();
  }
}
