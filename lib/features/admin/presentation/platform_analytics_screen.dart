import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/widgets/pro_charts.dart';

class PlatformAnalyticsScreen extends ConsumerStatefulWidget {
  const PlatformAnalyticsScreen({super.key});

  @override
  ConsumerState<PlatformAnalyticsScreen> createState() => _PlatformAnalyticsScreenState();
}

class _PlatformAnalyticsScreenState extends ConsumerState<PlatformAnalyticsScreen> {
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats({int days = 30}) async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc('get_platform_engagement_stats', params: {'p_days': days});
      if (mounted) setState(() { _stats = Map<String, dynamic>.from(res as Map? ?? {}); _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Engagement Analytics')), body: const Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Engagement Analytics'),
        actions: [
          PopupMenuButton<int>(
            onSelected: (d) => _loadStats(days: d),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 7, child: Text('Last 7 days')),
              const PopupMenuItem(value: 30, child: Text('Last 30 days')),
              const PopupMenuItem(value: 90, child: Text('Last 90 days')),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Last ${_stats['period_days'] ?? 30} days', style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 16),
        _metricCard('Bible Audio Plays', '${_stats['bible_audio_plays'] ?? 0}', LucideIcons.headphones, theme.primaryColor.withValues(alpha: 0.8)),
        _metricCard('Podcast Listens', '${_stats['podcast_listens'] ?? 0}', LucideIcons.radio, Colors.amber),
        _metricCard('Kids Activities', '${_stats['kids_activities'] ?? 0}', LucideIcons.gamepad2, theme.primaryColor.withValues(alpha: 0.7)),
        _metricCard('Kids Active Users', '${_stats['kids_active_users'] ?? 0}', LucideIcons.users, theme.primaryColor.withValues(alpha: 0.55)),
        _metricCard('Quiz Sessions', '${_stats['quiz_sessions'] ?? 0}', LucideIcons.helpCircle, Colors.orange),
        ProChartCard(
          title: 'Engagement Distribution',
          subtitle: 'Share of activity in period',
          height: 240,
          child: _buildChart(),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
          child: const Row(children: [
            Icon(LucideIcons.info, color: Colors.green, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text('These metrics help COA understand how congregations engage with Bible audio, Kids Zone, and quizzes. Use this data to improve content and plan features.', style: TextStyle(fontSize: 12, color: Colors.grey))),
          ]),
        ),
      ]),
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color, size: 20)),
        title: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        subtitle: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _buildChart() {
    final data = [
      (_stats['bible_audio_plays'] as num?)?.toDouble() ?? 0,
      (_stats['podcast_listens'] as num?)?.toDouble() ?? 0,
      (_stats['kids_activities'] as num?)?.toDouble() ?? 0,
      (_stats['quiz_sessions'] as num?)?.toDouble() ?? 0,
    ];
    final total = data.fold<double>(0, (a, b) => a + b);
    return ProPieChart(
      centerValue: total > 0 ? total.toStringAsFixed(0) : '0',
      centerLabel: 'EVENTS',
      sections: [
        ProPieSection(label: 'Bible Audio', value: data[0], color: Theme.of(context).primaryColor.withValues(alpha: 0.85)),
        ProPieSection(label: 'Podcast', value: data[1], color: const Color(0xFFF59E0B)),
        ProPieSection(label: 'Kids Zone', value: data[2], color: const Color(0xFF6366F1)),
        ProPieSection(label: 'Quiz', value: data[3], color: const Color(0xFF14B8A6)),
      ],
    );
  }
}
