import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/services/tenant_service.dart';
import '../data/stream_analytics_service.dart';

/// Streaming analytics dashboard.
///
/// Used in two modes:
///  - tenant mode  (`platform: false`, `tenantId` set): a church's leadership
///    sees their own services, viewers, watch-time, retention and CF cost.
///  - platform mode (`platform: true`): COA staff see the whole network plus a
///    per-church cost breakdown.
class StreamAnalyticsScreen extends ConsumerStatefulWidget {
  final String? tenantId;
  final bool platform;

  const StreamAnalyticsScreen({
    super.key,
    this.tenantId,
    this.platform = false,
  });

  @override
  ConsumerState<StreamAnalyticsScreen> createState() =>
      _StreamAnalyticsScreenState();
}

class _StreamAnalyticsScreenState extends ConsumerState<StreamAnalyticsScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Tenant mode resolves the currently-selected church automatically.
    final resolvedTenant = widget.platform
        ? ''
        : (widget.tenantId ??
            ref.watch(currentTenantProvider.select((t) => t?.id)) ??
            '');
    final async = ref.watch(streamAnalyticsProvider((
      tenantId: resolvedTenant,
      days: _days,
      platform: widget.platform,
    )));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.platform ? 'Network Streaming Analytics' : 'Streaming Analytics'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Period',
            icon: const Icon(LucideIcons.calendarRange),
            initialValue: _days,
            onSelected: (v) => setState(() => _days = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 7, child: Text('Last 7 days')),
              PopupMenuItem(value: 30, child: Text('Last 30 days')),
              PopupMenuItem(value: 90, child: Text('Last 90 days')),
            ],
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            onPressed: () => ref.invalidate(streamAnalyticsProvider((
              tenantId: resolvedTenant,
              days: _days,
              platform: widget.platform,
            ))),
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.alertTriangle, color: Colors.orange, size: 36),
                const SizedBox(height: 12),
                Text('Could not load analytics', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text('$e', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('No analytics available'));
          }
          final totals = (data['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
          final daily = (data['daily'] as List?) ?? const [];
          final services = (data['services'] as List?) ?? const [];
          final byChurch = (data['by_church'] as List?) ?? const [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _periodLabel(),
              const SizedBox(height: 12),
              _kpiWrap(totals),
              const SizedBox(height: 20),
              _sectionTitle('Watch minutes over time'),
              _dailyBars(daily),
              const SizedBox(height: 20),
              if (widget.platform && byChurch.isNotEmpty) ...[
                _sectionTitle('Cost by church'),
                ...byChurch.map((e) => _churchRow((e as Map).cast<String, dynamic>())),
                const SizedBox(height: 20),
              ],
              if (services.isNotEmpty) ...[
                _sectionTitle('Services'),
                ...services.map((e) => _serviceCard((e as Map).cast<String, dynamic>())),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No streamed services in this period yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _periodLabel() => Row(
        children: [
          const Icon(LucideIcons.activity, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('Last $_days days',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        ],
      );

  Widget _kpiWrap(Map<String, dynamic> t) {
    final items = <List<Object?>>[
      ['Services', _n(t['services'])],
      ['Peak viewers', _n(t['peak_viewers'])],
      ['Unique viewers', _n(t['unique_viewers'])],
      ['Watch minutes', _n(t['watch_minutes'])],
      ['Avg watch / viewer', '${_n(t['avg_watch_minutes'])} min'],
      ['Broadcast minutes', _n(t['broadcast_minutes'])],
      ['CF delivered min', _n(t['delivered_minutes'])],
      ['Cost (delivery)', 'K${_n(t['delivery_cost_kwacha'])}'],
      ['Cost (storage)', 'K${_n(t['storage_cost_kwacha'])}'],
      if (widget.platform) ['Total cost', 'K${_n(t['total_cost_kwacha'])}'],
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map((i) => _kpiCard(i[0] as String, i[1] as String))
          .toList(),
    );
  }

  Widget _kpiCard(String label, String value) {
    final theme = Theme.of(context);
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Container(width: 4, height: 16, decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
      );

  Widget _dailyBars(List<dynamic> daily) {
    if (daily.isEmpty) {
      return const Text('No daily data yet.', style: TextStyle(color: Colors.grey));
    }
    final values = daily
        .map((d) => ((d as Map)['watch_minutes'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final maxV = values.fold<double>(0, (m, v) => v > m ? v : m);
    final theme = Theme.of(context);
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values.map((v) {
          final h = maxV <= 0 ? 2.0 : (v / maxV) * 100.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: '${v.toStringAsFixed(0)} min',
                    child: Container(
                      height: h.clamp(2.0, 100.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.45)],
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _churchRow(Map<String, dynamic> c) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_shortId(c['tenant_id']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text('${_n(c['services'])} services · ${_n(c['unique_viewers'])} viewers · ${_n(c['watch_minutes'])} min',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
              ],
            ),
          ),
          Text('K${_n(c['delivery_cost_kwacha'])}',
              style: TextStyle(fontWeight: FontWeight.w900, color: theme.primaryColor)),
        ],
      ),
    );
  }

  Widget _serviceCard(Map<String, dynamic> s) {
    final theme = Theme.of(context);
    final retention = (s['retention'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: theme.shadowColor.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((s['title'] ?? 'Service').toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text('${s['day']} · ${_n(s['peak_viewers'])} peak · ${_n(s['unique_viewers'])} unique · ${_n(s['watch_minutes'])} min watched',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          if (retention.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: retention.entries
                  .where((e) => e.key != '1' || true)
                  .map((e) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${e.key}m: ${((e.value as num) * 100).round()}%',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.primaryColor),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  static String _n(Object? v) {
    if (v == null) return '0';
    if (v is num) {
      if (v is double || v is int) {
        final d = v.toDouble();
        if (d == d.roundToDouble()) return d.toInt().toString();
        return d.toStringAsFixed(1);
      }
    }
    return v.toString();
  }

  static String _shortId(Object? id) {
    final s = id?.toString() ?? '';
    return s.length > 8 ? '${s.substring(0, 8)}…' : (s.isEmpty ? 'Unknown' : s);
  }
}
