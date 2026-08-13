import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/theme/app_theme.dart';
import 'package:church_on_app/features/admin/data/audit_service.dart';

/// COA/Superadmin resolution hub: responds to support tickets, disputes and
/// app error reports. Every staff action is written to the audit log.
class ResolutionHubScreen extends ConsumerStatefulWidget {
  const ResolutionHubScreen({super.key});

  @override
  ConsumerState<ResolutionHubScreen> createState() => _ResolutionHubScreenState();
}

class _ResolutionHubScreenState extends ConsumerState<ResolutionHubScreen> {
  int _tab = 0;

  static const _tableFor = ['support_tickets', 'support_disputes', 'app_error_reports'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Resolution Hub", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 52,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  _tabBtn(theme, 0, LucideIcons.lifeBuoy, "Tickets"),
                  _tabBtn(theme, 1, LucideIcons.gavel, "Disputes"),
                  _tabBtn(theme, 2, LucideIcons.bug, "Errors"),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildList(theme)),
        ],
      ),
    );
  }

  Widget _tabBtn(ThemeData theme, int index, IconData icon, String label) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: selected ? theme.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    final table = _tableFor[_tab];
    final client = Supabase.instance.client;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: client
          .from(table)
          .select('*, profiles:user_id(full_name, phone_number, email)')
          .order('created_at', ascending: false)
          .limit(200),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Failed to load: ${snapshot.error}", style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text("Retry"),
                ),
              ],
            ),
          );
        }
        final rows = snapshot.data ?? const [];
        if (rows.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.inbox, size: 40, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                const SizedBox(height: 12),
                Text("Nothing to resolve here yet", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            itemCount: rows.length,
            itemBuilder: (context, index) => _buildRow(theme, rows[index]),
          ),
        );
      },
    );
  }

  Widget _buildRow(ThemeData theme, Map<String, dynamic> row) {
    final status = (row['status'] ?? 'open').toString();
    final color = StatusColor.fromString(context, status);
    final profile = row['profiles'] as Map<String, dynamic>?;
    final name = profile?['full_name']?.toString() ?? 'User ${row['user_id']?.toString().substring(0, 8)}';
    final created = row['created_at'] != null
        ? DateTime.tryParse(row['created_at'].toString())?.toLocal()
        : null;

    final title = row['subject']?.toString() ?? row['error_message']?.toString() ?? 'Untitled';
    final subtitle = _tab == 2
        ? '${row['screen'] ?? 'unknown screen'} · $name'
        : '${row['category'] ?? row['dispute_type'] ?? 'general'} · $name';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        onTap: () => _openDetail(theme, row),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(_tab == 2 ? LucideIcons.bug : LucideIcons.gavel, color: color, size: 17),
        ),
        title: Text(
          title.length > 70 ? '${title.substring(0, 70)}...' : title,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: const TextStyle(fontSize: 11.5)),
            if (created != null)
              Text(
                created.toLocal().toString().substring(0, 16),
                style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Text(
            status.toUpperCase(),
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(ThemeData theme, Map<String, dynamic> row) async {
    final client = Supabase.instance.client;
    final table = _tableFor[_tab];
    final isError = _tab == 2;
    final status = (row['status'] ?? 'open').toString();

    String? notes = row['resolution_notes']?.toString() ?? '';
    String? priority = row['priority']?.toString();

    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _RespondSheet(
        row: row,
        isError: isError,
        initialStatus: status,
        initialNotes: notes,
        initialPriority: priority,
        onSave: (s, n, p) {
          notes = n;
          priority = p;
          Navigator.pop(sheetCtx, {'status': s, 'notes': n, 'priority': p});
        },
      ),
    );

    if (updated == null || !mounted) return;

    try {
      final staff = client.auth.currentUser;
      final resolved = updated['status'] == 'resolved';
      final patch = <String, dynamic>{
        'status': updated['status'],
        'resolution_notes': updated['notes'],
        'responder_id': staff?.id,
        if (priority != null) 'priority': priority,
        if (resolved) 'resolved_at': DateTime.now().toIso8601String(),
      };
      await client.from(table).update(patch).eq('id', row['id']);

      await ref.read(auditServiceProvider).logAction(
            action: 'respond_${isError ? 'error_report' : _tab == 1 ? 'dispute' : 'ticket'}',
            entityType: table,
            entityId: row['id']?.toString(),
            details: {
              'subject': row['subject'] ?? row['error_message'],
              'to_status': updated['status'],
              'priority': priority,
              'resolver': staff?.email,
            },
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Updated successfully"), backgroundColor: Colors.green),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Update failed: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _RespondSheet extends StatefulWidget {
  final Map<String, dynamic> row;
  final bool isError;
  final String initialStatus;
  final String? initialNotes;
  final String? initialPriority;
  final void Function(String status, String notes, String? priority) onSave;

  const _RespondSheet({
    required this.row,
    required this.isError,
    required this.initialStatus,
    required this.initialNotes,
    required this.initialPriority,
    required this.onSave,
  });

  @override
  State<_RespondSheet> createState() => _RespondSheetState();
}

class _RespondSheetState extends State<_RespondSheet> {
  late String _status;
  late String _priority;
  late final TextEditingController _notesCtrl;

  static const _statusOptions = [
    'open',
    'in_review',
    'under_review',
    'resolved',
    'rejected',
    'closed',
  ];

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _priority = widget.initialPriority ?? 'medium';
    _notesCtrl = TextEditingController(text: widget.initialNotes ?? '');
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = widget.isError;
    final isDispute = !isError && widget.row.containsKey('dispute_type');
    final profile = widget.row['profiles'] as Map<String, dynamic>?;
    final name = profile?['full_name']?.toString() ?? 'User';
    final phone = profile?['phone_number']?.toString();
    final email = profile?['email']?.toString();
    final message = widget.row['description']?.toString() ?? widget.row['error_message']?.toString() ?? '';
    final stack = widget.row['stack_trace']?.toString();

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 50, height: 5, decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 18),
            Text(widget.row['subject']?.toString() ?? (isError ? 'Error Report' : 'Dispute'), style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('$name${phone != null ? ' · $phone' : ''}${email != null ? ' · $email' : ''}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            if (widget.row['reference_id'] != null) ...[
              const SizedBox(height: 4),
              Text('Ref: ${widget.row['reference_id']}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            ],
            if (isError) ...[
              const SizedBox(height: 4),
              Text('Version: ${widget.row['app_version'] ?? '?'} · ${widget.row['device_info'] ?? ''}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            ],
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(message, style: const TextStyle(fontSize: 13, height: 1.4)),
            ),
            if (stack != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  stack.length > 1500 ? '${stack.substring(0, 1500)}...' : stack,
                  style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: "Status", border: OutlineInputBorder()),
              items: _statusOptions
                  .where((s) => isError ? s != 'rejected' && s != 'closed' && s != 'under_review' : true)
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase())))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            if (isDispute) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: "Priority", border: OutlineInputBorder()),
                items: ['low', 'medium', 'high', 'urgent']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.toUpperCase())))
                    .toList(),
                onChanged: (v) => setState(() => _priority = v ?? _priority),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: "Resolution Notes / Response",
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => widget.onSave(_status, _notesCtrl.text.trim(), isDispute ? _priority : null),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text("SAVE RESPONSE", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            ),
          ],
        ),
      ),
    );
  }
}
