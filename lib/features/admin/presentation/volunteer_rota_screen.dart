import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/app_error_view.dart';
import '../data/care_service.dart';

/// Item 9 — Volunteer rota, lite.
///
/// "Who is serving on which date" and nothing more: no availability engine, no
/// auto-scheduling. The nudge is a WhatsApp deep link the leader taps, so the
/// app never sends anything on its own.
class VolunteerRotaScreen extends ConsumerWidget {
  const VolunteerRotaScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(volunteerRotaProvider(tenantId));
    final day = DateFormat('EEE d MMM');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Serving Rota',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () =>
                ref.invalidate(volunteerRotaProvider(tenantId)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _assign(context, ref),
        icon: const Icon(LucideIcons.userPlus),
        label: const Text('ADD SERVING SLOT'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(volunteerRotaProvider(tenantId)),
        ),
        data: (slots) {
          if (slots.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.calendarClock,
                        size: 64, color: Colors.grey.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    const Text('No one is rostered yet',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Add who is serving and when. Then nudge them on WhatsApp before the service.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            );
          }
          // Group by service date.
          final byDate = <String, List<VolunteerSlot>>{};
          for (final s in slots) {
            byDate.putIfAbsent(day.format(s.serviceDate), () => []).add(s);
          }
          final dates = byDate.keys.toList()..sort();

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(volunteerRotaProvider(tenantId)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final d in dates) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 6),
                    child: Text(d,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  for (final s in byDate[d]!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(LucideIcons.userCheck,
                                  size: 18, color: theme.primaryColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      s.userName ?? 'Volunteer',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(s.roleLabel,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600])),
                                ],
                              ),
                            ),
                            // WhatsApp nudge — the leader taps to send, we
                            // never message anyone on our own.
                            IconButton(
                              tooltip: s.isNotified
                                  ? 'Nudged'
                                  : 'Nudge on WhatsApp',
                              onPressed: (s.phoneNumber == null ||
                                      s.phoneNumber!.isEmpty)
                                  ? null
                                  : () async {
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      final url = Uri.parse(
                                        'https://wa.me/${_digits(s.phoneNumber!)}'
                                        '?text=${Uri.encodeComponent('Hello ${s.userName ?? ''}, you are serving as ${s.roleLabel} on ${day.format(s.serviceDate)}. See you then! God bless.')}');
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(
                                            url,
                                            mode: LaunchMode.externalApplication);
                                        await ref
                                            .read(careServiceProvider)
                                            .markNotified(s.id);
                                        ref.invalidate(
                                            volunteerRotaProvider(tenantId));
                                      } else {
                                        messenger.showSnackBar(const SnackBar(
                                            content: Text(
                                                'Could not open WhatsApp')));
                                      }
                                    },
                              icon: Icon(
                                  s.isNotified
                                      ? LucideIcons.checkCircle
                                      : LucideIcons.messageCircle,
                                  size: 20,
                                  color: s.isNotified
                                      ? Colors.green
                                      : Colors.green.shade700),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              onPressed: () async {
                                await ref
                                    .read(careServiceProvider)
                                    .removeVolunteer(s.id);
                                ref.invalidate(volunteerRotaProvider(tenantId));
                              },
                              icon: const Icon(LucideIcons.trash2,
                                  size: 18, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _digits(String phone) {
    var p = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('0')) p = '260${p.substring(1)}';
    return p;
  }

  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    final nameCtl = TextEditingController();
    final phoneCtl = TextEditingController();
    final roleCtl = TextEditingController(text: 'Usher');
    DateTime date = DateTime.now();

    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add Serving Slot'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(LucideIcons.calendar),
                    title: const Text('Service date'),
                    subtitle:
                        Text(DateFormat('EEE d MMM yyyy').format(date)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 7)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 180)),
                      );
                      if (picked != null) setState(() => date = picked);
                    },
                  ),
                  TextField(
                    controller: nameCtl,
                    decoration:
                        const InputDecoration(labelText: 'Volunteer name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtl,
                    decoration: const InputDecoration(
                        labelText: 'WhatsApp number',
                        hintText: '0977 000 000'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: roleCtl,
                    decoration: const InputDecoration(
                        labelText: 'Serving role',
                        hintText: 'Usher, pianist, sound, welcome…'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('CANCEL')),
            FilledButton(
              onPressed: () {
                final name = nameCtl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx, [name, phoneCtl.text.trim()]);
              },
              child: const Text('ADD'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !context.mounted) return;
    final service = ref.read(careServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    // Prefer a real member id when the typed name matches someone, so the
    // roster links to their profile; otherwise store it as a manual slot.
    try {
      final hits = await service.searchPeople(tenantId, result[0], limit: 5);
      final exact = hits
          .where((h) => h.name.toLowerCase() == result[0].toLowerCase().trim())
          .toList();
      final match = exact.isNotEmpty ? exact.first : null;
      await service.assignVolunteer(
        tenantId: tenantId,
        userId: match?.id,
        volunteerName: match == null ? result[0] : null,
        phoneNumber: result[1],
        roleLabel: roleCtl.text.trim(),
        serviceDate: date,
        notes: match == null ? 'Added manually' : null,
      );
      ref.invalidate(volunteerRotaProvider(tenantId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not add: $e'), backgroundColor: Colors.red));
    }
  }
}
