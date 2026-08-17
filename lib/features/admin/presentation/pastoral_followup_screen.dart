import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/features/admin/data/pastoral_followup_service.dart';

class PastoralFollowupScreen extends ConsumerStatefulWidget {
  const PastoralFollowupScreen({super.key});

  @override
  ConsumerState<PastoralFollowupScreen> createState() => _PastoralFollowupScreenState();
}

class _PastoralFollowupScreenState extends ConsumerState<PastoralFollowupScreen> {
  String _filter = 'open';
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;
    try {
      final members =
          await ref.read(pastoralFollowupServiceProvider).members(tenant.id);
      if (mounted) setState(() => _members = members);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final theme = Theme.of(context);
    if (tenant == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pastoral Follow-ups')),
        body: const AppErrorView(error: 'No church selected'),
      );
    }
    final followupsAsync = ref.watch(pastoralFollowupsProvider(tenant.id));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Pastoral Follow-ups', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'New follow-up',
            onPressed: () => _showAddSheet(tenant.id),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'open', label: Text('Open'), icon: Icon(LucideIcons.clock, size: 16)),
                ButtonSegment(value: 'done', label: Text('Completed'), icon: Icon(LucideIcons.checkCircle, size: 16)),
                ButtonSegment(value: 'all', label: Text('All'), icon: Icon(LucideIcons.layers, size: 16)),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
              showSelectedIcon: false,
            ),
          ),
          Expanded(
            child: followupsAsync.when(
              loading: () => const ShimmerLoader.rectangular(height: 80),
              error: (e, _) => AppErrorView(error: AppErrorView.friendlyMessage(e)),
              data: (followups) {
                final visible = followups.where((f) {
                  if (_filter == 'open') return f.isOpen;
                  if (_filter == 'done') return !f.isOpen;
                  return true;
                }).toList();
                if (visible.isEmpty) {
                  return const AppErrorView(
                    error: 'No follow-ups yet. Tap + to log a pastoral visit, call or WhatsApp check-in.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(pastoralFollowupsProvider(tenant.id));
                    await _loadMembers();
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    itemCount: visible.length,
                    itemBuilder: (context, i) => _followupCard(visible[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _followupCard(PastoralFollowup f) {
    final theme = Theme.of(context);
    final memberName = _memberName(f.memberId);
    final typeMeta = _typeMeta(f.followupType);
    final due = f.followUpAt != null
        ? 'Due ${_fmtDate(f.followUpAt!)}'
        : 'Logged ${_fmtDate(f.createdAt)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: typeMeta.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(typeMeta.icon, color: typeMeta.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          memberName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (f.isOpen)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('OPEN', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('DONE', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${typeMeta.label} • $due', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                  if (f.notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(f.notes, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical, size: 18),
              onSelected: (v) => _handleAction(f, v),
              itemBuilder: (_) => [
                if (f.isOpen)
                  const PopupMenuItem(value: 'done', child: Text('Mark completed'))
                else
                  const PopupMenuItem(value: 'reopen', child: Text('Reopen')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(PastoralFollowup f, String action) async {
    final service = ref.read(pastoralFollowupServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (action == 'done') {
        await service.setStatus(f.id, 'done');
        messenger.showSnackBar(const SnackBar(content: Text('Follow-up completed')));
      } else if (action == 'reopen') {
        await service.setStatus(f.id, 'open');
      } else if (action == 'delete') {
        await service.remove(f.id);
        messenger.showSnackBar(const SnackBar(content: Text('Follow-up deleted')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(AppErrorView.friendlyMessage(e))));
    }
  }

  String _memberName(String id) {
    for (final m in _members) {
      if (m['id'] == id) return m['full_name'] as String? ?? 'Member';
    }
    return 'Member';
  }

  String _fmtDate(DateTime d) {
    final local = d.toLocal();
    final now = DateTime.now();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return 'today';
    }
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  ({IconData icon, Color color, String label}) _typeMeta(String type) {
    switch (type) {
      case 'phone':
        return (icon: LucideIcons.phone, color: Colors.blue, label: 'Phone call');
      case 'whatsapp':
        return (icon: LucideIcons.messageCircle, color: Colors.green, label: 'WhatsApp');
      case 'sms':
        return (icon: LucideIcons.messageSquare, color: Colors.teal, label: 'SMS');
      case 'email':
        return (icon: LucideIcons.mail, color: Colors.purple, label: 'Email');
      case 'in_church':
        return (icon: LucideIcons.church, color: Colors.orange, label: 'In-church visit');
      case 'visit':
      default:
        return (icon: LucideIcons.home, color: Colors.indigo, label: 'Home visit');
    }
  }

  Future<void> _showAddSheet(String tenantId) async {
    String? memberId;
    String type = 'visit';
    final notesController = TextEditingController();
    DateTime? followUpAt;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Pastoral Follow-up', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: memberId,
                  decoration: const InputDecoration(
                    labelText: 'Member',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final m in _members)
                      DropdownMenuItem(
                        value: m['id'] as String,
                        child: Text(m['full_name'] as String? ?? 'Member', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setSheetState(() => memberId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'visit', child: Text('Home visit')),
                    DropdownMenuItem(value: 'in_church', child: Text('In-church visit')),
                    DropdownMenuItem(value: 'phone', child: Text('Phone call')),
                    DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
                    DropdownMenuItem(value: 'sms', child: Text('SMS')),
                    DropdownMenuItem(value: 'email', child: Text('Email')),
                  ],
                  onChanged: (v) => setSheetState(() => type = v ?? 'visit'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'What happened? Next steps?',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(LucideIcons.calendarDays, size: 18),
                        label: Text(
                          followUpAt == null
                              ? 'Set follow-up date'
                              : 'Due ${_fmtDate(followUpAt!)}',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: followUpAt ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setSheetState(() => followUpAt = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    icon: const Icon(LucideIcons.plus),
                    label: const Text('Save follow-up'),
                    onPressed: () async {
                      if (memberId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select a member')),
                        );
                        return;
                      }
                      final messenger = ScaffoldMessenger.of(sheetContext);
                      try {
                        await ref.read(pastoralFollowupServiceProvider).create(
                          tenantId: tenantId,
                          memberId: memberId!,
                          followupType: type,
                          notes: notesController.text.trim(),
                          followUpAt: followUpAt,
                        );
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(AppErrorView.friendlyMessage(e))),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
