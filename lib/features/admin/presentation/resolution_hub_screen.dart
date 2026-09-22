import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/theme/app_theme.dart';
import 'package:church_on_app/features/admin/data/audit_service.dart';

/// COA/Superadmin resolution hub: responds to support tickets, disputes and
/// app error reports. Every staff action is written to the audit log.
///
/// Error reports can be copied to the clipboard as a structured report so COA
/// staff can paste a full incident (timestamp, user, tenant, operation, error
/// code + message, ids) into a ticket/chat. The copy affordance is staff-only.
class ResolutionHubScreen extends ConsumerStatefulWidget {
  const ResolutionHubScreen({super.key});

  @override
  ConsumerState<ResolutionHubScreen> createState() => _ResolutionHubScreenState();
}

class _ResolutionHubScreenState extends ConsumerState<ResolutionHubScreen> {
  int _tab = 0;

  /// Memoised per-tab load. Kept in state so `setState` (tab switch, refresh,
  /// sheet close) never mints a new Future and re-queries on every rebuild.
  Future<List<Map<String, dynamic>>>? _future;

  static const _tableFor = ['support_tickets', 'support_disputes', 'app_error_reports'];

  /// Allowed statuses PER TABLE — must match the table CHECK constraints, or an
  /// UPDATE fails with 23514. (Previously the sheet offered the union of all
  /// three tables, so e.g. 'under_review' on a ticket was rejected.)
  static const _statusesByTable = <String, List<String>>{
    'support_tickets': ['open', 'in_review', 'resolved', 'closed'],
    'support_disputes': ['open', 'under_review', 'resolved', 'rejected'],
    'app_error_reports': ['open', 'in_review', 'resolved'],
  };

  static bool _isStaffRole(String? role) =>
      role == 'superadmin' ||
      role == 'super_admin' ||
      role == 'coa_employee' ||
      role == 'employee';

  @override
  void initState() {
    super.initState();
    _future = _loadRows(_tableFor[_tab]);
  }

  void _reload() {
    setState(() => _future = _loadRows(_tableFor[_tab]));
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() {
      _tab = index;
      _future = _loadRows(_tableFor[index]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStaff = _isStaffRole(ref.watch(profileProvider).value?.role);

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
          Expanded(child: _buildList(theme, isStaff)),
        ],
      ),
    );
  }

  Widget _tabBtn(ThemeData theme, int index, IconData icon, String label) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectTab(index),
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

  Future<List<Map<String, dynamic>>> _loadRows(String table) async {
    final client = Supabase.instance.client;
    final rows = (await client
            .from(table)
            .select('*')
            .order('created_at', ascending: false)
            .limit(200) as List)
        .cast<Map<String, dynamic>>();

    final userIds = rows
        .map((r) => r['user_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    Map<String, Map<String, dynamic>> profiles = {};
    if (userIds.isNotEmpty) {
      try {
        final res = await client
            .from('profiles')
            .select('id, full_name, phone_number, email, tenant_id')
            .inFilter('id', userIds);
        profiles = {
          for (final p in (res as List).cast<Map<String, dynamic>>())
            p['id'].toString(): p,
        };
      } catch (e) {
        debugPrint('ResolutionHub: profiles fetch error: $e');
      }
    }
    for (final r in rows) {
      final uid = r['user_id']?.toString();
      if (uid != null) r['profiles'] = profiles[uid];
    }
    return rows;
  }

  Widget _buildList(ThemeData theme, bool isStaff) {
    final table = _tableFor[_tab];

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text("Failed to load: ${snapshot.error}", textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 12),
                if (isStaff)
                  TextButton.icon(
                    onPressed: () => _copyReport(_buildLoadErrorReport(table, snapshot.error), label: 'Load error'),
                    icon: const Icon(LucideIcons.copy, size: 16),
                    label: const Text("COPY ERROR REPORT"),
                  ),
                TextButton(
                  onPressed: _reload,
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

        return Column(
          children: [
            if (_tab == 2 && isStaff)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "${rows.length} error report${rows.length == 1 ? '' : 's'}",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyReport(
                        rows.map(_errorReportText).join('\n\n────────────────\n\n'),
                        label: 'All ${rows.length} error reports',
                      ),
                      icon: const Icon(LucideIcons.copy, size: 15),
                      label: const Text("COPY ALL"),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _buildRow(theme, rows[index], isStaff),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRow(ThemeData theme, Map<String, dynamic> row, bool isStaff) {
    final status = (row['status'] ?? 'open').toString();
    final color = StatusColor.fromString(context, status);
    final profile = row['profiles'] as Map<String, dynamic>?;
    final rawUid = row['user_id']?.toString() ?? '';
    final name = profile?['full_name']?.toString() ?? (rawUid.length >= 8 ? 'User ${rawUid.substring(0, 8)}' : 'User');
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
        onTap: () => _openDetail(theme, row, isStaff),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_tab == 2 && isStaff)
              IconButton(
                tooltip: 'Copy error report',
                visualDensity: VisualDensity.compact,
                icon: const Icon(LucideIcons.copy, size: 16),
                onPressed: () => _copyReport(_errorReportText(row)),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Structured, paste-ready incident report (timestamp, ids, operation, error).
  String _errorReportText(Map<String, dynamic> row) {
    final profile = row['profiles'] as Map<String, dynamic>?;
    return [
      'COA ERROR REPORT',
      'timestamp: ${row['created_at'] ?? '-'}',
      'report_id: ${row['id'] ?? '-'}',
      'user_id: ${row['user_id'] ?? '-'}',
      'user: ${profile?['full_name'] ?? '-'} (${profile?['email'] ?? '-'})',
      'tenant_id: ${row['tenant_id'] ?? profile?['tenant_id'] ?? '-'}',
      'operation: ${row['screen'] ?? 'unknown screen'}',
      'status: ${row['status'] ?? '-'}',
      'app_version: ${row['app_version'] ?? '?'}',
      'device: ${row['device_info'] ?? '?'}',
      'error: ${row['error_message'] ?? '-'}',
      if (row['stack_trace'] != null) 'stack_trace:\n${row['stack_trace']}',
    ].join('\n');
  }

  String _buildLoadErrorReport(String table, Object? error) => [
        'COA RESOLUTION HUB — LOAD FAILURE',
        'timestamp: ${DateTime.now().toUtc().toIso8601String()}',
        'user_id: ${Supabase.instance.client.auth.currentUser?.id ?? '-'}',
        'operation: load_$table',
        'error: $error',
      ].join('\n');

  Future<void> _copyReport(String text, {String label = 'Error report'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard'), backgroundColor: Colors.green),
    );
  }

  Future<void> _openDetail(ThemeData theme, Map<String, dynamic> row, bool isStaff) async {
    final client = Supabase.instance.client;
    final table = _tableFor[_tab];
    final isError = _tab == 2;
    final status = (row['status'] ?? 'open').toString();
    final statusOptions = _statusesByTable[table] ?? const ['open', 'resolved'];
    // Both tickets and disputes carry a `priority` column; error reports don't.
    final hasPriority = table != 'app_error_reports';

    String? notes = row['resolution_notes']?.toString() ?? '';
    String? priority = row['priority']?.toString();

    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _RespondSheet(
        row: row,
        isError: isError,
        isStaff: isStaff,
        statusOptions: statusOptions,
        hasPriority: hasPriority,
        initialStatus: statusOptions.contains(status) ? status : statusOptions.first,
        initialNotes: notes,
        initialPriority: priority,
        onCopy: isError ? () => _copyReport(_errorReportText(row)) : null,
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
        _reload();
      }
    } catch (e) {
      if (mounted) {
        final report = [
          'COA RESOLUTION HUB — UPDATE FAILURE',
          'timestamp: ${DateTime.now().toUtc().toIso8601String()}',
          'user_id: ${client.auth.currentUser?.id ?? '-'}',
          'tenant_id: ${(row['profiles'] as Map?)?['tenant_id'] ?? row['tenant_id'] ?? '-'}',
          'operation: update_$table (status=${updated['status']})',
          'record_id: ${row['id']}',
          'error: $e',
        ].join('\n');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Update failed: $e"),
            backgroundColor: Colors.red,
            action: isStaff
                ? SnackBarAction(
                    label: 'COPY',
                    textColor: Colors.white,
                    onPressed: () => _copyReport(report, label: 'Update failure'),
                  )
                : null,
          ),
        );
      }
    }
  }
}

class _RespondSheet extends StatefulWidget {
  final Map<String, dynamic> row;
  final bool isError;
  final bool isStaff;
  final List<String> statusOptions;
  final bool hasPriority;
  final String initialStatus;
  final String? initialNotes;
  final String? initialPriority;
  final VoidCallback? onCopy;
  final void Function(String status, String notes, String? priority) onSave;

  const _RespondSheet({
    required this.row,
    required this.isError,
    required this.isStaff,
    required this.statusOptions,
    required this.hasPriority,
    required this.initialStatus,
    required this.initialNotes,
    required this.initialPriority,
    required this.onCopy,
    required this.onSave,
  });

  @override
  State<_RespondSheet> createState() => _RespondSheetState();
}

class _RespondSheetState extends State<_RespondSheet> {
  late String _status;
  late String _priority;
  late final TextEditingController _notesCtrl;

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
            if (widget.onCopy != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.onCopy,
                icon: const Icon(LucideIcons.copy, size: 16),
                label: const Text("COPY ERROR REPORT"),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: "Status", border: OutlineInputBorder()),
              items: widget.statusOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase())))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            if (widget.hasPriority) ...[
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
              onPressed: () => widget.onSave(_status, _notesCtrl.text.trim(), widget.hasPriority ? _priority : null),
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
