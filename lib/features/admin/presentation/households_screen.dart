import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/widgets/app_error_view.dart';
import '../data/care_service.dart';

/// Item 2 — Households (families) as the unit of care.
///
/// One family record, many people, one giving envelope, one follow-up list.
/// Tapping a household shows its members and its giving statement.
class HouseholdsScreen extends ConsumerWidget {
  const HouseholdsScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(householdsProvider(tenantId));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Households',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () => ref.invalidate(householdsProvider(tenantId)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editHousehold(context, ref),
        icon: const Icon(LucideIcons.home),
        label: const Text('NEW HOUSEHOLD'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(householdsProvider(tenantId)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.home,
                        size: 64, color: Colors.grey.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    const Text('No households yet',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Group members into families so you can care for the whole household and issue one giving statement per envelope.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(householdsProvider(tenantId)),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final h = list[i];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(LucideIcons.home,
                            color: theme.primaryColor, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 3),
                            Text(
                              '${h.memberCount} member${h.memberCount == 1 ? '' : 's'}'
                              '${h.envelopeCode != null && h.envelopeCode!.isNotEmpty ? ' · ${h.envelopeCode}' : ''}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                            if (h.address != null && h.address!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  h.address!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500]),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Giving statement',
                        icon: const Icon(LucideIcons.receipt,
                            color: Colors.green, size: 20),
                        onPressed: () =>
                            _showStatement(context, ref, h),
                      ),
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(LucideIcons.pencil, size: 18),
                        onPressed: () => _editHousehold(context, ref, h),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _editHousehold(BuildContext context, WidgetRef ref,
      [Household? existing]) async {
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final addrCtl = TextEditingController(text: existing?.address ?? '');
    final phoneCtl = TextEditingController(text: existing?.phoneNumber ?? '');
    final envCtl = TextEditingController(text: existing?.envelopeCode ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New Household' : 'Edit Household'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Family name'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addrCtl,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtl,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: envCtl,
                decoration: const InputDecoration(
                    labelText: 'Giving envelope code (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );

    if (saved != true || !context.mounted) return;
    final name = nameCtl.text.trim();
    if (name.isEmpty) return;
    final service = ref.read(careServiceProvider);
    try {
      if (existing == null) {
        await service.createHousehold(
          onChanged: () => ref.invalidate(householdsProvider(tenantId)),
          tenantId: tenantId,
          name: name,
          address: addrCtl.text.trim(),
          phoneNumber: phoneCtl.text.trim(),
          envelopeCode: envCtl.text.trim(),
        );
      } else {
        await service.updateHousehold(existing.id, {
          'name': name,
          'address': addrCtl.text.trim(),
          'phone_number': phoneCtl.text.trim(),
          'envelope_code': envCtl.text.trim(),
        }, onChanged: () => ref.invalidate(householdsProvider(tenantId)));
      }
      ref.invalidate(householdsProvider(tenantId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not save: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  /// Item 2 (cont) — one giving statement per household envelope, computed
  /// server-side from `transactions` (never from a client-side sum).
  Future<void> _showStatement(
      BuildContext context, WidgetRef ref, Household h) async {
    final service = ref.read(careServiceProvider);
    final money = NumberFormat.currency(symbol: 'K ', decimalDigits: 2);
    Map<String, dynamic>? data;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${h.name} — Giving'),
        content: SizedBox(
          width: 340,
          child: FutureBuilder<Map<String, dynamic>>(
            future: service.householdGivingStatement(h.id),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return Text('Could not load statement:\n${snap.error}');
              }
              data = snap.data;
              final total = (snap.data?['total'] as num?)?.toDouble() ?? 0;
              final count = (snap.data?['transactions'] as num?)?.toInt() ?? 0;
              final members =
                  (snap.data?['members'] as List?) ?? const [];
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (h.envelopeCode != null && h.envelopeCode!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('Envelope ${h.envelopeCode}',
                            style: TextStyle(color: Colors.grey[600])),
                      ),
                    Text(money.format(total),
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.green)),
                    Text('$count contribution${count == 1 ? '' : 's'} this year',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const Divider(height: 24),
                    Text('HOUSEHOLD (${members.length})',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    for (final m in members)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '• ${m['full_name'] ?? 'Unnamed'}'
                          '${m['role'] != null ? ' (${m['role']})' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
        ],
      ),
    );
    if (data == null) return;
  }
}
