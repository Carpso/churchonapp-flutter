import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/pro_charts.dart';
import '../data/care_service.dart';

/// Item 8 — Visitor retention: who came once, who came back, who is regular,
/// month over month. This is the number that tells a pastor whether newcomers
/// are actually being assimilated or just passing through.
class VisitorRetentionScreen extends ConsumerWidget {
  const VisitorRetentionScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(retentionProvider(tenantId));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Visitor Retention',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          // Item 11 — recompute who is a "regular" from real attendance.
          IconButton(
            tooltip: 'Recalculate tags',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final r = await ref
                    .read(careServiceProvider)
                    .refreshAttendanceTags(tenantId);
                ref.invalidate(retentionProvider(tenantId));
                messenger.showSnackBar(SnackBar(
                    content: Text(
                        'Tagged ${r['regular'] ?? 0} regular, ${r['returning'] ?? 0} returning, ${r['inactive'] ?? 0} inactive.')));
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                    content: Text('Could not recalculate: $e'),
                    backgroundColor: Colors.red));
              }
            },
            icon: const Icon(LucideIcons.refreshCcw),
          ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () => ref.invalidate(retentionProvider(tenantId)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(retentionProvider(tenantId)),
        ),
        data: (r) {
          final buckets = <String, (int, Color)>{
            'First-time': (r.firstTime, Colors.amber),
            'Returning': (r.returning, Colors.teal),
            'Regular': (r.regular, Colors.green),
            'Members': (r.member, theme.primaryColor),
            'Gone quiet': (r.inactive, Colors.grey),
          };
          final sections = buckets.entries
              .where((e) => e.value.$1 > 0)
              .map((e) => ProPieSection(
                    label: e.key,
                    value: e.value.$1.toDouble(),
                    color: e.value.$2,
                  ))
              .toList();
          final total = buckets.values.fold<int>(0, (a, e) => a + e.$1);
          final months = r.months;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(retentionProvider(tenantId)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (total == 0)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Column(
                      children: [
                        Icon(LucideIcons.userX,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No attendance recorded yet',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 6),
                        Text(
                          'Retention needs attendance. Use QR Check-in or the member attendance screen on Sunday and this fills in automatically.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                else ...[
                  ProChartCard(
                    title: 'Where your people are',
                    height: 260,
                    child: ProPieChart(
                      sections: sections,
                      centerLabel: '$total',
                    ),
                  ),
                  const SizedBox(height: 18),
                  ProChartCard(
                    title: 'Attendance by month',
                    subtitle: 'Distinct people who checked in',
                    child: ProBarChart(
                      values: months.map((m) => m.attended.toDouble()).toList(),
                      labels: months.map((m) => m.month).toList(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ProChartCard(
                    title: 'First-time visitors by month',
                    subtitle: 'Their first ever service fell in this month',
                    child: ProBarChart(
                      values: months.map((m) => m.firstTime.toDouble()).toList(),
                      labels: months.map((m) => m.month).toList(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ProChartCard(
                    title: 'What this means',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _insight(
                          r.firstTime > 0,
                          '${r.firstTime} people are visiting for the first time. '
                              'Every one needs a welcome and a follow-up — see People to See Today.',
                        ),
                        _insight(
                          r.returning > 0,
                          '${r.returning} came back. That is the group worth investing in — invite them to a group.',
                        ),
                        _insight(
                          r.regular > 0,
                          '${r.regular} are now regular attenders (6+ services in 4 months).',
                        ),
                        _insight(
                          r.inactive > 0,
                          '${r.inactive} have not been seen in 60+ days. A phone call is usually enough.',
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _insight(bool show, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(show ? LucideIcons.checkCircle : LucideIcons.circle,
                size: 14, color: show ? Colors.green : Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, height: 1.35)),
            ),
          ],
        ),
      );
}
