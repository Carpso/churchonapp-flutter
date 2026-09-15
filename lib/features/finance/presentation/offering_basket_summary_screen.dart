import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/utils/money.dart';
import 'package:church_on_app/features/finance/data/offering_basket_service.dart';
import 'widgets/basket_visuals.dart';

/// Pastor / bishop basket report.
///
/// A church leader sees their own church's basket totals; a bishop (or other
/// organisation leader) can roll the whole organisation up. All aggregation is
/// done server-side in `get_basket_summary()`.
class OfferingBasketSummaryScreen extends ConsumerStatefulWidget {
  const OfferingBasketSummaryScreen({super.key});

  @override
  ConsumerState<OfferingBasketSummaryScreen> createState() =>
      _OfferingBasketSummaryScreenState();
}

class _OfferingBasketSummaryScreenState
    extends ConsumerState<OfferingBasketSummaryScreen> {
  static const _orgRoles = {
    'bishop',
    'apostle',
    'prophet',
    'general_secretary',
    'general_treasurer',
    'superadmin',
    'super_admin',
    'coa_employee',
    'employee',
  };

  int _days = 30;
  bool _orgWide = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).value;
    final tenant = ref.watch(currentTenantProvider);
    final isOrgLeader = profile != null && _orgRoles.contains(profile.role);
    final orgId = isOrgLeader ? tenant?.organizationId : null;

    if (!_orgWide || orgId == null) {
      _orgWide = false;
    }

    final key = (
      tenantId: _orgWide ? null : tenant?.id,
      orgId: _orgWide ? orgId : null,
      days: _days,
    );
    final summaryAsync = ref.watch(basketSummaryProvider(key));

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: const Text('Basket Report')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(basketSummaryProvider(key)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            _windowChips(theme),
            if (isOrgLeader && orgId != null) ...[
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: false,
                      label: Text('My church'),
                      icon: Icon(LucideIcons.church, size: 16)),
                  ButtonSegment(
                      value: true,
                      label: Text('Organisation'),
                      icon: Icon(LucideIcons.network, size: 16)),
                ],
                selected: {_orgWide},
                onSelectionChanged: (v) =>
                    setState(() => _orgWide = v.first),
              ),
            ],
            const SizedBox(height: 18),
            summaryAsync.when(
              data: (rows) => _body(theme, rows),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(LucideIcons.alertTriangle,
                        size: 42, color: Colors.red.shade300),
                    const SizedBox(height: 10),
                    Text('Could not load report.\n$e',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _windowChips(ThemeData theme) {
    return Wrap(
      spacing: 8,
      children: [7, 30, 90].map((d) {
        return ChoiceChip(
          label: Text(d == 7 ? 'This week' : (d == 30 ? '30 days' : '90 days')),
          selected: _days == d,
          onSelected: (_) => setState(() => _days = d),
        );
      }).toList(),
    );
  }

  Widget _body(ThemeData theme, List<BasketSummaryRow> rows) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(LucideIcons.inbox,
                size: 36,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 10),
            Text(
              'No offerings recorded in this window. Open an offering from the '
              'Basket Manager and members\' gifts will roll up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    final total = rows.fold<double>(0, (s, r) => s + r.totalAmount);
    final maxAmount =
        rows.map((r) => r.totalAmount).fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              theme.primaryColor,
              theme.primaryColor.withValues(alpha: 0.75),
            ]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_orgWide ? 'ORGANISATION TOTAL' : 'CHURCH TOTAL',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1)),
              const SizedBox(height: 8),
              Text(formatKwacha(total),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                '${rows.length} basket(s) · last $_days days',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('BY BASKET',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        const SizedBox(height: 10),
        ...rows.map((r) => _row(theme, r, total, maxAmount)),
      ],
    );
  }

  Widget _row(ThemeData theme, BasketSummaryRow r, double total, double maxAmount) {
    final color = BasketVisuals.colorFor(null);
    final pct = total <= 0 ? 0.0 : (r.totalAmount / total);
    final barFrac = maxAmount <= 0 ? 0.0 : (r.totalAmount / maxAmount);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(r.basketName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                    if (r.basketCode != null &&
                        r.basketCode!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(r.basketCode!,
                          style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5))),
                    ],
                    if (r.scope == 'organisation') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('ORG',
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                color: theme.primaryColor)),
                      ),
                    ],
                  ],
                ),
              ),
              Text(formatKwacha(r.totalAmount),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: theme.primaryColor)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: barFrac,
              minHeight: 7,
              backgroundColor: theme.colorScheme.surface,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('${(pct * 100).toStringAsFixed(0)}% of total',
                  style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
              const Spacer(),
              Text(
                '${r.sessions} session(s)'
                '${r.lastTakenAt != null ? ' · last ${_date(r.lastTakenAt!)}' : ''}',
                style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _date(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
}
