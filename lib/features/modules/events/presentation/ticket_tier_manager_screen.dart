import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/events/data/event_ticketing_service.dart';

/// Host-side tier manager — create/edit/delete ticket tiers and cancel the
/// event. Tier writes go straight to `event_ticket_tiers` (host RLS); capacity
/// enforcement still happens server-side at reservation time.
class TicketTierManagerScreen extends ConsumerStatefulWidget {
  final String eventId;
  final String eventTitle;
  const TicketTierManagerScreen({super.key, required this.eventId, required this.eventTitle});

  @override
  ConsumerState<TicketTierManagerScreen> createState() => _TicketTierManagerScreenState();
}

class _TicketTierManagerScreenState extends ConsumerState<TicketTierManagerScreen> {
  @override
  Widget build(BuildContext context) {
    final tiersAsync = ref.watch(eventTicketTiersProvider(widget.eventId));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Manage Tickets', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(widget.eventTitle, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cancel event & refund',
            icon: const Icon(LucideIcons.xCircle, color: Colors.red),
            onPressed: _cancelEvent,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTierSheet(),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Add Tier'),
      ),
      body: tiersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load tiers.\n$e', textAlign: TextAlign.center)),
        data: (tiers) => tiers.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No ticket tiers yet. Add one to start selling tickets.',
                      textAlign: TextAlign.center),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: tiers.length,
                itemBuilder: (context, i) {
                  final t = tiers[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                            Text(
                              t.price == 0 ? 'FREE' : 'K${t.price.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (t.quantityTotal != null) '${t.quantitySold}/${t.quantityTotal} sold',
                            if (t.quantityTotal == null) '${t.quantitySold} sold (unlimited)',
                            if (t.salesEnd != null) 'ends ${DateFormat.yMMMd().format(t.salesEnd!)}',
                            if (!t.isActive) 'INACTIVE',
                          ].join('  •  '),
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => _openTierSheet(tier: t),
                              icon: const Icon(LucideIcons.pencil, size: 15),
                              label: const Text('Edit'),
                            ),
                            TextButton.icon(
                              onPressed: () => _deleteTier(t),
                              icon: const Icon(LucideIcons.trash2, size: 15, color: Colors.red),
                              label: const Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _deleteTier(EventTicketTier t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${t.name}"?'),
        content: const Text('Sold tickets are unaffected, but the tier will no longer be purchasable.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(eventTicketingServiceProvider).deleteTier(t.id);
      ref.invalidate(eventTicketTiersProvider(widget.eventId));
      if (mounted) PremiumToast.showSuccess(context, 'Tier deleted.', title: 'Deleted');
    } catch (e) {
      if (mounted) PremiumToast.showError(context, e.toString(), title: 'Delete Failed');
    }
  }

  Future<void> _cancelEvent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel event?'),
        content: const Text('All valid tickets will be cancelled and paid tickets refunded. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep event')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel event', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(eventTicketingServiceProvider).cancelEvent(eventId: widget.eventId, reason: 'Event cancelled by host');
      ref.invalidate(eventTicketTiersProvider(widget.eventId));
      if (mounted) PremiumToast.showSuccess(context, 'Event cancelled and tickets refunded.', title: 'Cancelled');
    } catch (e) {
      if (mounted) PremiumToast.showError(context, e.toString(), title: 'Cancel Failed');
    }
  }

  Future<void> _openTierSheet({EventTicketTier? tier}) async {
    final nameController = TextEditingController(text: tier?.name ?? '');
    final descController = TextEditingController(text: tier?.description ?? '');
    final priceController = TextEditingController(text: (tier?.price ?? 0).toString());
    final qtyController = TextEditingController(text: tier?.quantityTotal?.toString() ?? '');
    final maxController = TextEditingController(text: (tier?.maxPerOrder ?? 10).toString());
    DateTime? salesEnd = tier?.salesEnd;
    bool active = tier?.isActive ?? true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tier == null ? 'Add ticket tier' : 'Edit ticket tier',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 16),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (K)', border: OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacity (blank = ∞)', border: OutlineInputBorder()))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: maxController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max per order', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sales open'),
                  value: active,
                  onChanged: (v) => setSheet(() => active = v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sales end (early-bird cutoff)'),
                  subtitle: Text(salesEnd == null ? 'No end date' : DateFormat.yMMMd().format(salesEnd!)),
                  trailing: IconButton(
                    icon: const Icon(LucideIcons.calendar),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                        initialDate: salesEnd ?? DateTime.now().add(const Duration(days: 7)),
                      );
                      if (picked != null) setSheet(() => salesEnd = picked);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(ctx);
                    try {
                      await ref.read(eventTicketingServiceProvider).upsertTier(
                            id: tier?.id,
                            eventId: widget.eventId,
                            name: name,
                            description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                            price: double.tryParse(priceController.text.trim()) ?? 0,
                            quantityTotal: qtyController.text.trim().isEmpty ? null : int.tryParse(qtyController.text.trim()),
                            maxPerOrder: int.tryParse(maxController.text.trim()) ?? 10,
                            salesEnd: salesEnd,
                            sortOrder: tier?.sortOrder ?? 0,
                            isActive: active,
                          );
                      ref.invalidate(eventTicketTiersProvider(widget.eventId));
                      if (mounted) PremiumToast.showSuccess(context, 'Tier saved.', title: 'Saved');
                    } catch (e) {
                      if (mounted) PremiumToast.showError(context, e.toString(), title: 'Save Failed');
                    }
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                  child: const Text('SAVE TIER', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
