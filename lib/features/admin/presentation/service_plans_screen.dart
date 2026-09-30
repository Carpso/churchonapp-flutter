import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/widgets/app_error_view.dart';
import '../data/care_service.dart';

/// Item 5 — Order of service, lite.
///
/// Not a Planning Center clone: date, title, songs (from `worship_setlists`),
/// speakers, ushers, musicians, notes, and a publish-to-congregation toggle
/// (handled by the `publish_service_plan` RPC so `published_at` is server-set).
class ServicePlansScreen extends ConsumerWidget {
  const ServicePlansScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(servicePlansProvider(tenantId));
    final day = DateFormat('EEE d MMM yyyy');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Order of Service',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () => ref.invalidate(servicePlansProvider(tenantId)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editPlan(context, ref),
        icon: const Icon(LucideIcons.calendarPlus),
        label: const Text('NEW SERVICE'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(servicePlansProvider(tenantId)),
        ),
        data: (plans) {
          if (plans.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.clipboardList,
                        size: 64, color: Colors.grey.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    const Text('No services planned',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Plan the service once — songs, speakers and ushers in one place, then publish it to the congregation.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(servicePlansProvider(tenantId)),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: plans.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = plans[i];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: p.isPublished
                          ? Colors.green.withValues(alpha: 0.35)
                          : Colors.transparent,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(day.format(p.serviceDate),
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 2),
                                Text(p.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                              ],
                            ),
                          ),
                          if (p.isPublished)
                            const Chip(
                              label: Text('PUBLISHED',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.green)),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      if (p.setlistTitle != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(LucideIcons.music,
                                size: 13, color: theme.primaryColor),
                            const SizedBox(width: 5),
                            Text('Setlist: ${p.setlistTitle}',
                                style: TextStyle(
                                    fontSize: 12, color: theme.primaryColor)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (p.speakers.isNotEmpty)
                        _line(LucideIcons.mic, 'Speakers: ${p.speakers.join(", ")}'),
                      if (p.ushers.isNotEmpty)
                        _line(LucideIcons.users, 'Ushers: ${p.ushers.length} assigned'),
                      if (p.musicians.isNotEmpty)
                        _line(LucideIcons.music, 'Musicians: ${p.musicians.length}'),
                      if (p.notes != null && p.notes!.isNotEmpty)
                        _line(LucideIcons.fileText, p.notes!),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _editPlan(context, ref, p),
                            icon: const Icon(LucideIcons.pencil, size: 15),
                            label: const Text('Edit', style: TextStyle(fontSize: 12)),
                          ),
                          const Spacer(),
                          // Publish toggle — server sets published_at.
                          OutlinedButton.icon(
                            onPressed: () async {
                              await ref
                                  .read(careServiceProvider)
                                  .publishServicePlan(p.id, !p.isPublished);
                              ref.invalidate(servicePlansProvider(tenantId));
                            },
                            icon: Icon(
                                p.isPublished
                                    ? LucideIcons.eyeOff
                                    : LucideIcons.send,
                                size: 15),
                            label: Text(
                                p.isPublished ? 'Unpublish' : 'Publish',
                                style: const TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
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

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 12, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  Future<void> _editPlan(BuildContext context, WidgetRef ref,
      [ServicePlan? existing]) async {
    final titleCtl = TextEditingController(text: existing?.title ?? '');
    final notesCtl = TextEditingController(text: existing?.notes ?? '');
    final speakersCtl = TextEditingController(text: existing?.speakers.join(', ') ?? '');
    final ushersCtl = TextEditingController(text: '');
    final musiciansCtl = TextEditingController(text: '');
    DateTime date = existing?.serviceDate ?? DateTime.now();
    String? setlistId = existing?.setlistId;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Plan a Service' : 'Edit Service'),
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
                    subtitle: Text(DateFormat('EEE d MMM yyyy').format(date)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 30)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => date = picked);
                    },
                  ),
                  TextField(
                    controller: titleCtl,
                    decoration: const InputDecoration(
                        labelText: 'Service title',
                        hintText: 'e.g. Sunday Service'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: speakersCtl,
                    decoration: const InputDecoration(
                        labelText: 'Speakers (comma separated)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ushersCtl,
                    decoration: const InputDecoration(
                        labelText: 'Ushers (names, comma separated)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: musiciansCtl,
                    decoration: const InputDecoration(
                        labelText: 'Musicians (names, comma separated)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtl,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('SAVE')),
          ],
        ),
      ),
    );

    if (saved != true || !context.mounted) return;
    final title = titleCtl.text.trim();
    if (title.isEmpty) return;
    List<String> split(String s) => s
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    try {
      await ref.read(careServiceProvider).upsertServicePlan(
            id: existing?.id,
            tenantId: tenantId,
            serviceDate: date,
            title: title,
            setlistId: setlistId,
            speakers: split(speakersCtl.text),
            // Ushers/musicians are stored as uuid[]; until the member picker
            // exists we keep them empty rather than writing invalid ids.
            ushers: const [],
            musicians: const [],
            notes: notesCtl.text.trim(),
          );
      ref.invalidate(servicePlansProvider(tenantId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not save: $e'),
            backgroundColor: Colors.red));
      }
    }
  }
}
