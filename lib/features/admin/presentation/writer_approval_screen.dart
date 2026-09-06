import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/features/admin/data/writer_approval_service.dart';

class WriterApprovalScreen extends ConsumerWidget {
  const WriterApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingWriterApplicationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Writer Applications')),
      body: pendingAsync.when(
        data: (apps) => apps.isEmpty
            ? const Center(child: Text('No pending writer applications'))
            : ListView.builder(
                itemCount: apps.length,
                itemBuilder: (context, index) {
                  final app = apps[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ExpansionTile(
                      leading: CircleAvatar(child: Text(app.fullName.isNotEmpty ? app.fullName[0].toUpperCase() : '?')),
                      title: Text(app.fullName),
                      subtitle: Text(app.email ?? app.phone ?? 'No contact'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (app.reason != null) Text('Reason: ${app.reason}'),
                              if (app.writingSamplesUrl != null)
                                InkWell(
                                  onTap: () async {
                                    final uri = Uri.tryParse(app.writingSamplesUrl!);
                                    if (uri != null && await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  },
                                  child: Text('Samples: ${app.writingSamplesUrl}', style: TextStyle(color: Theme.of(context).primaryColor)),
                                ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _reject(context, ref, app),
                                    icon: const Icon(LucideIcons.xCircle, size: 16),
                                    label: const Text('Reject'),
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      await ref.read(writerApprovalServiceProvider).approveApplication(app.id);
                                      ref.invalidate(pendingWriterApplicationsProvider);
                                    },
                                    icon: const Icon(LucideIcons.checkCircle, size: 16),
                                    label: const Text('Approve'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }

  void _reject(BuildContext context, WidgetRef ref, WriterApplication app) {
    final reasonC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Application'),
        content: TextField(
          controller: reasonC,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(writerApprovalServiceProvider).rejectApplication(app.id, reason: reasonC.text);
              ref.invalidate(pendingWriterApplicationsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}
