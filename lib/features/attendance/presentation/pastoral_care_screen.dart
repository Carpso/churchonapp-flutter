import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/church_registers_service.dart';

/// Counselling, warnings, suspension and restoration.
///
/// This is the most sensitive register in the product, so the screen says so
/// out loud and asks for confirmation before writing. A disciplinary record is
/// a serious act between a church and a person; the UI should never make it feel
/// like tapping a form.
class PastoralCareScreen extends StatefulWidget {
  final String tenantId;
  const PastoralCareScreen({super.key, required this.tenantId});

  @override
  State<PastoralCareScreen> createState() => _PastoralCareScreenState();
}

class _PastoralCareScreenState extends State<PastoralCareScreen> {
  late final ChurchRegistersService _service =
      ChurchRegistersService(Supabase.instance.client);

  List<CareRecord> _records = const [];
  List<Map<String, dynamic>> _members = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchCareRecords(widget.tenantId),
        _service.fetchMembers(widget.tenantId),
      ]);
      if (!mounted) return;
      setState(() {
        _records = results[0] as List<CareRecord>;
        _members = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the pastoral care register.';
        _loading = false;
      });
    }
  }

  List<CareRecord> get _open => _records.where((r) => r.isOpen).toList();
  List<CareRecord> get _closed =>
      _records.where((r) => !r.isOpen).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pastoral Care',
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _openRecordSheet,
        icon: const Icon(Icons.add),
        label: const Text('Record'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      _privacyNotice(theme),
                      const SizedBox(height: 16),
                      if (_open.isNotEmpty) ...[
                        Text('OPEN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: theme.colorScheme.error,
                            )),
                        const SizedBox(height: 8),
                        ..._open.map((r) => _card(r, theme)),
                        const SizedBox(height: 20),
                      ],
                      if (_closed.isNotEmpty) ...[
                        Text('CLOSED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: theme.disabledColor,
                            )),
                        const SizedBox(height: 8),
                        ..._closed.take(40).map((r) => _card(r, theme)),
                      ],
                      if (_records.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'Nothing recorded.\n\nUse this for pastoral '
                              'counselling and formal steps. Members cannot see '
                              'any of it.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _privacyNotice(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Visible to pastoral leadership only. Members cannot see these '
              'records, and every entry is added to the church activity log.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(CareRecord r, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(r.category.icon, size: 18, color: r.category.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${r.memberName ?? 'Unnamed'}  ·  ${r.category.label}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (r.isOpen ? Colors.orange : Colors.green)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    r.status.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: r.isOpen
                          ? Colors.orange.shade800
                          : Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(r.summary, style: theme.textTheme.bodySmall),
            if (r.actionTaken != null && r.actionTaken!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Action: ${r.actionTaken}',
                  style: theme.textTheme.labelSmall),
            ],
            const SizedBox(height: 6),
            Text(
              '${r.severityLabel}  ·  ${r.incidentDate.day}/${r.incidentDate.month}/${r.incidentDate.year}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.disabledColor),
            ),
            if (r.isOpen) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in [
                    CareStatus.restored,
                    CareStatus.resolved,
                    CareStatus.appealed
                  ])
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _resolve(r, s),
                      child: Text(s.label),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _resolve(CareRecord r, CareStatus status) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark as ${status.label.toLowerCase()}?'),
        content: Text(
          '${r.memberName ?? 'This member'} — ${r.category.label}.\n\n'
          'This is recorded in the church activity log.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(status.label)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.resolveCare(recordId: r.id, status: status);
      if (!mounted) return;
      await _load();
    } on RegisterException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openRecordSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecordCareSheet(members: _members, service: _service),
    );
    if (saved == true) await _load();
  }
}

class _RecordCareSheet extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  final ChurchRegistersService service;

  const _RecordCareSheet({required this.members, required this.service});

  @override
  State<_RecordCareSheet> createState() => _RecordCareSheetState();
}

class _RecordCareSheetState extends State<_RecordCareSheet> {
  final _searchCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _actionCtrl = TextEditingController();

  Map<String, dynamic>? _member;
  CareCategory _category = CareCategory.counselling;
  String _severity = 'pastoral';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _summaryCtrl.dispose();
    _actionCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.members;
    return widget.members
        .where((m) => m['full_name']?.toString().toLowerCase().contains(q) ??
            false)
        .toList();
  }

  Future<void> _save() async {
    if (_member == null) {
      setState(() => _error = 'Choose the member.');
      return;
    }
    if (_summaryCtrl.text.trim().length < 3) {
      setState(() => _error = 'Write a short summary of what happened.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.recordCare(
        memberId: _member!['id'].toString(),
        category: _category,
        summary: _summaryCtrl.text.trim(),
        severity: _severity,
        actionTaken: _actionCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on RegisterException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('Record pastoral care',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Leadership only. The member will not be able to see this.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 16),

            Text('MEMBER',
                style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (_member != null)
              InputDecorator(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _member = null),
                  ),
                ),
                child: Text(_member!['full_name']?.toString() ?? ''),
              )
            else ...[
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Search member',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final m = _filtered[i];
                    return ListTile(
                      dense: true,
                      title: Text(m['full_name']?.toString() ?? 'Unnamed'),
                      onTap: () => setState(() => _member = m),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 18),

            Text('TYPE',
                style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in CareCategory.values)
                  ChoiceChip(
                    avatar: Icon(c.icon, size: 16, color: c.color),
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pastoral', label: Text('Pastoral')),
                ButtonSegment(value: 'formal', label: Text('Formal')),
                ButtonSegment(value: 'serious', label: Text('Serious')),
              ],
              selected: {_severity},
              onSelectionChanged: (s) => setState(() => _severity = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _summaryCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'What happened',
                helperText: 'Keep it factual. Members may be discussed later.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _actionCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Action taken (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_outline),
              label: Text(_saving ? 'Saving...' : 'Record (leadership only)'),
            ),
          ],
        ),
      ),
    );
  }
}