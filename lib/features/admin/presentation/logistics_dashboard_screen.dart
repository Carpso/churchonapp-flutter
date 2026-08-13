import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/stats_provider.dart';

class LogisticsDashboardScreen extends ConsumerStatefulWidget {
  const LogisticsDashboardScreen({super.key});

  @override
  ConsumerState<LogisticsDashboardScreen> createState() => _LogisticsDashboardScreenState();
}

class _LogisticsDashboardScreenState extends ConsumerState<LogisticsDashboardScreen> {
  int _totalRides = 0;
  int _completedRides = 0;
  int _pendingRides = 0;
  int _deliveriesDone = 0;
  int _weeklyMissions = 0;
  double _weeklyEarnings = 0;
  int _onlineCouriers = 0;

  @override
  void initState() {
    super.initState();
    _loadLogistics();
  }

  Future<void> _loadLogistics() async {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    try {
      final client = Supabase.instance.client;

      final ridesRes = await client
          .from('ride_bookings')
          .select('status, fare, created_at')
          .limit(1000);
      final rides = List<Map<String, dynamic>>.from(ridesRes);
      _totalRides = rides.length;
      _completedRides = rides.where((r) => (r['status'] ?? '').toString().toLowerCase() == 'completed').length;
      _pendingRides = rides.where((r) => (r['status'] ?? '').toString().toLowerCase() == 'pending').length;

      final deliveriesRes = await client
          .from('deliveries')
          .select('status, fee, created_at')
          .limit(1000);
      final deliveries = List<Map<String, dynamic>>.from(deliveriesRes);
      _deliveriesDone = deliveries.where((d) => (d['status'] ?? '').toString().toLowerCase() == 'delivered').length;

      for (final r in rides) {
        final dt = DateTime.tryParse(r['created_at']?.toString() ?? '');
        if (dt != null && dt.isAfter(weekAgo)) {
          _weeklyMissions++;
          if ((r['status'] ?? '').toString().toLowerCase() == 'completed') {
            _weeklyEarnings += (r['fare'] as num?)?.toDouble() ?? 0;
          }
        }
      }
      for (final d in deliveries) {
        final dt = DateTime.tryParse(d['created_at']?.toString() ?? '');
        if (dt != null && dt.isAfter(weekAgo)) {
          _weeklyMissions++;
          if ((d['status'] ?? '').toString().toLowerCase() == 'delivered') {
            _weeklyEarnings += (d['fee'] as num?)?.toDouble() ?? 0;
          }
        }
      }

      final couriersRes = await client
          .from('profiles')
          .select('id')
          .eq('driver_status', 'online')
          .limit(500);
      _onlineCouriers = List<Map<String, dynamic>>.from(couriersRes).length;
    } catch (e) {
      debugPrint('Logistics dashboard load failed: $e');
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(adminStatsProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text("Logistics Command", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _loadLogistics)],
      ),
      body: statsAsync.when(
        data: (stats) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminStatsProvider);
            await _loadLogistics();
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHighlightGrid(theme, stats),
                const SizedBox(height: 40),
                Text("Active Operations", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 20),
                _buildOperationTile(
                  theme,
                  LucideIcons.car,
                  "Total Ride Requests",
                  "$_totalRides requests • $_completedRides completed • $_pendingRides pending",
                  Colors.blue,
                ),
                _buildOperationTile(
                  theme,
                  LucideIcons.package,
                  "Cargo",
                  "${stats.pendingCargo} pending • $_deliveriesDone delivered",
                  Colors.orange,
                ),
                _buildOperationTile(
                  theme,
                  LucideIcons.truck,
                  "Couriers",
                  "$_onlineCouriers drivers online now (${stats.activeCouriers} total on duty)",
                  Colors.green,
                ),
                const SizedBox(height: 30),
                _buildPerformanceCard(context),
              ],
            ),
          ),
        ),
        loading: () => Center(child: CircularProgressIndicator(color: theme.primaryColor)),
        error: (e, s) => Center(child: Text("Error: $e")),
      ),
    );
  }

  String get _successRate {
    if (_totalRides == 0) return '--';
    final pct = (_completedRides / _totalRides * 100).round();
    return '$pct%';
  }

  String get _fleetHealth {
    if (_onlineCouriers >= 5) return 'Good';
    if (_onlineCouriers >= 2) return 'Fair';
    return _onlineCouriers == 0 ? 'Idle' : 'Low';
  }

  Widget _buildHighlightGrid(ThemeData theme, AdminStats stats) {
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 15,
      mainAxisSpacing: 15,
      childAspectRatio: 1.2,
      children: [
        _buildHighlightCard(theme, "SUCCESS RATE", _successRate, LucideIcons.checkCircle, Colors.green),
        _buildHighlightCard(theme, "COMPLETED", "$_completedRides rides", LucideIcons.clock, Colors.blue),
        _buildHighlightCard(theme, "ACTIVE MISSIONS", stats.totalMissions.toString(), LucideIcons.zap, Colors.amber),
        _buildHighlightCard(theme, "FLEET HEALTH", _fleetHealth, LucideIcons.activity, Colors.purple),
      ],
    );
  }

  Widget _buildHighlightCard(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis),
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildOperationTile(ThemeData theme, IconData icon, String title, String subtitle, Color color) {
    return Container(
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
    );
  }

  Widget _buildPerformanceCard(BuildContext context) {
    final theme = Theme.of(context);
    final earningsText = _weeklyEarnings >= 1000
        ? 'K ${(_weeklyEarnings / 1000).toStringAsFixed(1)}k'
        : 'K ${_weeklyEarnings.toStringAsFixed(0)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Live Intelligence", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          const Text("Last 7 days of ride and cargo activity across all zones.", style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStat("$_weeklyMissions", "Weekly trips"),
              _buildMiniStat(earningsText, "7-day earnings"),
              _buildMiniStat("$_onlineCouriers", "Couriers online"),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMiniStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }
}
