import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/admin/presentation/widgets/pastor_telemetry_widget.dart';
import 'global_broadcast_screen.dart';
import 'member_management_screen.dart';
import 'media_upload_screen.dart';
import 'event_scheduler_screen.dart';
import 'service_report_screen.dart';
import 'finance_dashboard_screen.dart';
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
  int _memberCount = 0;
  int _sermonCount = 0;
  int _attendanceCount = 0;
  int _lastMonthAttendance = 0;
  double _givingTotal = 0.0;
  double _lastMonthGiving = 0.0;
  List<Map<String, dynamic>> _recentMembers = [];
  List<Map<String, dynamic>> _upcomingEvents = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    final profile = ref.read(profileProvider).value;
    final tenantId = profile?.tenantId;
    if (tenantId == null) {
      if (mounted) setState(() { _isLoading = false; _error = "No church assigned"; });
      return;
    }

    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final firstOfLastMonth = DateTime(now.year, now.month - 1, 1);

    try {
      final memberRes = await Supabase.instance.client
          .from('profiles')
          .select('id, created_at')
          .eq('tenant_id', tenantId);

      final sermonRes = await Supabase.instance.client
          .from('klips')
          .select('id')
          .eq('tenant_id', tenantId)
          .gte('created_at', firstOfMonth.toIso8601String());

      final attThisMonth = await Supabase.instance.client
          .from('attendance_logs')
          .select('id')
          .eq('tenant_id', tenantId)
          .gte('created_at', firstOfMonth.toIso8601String());

      final attLastMonth = await Supabase.instance.client
          .from('attendance_logs')
          .select('id')
          .eq('tenant_id', tenantId)
          .gte('created_at', firstOfLastMonth.toIso8601String())
          .lt('created_at', firstOfMonth.toIso8601String());

      final givingRes = await Supabase.instance.client
          .from('transactions')
          .select('amount')
          .eq('tenant_id', tenantId)
          .inFilter('type', ['giving', 'tithe', 'offering'])
          .gte('created_at', firstOfMonth.toIso8601String());

      final givingLastRes = await Supabase.instance.client
          .from('transactions')
          .select('amount')
          .eq('tenant_id', tenantId)
          .inFilter('type', ['giving', 'tithe', 'offering'])
          .gte('created_at', firstOfLastMonth.toIso8601String())
          .lt('created_at', firstOfMonth.toIso8601String());

      final recentMembersRes = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, role, avatar_url')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false)
          .limit(5);

      final eventsRes = await Supabase.instance.client
          .from('events')
          .select('id, title, date, location')
          .eq('tenant_id', tenantId)
          .gte('date', now.toIso8601String())
          .order('date', ascending: true)
          .limit(5);

      final members = (memberRes as List);

      double totalGiving = 0;
      for (final item in givingRes) {
        totalGiving += (item['amount'] as num?)?.toDouble() ?? 0;
      }
      double lastGiving = 0;
      for (final item in givingLastRes) {
        lastGiving += (item['amount'] as num?)?.toDouble() ?? 0;
      }

      if (mounted) {
        setState(() {
          _memberCount = members.length;
          _sermonCount = (sermonRes as List).length;
          _attendanceCount = (attThisMonth as List).length;
          _lastMonthAttendance = (attLastMonth as List).length;
          _givingTotal = totalGiving;
          _lastMonthGiving = lastGiving;
          _recentMembers = List<Map<String, dynamic>>.from(recentMembersRes);
          _upcomingEvents = List<Map<String, dynamic>>.from(eventsRes);
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

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Pastor Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFFAEB),
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _isLoading ? null : _loadDashboard),
        ],
      ),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) return const Center(child: Text("Profile not found"));
          return _buildBody(theme);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Error: $e")),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) return _buildShimmer();
    if (_error != null) return _buildError(theme);

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeHeader(theme),
            const SizedBox(height: 25),
            _buildSummaryRow(theme),
            const SizedBox(height: 25),
            PastorTelemetryWidget(
              totalTithes: _givingTotal * 0.6,
              totalOfferings: _givingTotal * 0.3,
              totalPledges: _givingTotal * 0.1,
              activeMembersCount: _memberCount,
              averageAttendance: _attendanceCount,
            ),
            const SizedBox(height: 35),
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

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.wifiOff, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text("Could not load dashboard", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadDashboard,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text("Retry"),
            ),
          ],
        ),
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
        gradient: LinearGradient(
          colors: [const Color(0xFF075E54), const Color(0xFF128C7E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF075E54).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                Text("Pastor Dashboard", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
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
    final currencyFormat = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    final attGrowth = _calcGrowth(_attendanceCount, _lastMonthAttendance);
    final givingGrowth = _calcGrowth(_givingTotal.round(), _lastMonthGiving.round());

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: 1.1,
      children: [
        _statCard(theme, "Total Members", _formatNumber(_memberCount), LucideIcons.users, Colors.blue, null),
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
        color: Colors.white,
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
                      Text("${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(0)}%", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: growth >= 0 ? Colors.green : Colors.red)),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 10)),
        ],
      ),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
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
                      if (location.isNotEmpty) Text(location, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 10)),
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
        _actionTile(theme, LucideIcons.video, "Upload Sermon", "Record or upload a sermon message", Colors.orange,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaUploadScreen()))),
        _actionTile(theme, LucideIcons.megaphone, "Send Broadcast", "Push notification to your congregation", Colors.purple,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalBroadcastScreen()))),
        _actionTile(theme, LucideIcons.barChart3, "View Finances", "Monthly stewardship and service reports", Colors.green,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceDashboardScreen()))),
        _actionTile(theme, LucideIcons.church, "Manage Ministries", "Oversee ministry groups and leaders", Colors.amber,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MinistryManagementScreen()))),
        _actionTile(theme, LucideIcons.award, "Baptism Registry", "Official baptism records and certificates", Colors.indigo,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BaptismRegistryScreen()))),
        _actionTile(theme, LucideIcons.fileText, "Service Reports", "Record and view service reports", Colors.teal,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServiceReportScreen()))),
        _actionTile(theme, LucideIcons.shieldCheck, "Content Moderation", "Review prayers & testimonies", Colors.purple,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContentModerationScreen()))),
        _actionTile(theme, LucideIcons.qrCode, "QR Check-in", "Scan QR codes for attendance tracking", Colors.blue,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceCheckinScreen()))),
        _actionTile(theme, LucideIcons.piggyBank, "Church Financial Hub", "Building funds, group contributions & goals", Colors.green,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChurchFinancialHubScreen()))),
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

  Widget _emptyCard(ThemeData theme, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Center(child: Text(message, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4)))),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}k';
    return number.toString();
  }
}
