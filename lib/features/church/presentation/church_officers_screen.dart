import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/config/app_constants.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/theme/app_theme.dart';
import 'package:church_on_app/features/church/data/church_governance_service.dart';

/// The elders / deacons / deaconesses roll.
///
/// This is a LOCAL register. A church APPOINTS its officers — that authority belongs
/// to the pastor and the leadership team, not to the conference. Ordination is a
/// different act by a different authority and lives in `OrdinationScreen`; keeping
/// the two apart on the same screen set is the whole point, because "the pastor gave
/// him the title" is exactly the confusion this feature exists to remove.
///
/// Members of the church can read this roll (an elders board is public in a Zambian
/// church), so non-leaders get a read-only view with the counts and no controls.
class ChurchOfficersScreen extends ConsumerStatefulWidget {
  const ChurchOfficersScreen({super.key, this.churchId});

  /// Optional explicit church/tenant id. Falls back to the signed-in user's church.
  final String? churchId;

  @override
  ConsumerState<ChurchOfficersScreen> createState() =>
      _ChurchOfficersScreenState();
}

class _ChurchOfficersScreenState extends ConsumerState<ChurchOfficersScreen> {
  bool _busy = false;
  String? _error;

  ChurchGovernanceService get _service =>
      ref.read(churchGovernanceServiceProvider);

  /// The church this register belongs to. A router caller can pin it; otherwise it is
  /// the user's current church.
  String get _churchId {
    final explicit = (widget.churchId ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    return ref.read(currentTenantProvider)?.id ?? '';
  }

  /// Mirrors `can_manage_church_officers` in the migration. The server enforces it
  /// too — this only decides which controls are shown.
  bool get _canAppoint {
    final role = ref.watch(profileProvider).value?.role ?? '';
    return GovernanceRoles.canAppointOfficers(role);
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _error = null);
    final id = _churchId;
    try {
      await Future.wait([
        ref.refresh(churchOfficersProvider(id).future),
        ref.refresh(officerCountsProvider(id).future),
      ]);
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      await _reload();
    } on GovernanceException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _appoint() async {
    final id = _churchId;
    if (id.isEmpty) {
      setState(() => _error = 'Select a church first.');
      return;
    }

    List<Map<String, dynamic>> members;
    try {
      members = await _service.fetchMembers(id);
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
      return;
    }
    if (!mounted) return;
    if (members.isEmpty) {
      setState(() => _error =
          'No members found for this church yet. An officer has to be a member of '
          'the church that appoints them.');
      return;
    }

    final result = await showModalBottomSheet<_AppointResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AppointOfficerSheet(members: members),
    );
    if (result == null) return;

    await _run(
      () => _service.appoint(
        churchId: id,
        memberId: result.memberId,
        role: result.role,
        termStart: result.termStart,
        termEnd: result.termEnd,
        isExcoMember: result.isExcoMember,
        notes: result.notes,
      ),
      '${result.role.label} appointed',
    );
  }

  Future<void> _endAppointment(ChurchOfficer officer) async {
    final status = await showDialog<OfficerStatus>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('End ${officer.displayName}\'s appointment?'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'The appointment is closed and kept on record — nothing is deleted, '
              'so the church can still answer "who served here and when".',
              style: TextStyle(fontSize: 12),
            ),
          ),
          for (final s in const [
            OfficerStatus.inactive,
            OfficerStatus.deceased,
            OfficerStatus.transferred,
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Text('Mark as ${s.label.toLowerCase()}'),
            ),
        ],
      ),
    );
    if (status == null) return;

    await _run(
      () => _service.endAppointment(officerId: officer.id, status: status),
      'Appointment closed',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final churchId = _churchId;
    final officersAsync = ref.watch(churchOfficersProvider(churchId));
    final counts = ref.watch(officerCountsProvider(churchId)).value ?? const {};
    final canAppoint = _canAppoint;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Church Officers'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(LucideIcons.rotateCcw),
            onPressed: _busy ? null : _reload,
          ),
        ],
      ),
      floatingActionButton: canAppoint
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _appoint,
              backgroundColor: AppTheme.platformPrimary,
              foregroundColor: AppTheme.onPlatformPrimary,
              icon: const Icon(LucideIcons.plus),
              label: const Text(
                'APPOINT OFFICER',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
            )
          : null,
      body: officersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _errorView(theme, _friendly(e)),
        data: (officers) => RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              _countsRow(theme, counts),
              const SizedBox(height: 14),
              _authorityNote(theme, canAppoint),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _banner(theme, LucideIcons.alertTriangle, _error!, Colors.red),
              ],
              const SizedBox(height: 20),
              if (officers.isEmpty)
                _emptyState(theme, canAppoint)
              else
                ..._grouped(theme, officers, canAppoint),
            ],
          ),
        ),
      ),
    );
  }

  // ── Headcount across the three offices ──────────────────────────────────
  Widget _countsRow(
    ThemeData theme,
    Map<OfficerRole, int> counts,
  ) {
    return Row(
      children: [
        for (final role in OfficerRole.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _countCard(theme, role, counts[role] ?? 0),
            ),
          ),
      ],
    );
  }

  Widget _countCard(ThemeData theme, OfficerRole role, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: count > 0
              ? AppConstants.sunflowerYellow
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: count > 0 ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          Icon(_iconForRole(role),
              size: 18,
              color: count > 0
                  ? AppConstants.primaryDark
                  : theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(height: 6),
          Text('$count',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900)),
          Text(role.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              )),
        ],
      ),
    );
  }

  /// Says plainly what this register is and is not. The distinction between an
  /// APPOINTMENT and an ORDINATION is the one people get wrong.
  Widget _authorityNote(ThemeData theme, bool canAppoint) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.surfaceWarm.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.info,
              size: 16, color: AppConstants.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              canAppoint
                  ? 'This is the church\'s own register: the pastor and leadership '
                      'team appoint from among their members. Ordination is a '
                      'separate act by a bishop, and is recorded in Ordination & '
                      'Credentials — being on this roll does not make somebody an '
                      'ordained elder.'
                  : 'Your church\'s elders, deacons and deaconesses. Only church '
                      'leadership can appoint or close an appointment, so this view '
                      'is read-only.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppConstants.primaryDark.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── The roll, grouped by office ─────────────────────────────────────────
  List<Widget> _grouped(
    ThemeData theme,
    List<ChurchOfficer> officers,
    bool canAppoint,
  ) {
    final widgets = <Widget>[];

    for (final role in OfficerRole.values) {
      final rows = officers.where((o) => o.role == role).toList();
      if (rows.isEmpty) continue;

      final serving = rows.where((o) => o.isActive).length;

      widgets.add(const SizedBox(height: 14));
      widgets.add(
          _sectionHeader(theme, _iconForRole(role), role.label, '$serving serving'));
      widgets.add(const SizedBox(height: 6));
      widgets.addAll(rows.map((o) => _officerTile(theme, o, canAppoint)));
    }

    final closed =
        officers.where((o) => !o.isActive).toList().reversed.toList();
    if (closed.isNotEmpty) {
      widgets.add(const SizedBox(height: 22));
      widgets.add(_sectionHeader(theme, LucideIcons.archive, 'No longer serving',
          '${closed.length}'));
      widgets.add(const SizedBox(height: 6));
      widgets.addAll(closed.map((o) => _officerTile(theme, o, canAppoint)));
    }

    return widgets;
  }

  Widget _sectionHeader(
      ThemeData theme, IconData icon, String title, String count) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
        Text(
          count,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }

  Widget _officerTile(
      ThemeData theme, ChurchOfficer officer, bool canAppoint) {
    final lapsed = officer.termLapsed;
    final ending = officer.termEndingSoon;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: lapsed
              ? theme.colorScheme.error.withValues(alpha: 0.5)
              : ending
                  ? Colors.amber.withValues(alpha: 0.6)
                  : officer.isActive
                      ? AppConstants.sunflowerYellow
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: officer.isActive ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (officer.isActive
                      ? AppConstants.sunflowerYellow
                      : theme.colorScheme.onSurface)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconForRole(officer.role),
                size: 20,
                color: officer.isActive
                    ? AppConstants.primaryDark
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  officer.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: officer.isActive
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    decoration:
                        officer.isActive ? null : TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(officer.status.label,
                        officer.isActive ? Colors.green : Colors.grey,
                        dark: false),
                    if (officer.isExcoMember)
                      _chip('EXCO', AppConstants.accentGreen, dark: true),
                    if (lapsed) _chip('TERM LAPSED', theme.colorScheme.error),
                    if (ending && !lapsed) _chip('TERM ENDING', Colors.amber),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _termLine(officer),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          if (canAppoint && officer.isActive)
            IconButton(
              tooltip: 'End appointment',
              icon: const Icon(LucideIcons.circleSlash, size: 18),
              onPressed: _busy ? null : () => _endAppointment(officer),
            ),
        ],
      ),
    );
  }

  String _termLine(ChurchOfficer officer) {
    final start = _fmtDate(officer.termStart);
    final end = officer.termEnd == null ? 'no end date set' : _fmtDate(officer.termEnd);
    final exco = officer.isExcoMember ? ' · on the officers board' : '';
    return 'Term $start → $end$exco';
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '?';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$day/$m/${d.year}';
  }

  Widget _chip(String label, Color color, {bool dark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 1.0 : 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          color: dark ? Colors.white : color,
        ),
      ),
    );
  }

  // ── Empty / error ───────────────────────────────────────────────────────
  Widget _emptyState(ThemeData theme, bool canAppoint) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.users,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              const Text('NO OFFICERS APPOINTED YET',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Most Zambian churches keep the elders, deacons and deaconesses on a '
            'page in the register book, signed and dated, with terms. This is that '
            'page — it lets the church list its leadership, see when a term ends, '
            'and stop losing the record when somebody moves on or dies.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            canAppoint
                ? 'Tap APPOINT OFFICER to add the first one.'
                : 'Only church leadership can appoint an officer. Ask your pastor '
                    'or leadership team.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(
      ThemeData theme, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color, height: 1.3)),
          ),
        ],
      ),
    );
  }

  Widget _errorView(ThemeData theme, String message) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 70),
        Icon(LucideIcons.alertTriangle,
            size: 46, color: theme.colorScheme.error.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        Center(
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(height: 14),
        Center(child: FilledButton(onPressed: _reload, child: const Text('RETRY'))),
      ],
    );
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('42501') || s.contains('permission denied')) {
      return 'You do not have permission to view this register.';
    }
    return 'Could not load the officers register.';
  }

  IconData _iconForRole(OfficerRole role) => switch (role) {
        OfficerRole.elder => LucideIcons.crown,
        OfficerRole.deacon => LucideIcons.bookOpen,
        OfficerRole.deaconess => LucideIcons.badge,
      };
}

// ===========================================================================
// Appoint sheet
// ===========================================================================

class _AppointResult {
  final String memberId;
  final OfficerRole role;
  final DateTime? termStart;
  final DateTime? termEnd;
  final bool isExcoMember;
  final String? notes;

  const _AppointResult({
    required this.memberId,
    required this.role,
    this.termStart,
    this.termEnd,
    required this.isExcoMember,
    this.notes,
  });
}

class _AppointOfficerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  const _AppointOfficerSheet({required this.members});

  @override
  State<_AppointOfficerSheet> createState() => _AppointOfficerSheetState();
}

class _AppointOfficerSheetState extends State<_AppointOfficerSheet> {
  final _searchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  Map<String, dynamic>? _member;
  OfficerRole _role = OfficerRole.elder;
  bool _isExco = false;
  bool _hasTerm = true;
  DateTime _termStart = DateTime.now();
  DateTime _termEnd =
      DateTime.now().add(const Duration(days: 365));
  final bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.members;
    return widget.members
        .where((m) =>
            (m['full_name']?.toString().toLowerCase().contains(q) ?? false) ||
            (m['phone_number']?.toString().contains(q) ?? false))
        .toList();
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _termStart : _termEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _termStart = picked;
        // Keep the window coherent rather than letting the server reject it.
        if (_termEnd.isBefore(_termStart)) _termEnd = _termStart;
      } else {
        _termEnd = picked;
      }
    });
  }

  void _save() {
    if (_member == null) {
      setState(() => _error = 'Choose the member being appointed.');
      return;
    }
    if (_hasTerm && !_termEnd.isAfter(_termStart)) {
      setState(() => _error = 'The term must end after it starts.');
      return;
    }
    Navigator.of(context).pop(_AppointResult(
      memberId: _member!['id'].toString(),
      role: _role,
      termStart: _hasTerm ? _termStart : null,
      termEnd: _hasTerm ? _termEnd : null,
      isExcoMember: _isExco,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('Appoint an officer',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'A local appointment by this church. Ordination is recorded '
              'separately, by a bishop.',
              style: theme.textTheme.bodySmall,
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
                  prefixIcon: const Icon(LucideIcons.user),
                  suffixIcon: IconButton(
                    icon: const Icon(LucideIcons.x),
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
                  prefixIcon: Icon(LucideIcons.search),
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
                      subtitle: m['phone_number'] == null
                          ? null
                          : Text(m['phone_number'].toString()),
                      onTap: () => setState(() => _member = m),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 18),

            Text('OFFICE',
                style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in OfficerRole.values)
                  ChoiceChip(
                    avatar: Icon(_iconFor(r), size: 16),
                    label: Text(r.label),
                    selected: _role == r,
                    onSelected: (_) => setState(() => _role = r),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _hasTerm,
              onChanged: (v) => setState(() => _hasTerm = v),
              title: const Text('Set a term', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                'Most churches give officers a fixed term and renew it deliberately. '
                'Turn off for an open-ended appointment.',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            if (_hasTerm) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(start: true),
                      icon: const Icon(LucideIcons.calendar, size: 16),
                      label: Text('From ${_short(_termStart)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(start: false),
                      icon: const Icon(LucideIcons.calendarCheck, size: 16),
                      label: Text('To ${_short(_termEnd)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isExco,
              onChanged: (v) => setState(() => _isExco = v),
              title: const Text('On the officers board (exco)',
                  style: TextStyle(fontSize: 13)),
              subtitle: Text(
                'The exco runs decisions between meetings. Members often hold an '
                'office without sitting on it.',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Notes (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: AppConstants.sunflowerYellow,
                foregroundColor: AppConstants.primaryDark,
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.check),
              label: Text(_saving ? 'SAVING…' : 'APPOINT',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }

  String _short(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$day/$m/${d.year}';
  }

  IconData _iconFor(OfficerRole role) => switch (role) {
        OfficerRole.elder => LucideIcons.crown,
        OfficerRole.deacon => LucideIcons.bookOpen,
        OfficerRole.deaconess => LucideIcons.badge,
      };
}