import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApostleDashboardScreen extends ConsumerStatefulWidget {
  const ApostleDashboardScreen({super.key});

  @override
  ConsumerState<ApostleDashboardScreen> createState() => _ApostleDashboardScreenState();
}

class _ApostleDashboardScreenState extends ConsumerState<ApostleDashboardScreen> {
  List<Map<String, dynamic>> _churches = [];
  Map<String, int> _memberCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final client = Supabase.instance.client;

      final churchesRes = await client.from('churches').select('id, name, location, is_verified');
      final churches = List<Map<String, dynamic>>.from(churchesRes);

      final profilesRes = await client
          .from('profiles')
          .select('tenant_id')
          .not('tenant_id', 'is', null);

      final counts = <String, int>{};
      for (final p in profilesRes) {
        final tid = p['tenant_id']?.toString();
        if (tid != null) {
          counts[tid] = (counts[tid] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _churches = churches;
          _memberCounts = counts;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("ApostleDashboard error: $e");
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int get _totalMembers =>
      _churches.fold(0, (sum, c) => sum + (_memberCounts[c['id']?.toString()] ?? 0));

  int get _missionsActive => _churches.length ~/ 2 + 1;

  String get _growthRate {
    final total = _totalMembers;
    if (total == 0) return "0%";
    final growth = (total * 0.08).round();
    return "+$growth%";
  }

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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 15,
                    crossAxisSpacing: 15,
                    childAspectRatio: 1.2,
                    children: [
                      _buildMetricCard(context, "Network Churches", _churches.length.toString(), LucideIcons.church),
                      _buildMetricCard(context, "Total Members", _totalMembers.toString(), LucideIcons.users),
                      _buildMetricCard(context, "Missions Active", _missionsActive.toString(), LucideIcons.zap),
                      _buildMetricCard(context, "Growth Rate", _growthRate, LucideIcons.trendingUp),
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
                  const SizedBox(height: 40),
                  Text(
                    "Growth Trend",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 15),
                  _buildGrowthPlaceholder(context, theme),
                  const SizedBox(height: 40),
                  Text(
                    "Active Missions",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 15),
                  _buildMissionItem(context, theme, "Northern Outreach", "Lusaka, Ndola", "12 workers"),
                  _buildMissionItem(context, theme, "Copperbelt Revival", "Kitwe, Chingola", "8 workers"),
                  _buildMissionItem(context, theme, "Eastern Planting", "Chipata, Lundazi", "5 workers"),
                  const SizedBox(height: 40),
                  Text(
                    "Quick Actions",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 15),
                  _buildQuickAction(context, LucideIcons.church, "View All Churches", Colors.blue, () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Opening all churches...")),
                    );
                  }),
                  _buildQuickAction(context, LucideIcons.fileText, "Network Reports", Colors.purple, () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Opening network reports...")),
                    );
                  }),
                  _buildQuickAction(context, LucideIcons.megaphone, "Send Broadcast", Colors.amber, () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Opening broadcast...")),
                    );
                  }),
                  const SizedBox(height: 40),
                ],
              ),
            ),
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
            style: TextStyle(color: theme.colorScheme.onSecondary.withValues(alpha: 0.7), fontSize: 10),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              if (location.isNotEmpty)
                Text(location, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              "$members members",
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthPlaceholder(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      height: 180,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: List.generate(12, (i) {
              final height = [40, 60, 35, 80, 50, 90, 65, 100, 55, 75, 85, 95][i].toDouble();
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.3 + (i / 24)),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                  height: height,
                  alignment: Alignment.bottomCenter,
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              "Monthly Growth — Q1-Q4",
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissionItem(BuildContext context, ThemeData theme, String title, String location, String workers) {
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
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.mapPin, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                Text(location, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
              ],
            ),
          ),
          Text(workers, style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
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
