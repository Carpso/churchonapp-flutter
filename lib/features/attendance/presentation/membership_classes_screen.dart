import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/church_registers_service.dart';

/// Membership progression: convert -> righteous member -> worker.
///
/// The headline number is the roll of workers, because that is what a Zambian
/// church is counted by. Each class is shown as a card with its headcount so the
/// church can see where people are stalling - typically a large convert class
/// that never becomes workers.
class MembershipClassesScreen extends StatefulWidget {
  final String tenantId;
  const MembershipClassesScreen({super.key, required this.tenantId});

  @override
  State<MembershipClassesScreen> createState() => _MembershipClassesScreenState();
}

class _MembershipClassesScreenState extends State<MembershipClassesScreen> {
  late final ChurchRegistersService _service =
      ChurchRegistersService(Supabase.instance.client);

  Map<MemberClass, int> _counts = const {};
  List<MemberClassRecord> _records = const [];
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
        _service.classCounts(widget.tenantId),
        _service.fetchClasses(widget.tenantId),
        _service.fetchMembers(widget.tenantId),
      ]);
      if (!mounted) return;
      setState(() {
        _counts = results[0] as Map<MemberClass, int>;
        _records = results[1] as List<MemberClassRecord>;
        _members = results[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the membership register.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership Classes',
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _openAssignSheet(context),
        icon: const Icon(Icons.how_to_reg),
        label: const Text('Assign class'),
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
                      Text('WHERE THE CHURCH IS TODAY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: theme.disabledColor,
                          )),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (final c in MemberClass.values)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _countCard(c, theme),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _stallNote(theme),
                      const SizedBox(height: 20),
                      Text('RECENT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: theme.disabledColor,
                          )),
                      const SizedBox(height: 6),
                      if (_records.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'No one has been placed in a class yet.\n\n'
                              'Assign a class as people move from convert to '
                              'righteous member to worker.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        )
                      else
                        ..._records.take(60).map((r) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: theme.primaryColor
                                    .withValues(alpha: 0.12),
                                child: Icon(Icons.person, size: 16,
                                    color: theme.primaryColor),
                              ),
                              title: Text(r.memberName ?? 'Unnamed'),
                              subtitle: Text(
                                '${r.label}  ·  ${r.classDate.day}/${r.classDate.month}/${r.classDate.year}',
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }

  Widget _countCard(MemberClass c, ThemeData theme) {
    final count = _counts[c] ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Text('$count',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            c.label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  /// The question a pastor actually asks: why is the convert class bigger than
  /// the worker roll?
  Widget _stallNote(ThemeData theme) {
    final converts = (_counts[MemberClass.convert] ?? 0) +
        (_counts[MemberClass.righteousMember] ?? 0);
    final workers = _counts[MemberClass.worker] ?? 0;
    if (converts == 0 || workers == 0) return const SizedBox.shrink();

    if (converts > workers * 2 && converts >= 5) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.trending_flat, size: 18, color: Colors.amber.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$converts people are still converts but only $workers have '
                'become workers. It may be worth running the classes again.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _openAssignSheet(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AssignClassSheet(
        members: _members,
        service: _service,
      ),
    );
    if (saved == true) await _load();
  }
}

class _AssignClassSheet extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  final ChurchRegistersService service;

  const _AssignClassSheet({required this.members, required this.service});

  @override
  State<_AssignClassSheet> createState() => _AssignClassSheetState();
}

class _AssignClassSheetState extends State<_AssignClassSheet> {
  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _member;
  MemberClass _class = MemberClass.convert;
  int? _stage = 1;
  final _notesCtrl = TextEditingController();
  bool _saving = false;
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

  Future<void> _save() async {
    if (_member == null) {
      setState(() => _error = 'Choose the member.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.setClass(
        memberId: _member!['id'].toString(),
        memberClass: _class,
        convertStage: _class == MemberClass.convert ? _stage : null,
        notes: _notesCtrl.text.trim(),
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
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('Assign a class',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            Text('MEMBER',
                style: theme.textTheme.labelSmall
                    ?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold)),
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
                constraints: const BoxConstraints(maxHeight: 220),
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

            Text('CLASS',
                style: theme.textTheme.labelSmall
                    ?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final c in MemberClass.values)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _class == c,
                    onSelected: (_) => setState(() => _class = c),
                  ),
              ],
            ),
            if (_class == MemberClass.convert) ...[
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1st class')),
                  ButtonSegment(value: 2, label: Text('2nd class')),
                ],
                selected: {_stage ?? 1},
                onSelectionChanged: (s) => setState(() => _stage = s.first),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Notes (optional)',
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
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saving...' : 'Assign'),
            ),
          ],
        ),
      ),
    );
  }
}