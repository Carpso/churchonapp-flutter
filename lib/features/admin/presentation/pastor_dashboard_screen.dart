import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'global_broadcast_screen.dart';

class PastorDashboardScreen extends ConsumerStatefulWidget {
  const PastorDashboardScreen({super.key});

  @override
  ConsumerState<PastorDashboardScreen> createState() => _PastorDashboardScreenState();
}

class _PastorDashboardScreenState extends ConsumerState<PastorDashboardScreen> {
  bool _isLoading = true;
  int _memberCount = 0;
  int _sermonCount = 0;
  int _attendanceCount = 0;
  double _givingTotal = 0.0;
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
      setState(() => _isLoading = false);
      return;
    }

    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);

    try {
      final memberRes = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('tenant_id', tenantId);

      final sermonRes = await Supabase.instance.client
          .from('klips')
          .select('id')
          .eq('tenant_id', tenantId)
          .gte('created_at', firstOfMonth.toIso8601String());

      final attendanceRes = await Supabase.instance.client
          .from('attendance_logs')
          .select('id')
          .eq('tenant_id', tenantId)
          .gte('created_at', firstOfMonth.toIso8601String());

      final givingRes = await Supabase.instance.client
          .from('transactions')
          .select('amount')
          .eq('tenant_id', tenantId)
          .inFilter('type', ['giving', 'tithe', 'offering'])
          .gte('created_at', firstOfMonth.toIso8601String());

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

      double totalGiving = 0;
      for (final item in givingRes) {
        totalGiving += (item['amount'] as num?)?.toDouble() ?? 0;
      }

      if (mounted) {
        setState(() {
          _memberCount = (memberRes as List).length;
          _sermonCount = (sermonRes as List).length;
          _attendanceCount = (attendanceRes as List).length;
          _givingTotal = totalGiving;
          _recentMembers = List<Map<String, dynamic>>.from(recentMembersRes);
          _upcomingEvents = List<Map<String, dynamic>>.from(eventsRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _isLoading ? null : _loadDashboard,
          ),
        ],
      ),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text("Profile not found"));
          }
          return _buildBody(theme, profile);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text("Error: $e")),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, UserProfile profile) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryRow(theme),
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
          _buildQuickActions(theme, profile),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(ThemeData theme) {
    final currencyFormat = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: 1.2,
      children: [
        _buildStatCard(theme, "Total Members", _formatNumber(_memberCount), LucideIcons.users, Colors.blue),
        _buildStatCard(theme, "Sermons This Month", _formatNumber(_sermonCount), LucideIcons.bookOpen, Colors.amber),
        _buildStatCard(theme, "Attendance Avg", _formatNumber(_attendanceCount), LucideIcons.calendarCheck, Colors.green),
        _buildStatCard(theme, "Giving This Month", currencyFormat.format(_givingTotal), LucideIcons.heartPulse, Colors.red),
      ],
    );
  }

  Widget _buildStatCard(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildRecentMembers(ThemeData theme) {
    if (_recentMembers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Center(
          child: Text("No members found", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
        ),
      );
    }

    return Column(
      children: _recentMembers.map((member) {
        final name = member['full_name'] ?? 'Unknown';
        final role = member['role'] ?? 'member';
        final avatarUrl = member['avatar_url'];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null ? Icon(LucideIcons.user, size: 20, color: theme.colorScheme.primary) : null,
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
        );
      }).toList(),
    );
  }

  Widget _buildUpcomingEvents(ThemeData theme) {
    if (_upcomingEvents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Center(
          child: Text("No upcoming events", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
        ),
      );
    }

    return Column(
      children: _upcomingEvents.map((event) {
        final title = event['title'] ?? 'Untitled';
        final dateStr = event['date'];
        final location = event['location'] ?? '';
        final date = dateStr is String ? DateTime.tryParse(dateStr) : (dateStr is DateTime ? dateStr : null);
        final formattedDate = date != null ? DateFormat('MMM d, yyyy').format(date) : '';

        return Container(
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
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
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
                      Text(location, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 10)),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuickActions(ThemeData theme, UserProfile profile) {
    return Column(
      children: [
        _buildActionTile(
          theme,
          LucideIcons.bookOpen,
          "New Sermon",
          "Upload a sermon recording or message",
          Colors.orange,
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Navigate to Media Hub to upload a new sermon")),
            );
          },
        ),
        _buildActionTile(
          theme,
          LucideIcons.megaphone,
          "Send Broadcast",
          "Send push notification to your congregation",
          Colors.purple,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GlobalBroadcastScreen())),
        ),
        _buildActionTile(
          theme,
          LucideIcons.fileText,
          "View Reports",
          "Monthly stewardship and service reports",
          Colors.green,
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Navigate to Service Reports to view reports")),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionTile(ThemeData theme, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
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

  String _formatNumber(int number) {
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    }
    return number.toString();
  }
}
