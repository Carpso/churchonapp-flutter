import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/widgets/app_error_view.dart';
import '../data/care_service.dart';

/// Item 12 — Delegate permissions.
///
/// A pastor is currently the only person who can record attendance, work a
/// follow-up or manage giving. This hands a *scoped* slice of that to an usher
/// or deacon without making them an admin, so Sunday actually works.
class DelegationsScreen extends ConsumerWidget {
  const DelegationsScreen({super.key, required this.tenantId});

  final String tenantId;

  static const _scopes = <String, (String, IconData, String)>{
    'attendance': ('Attendance', LucideIcons.calendarCheck,
        'Record check-ins and view attendance'),
    'followups': ('Pastoral follow-ups', LucideIcons.heartHandshake,
        'Work the care queue and complete follow-ups'),
    'events': ('Events', LucideIcons.calendarDays, 'Create and edit events'),
    'members': ('Member records', LucideIcons.users,
        'View and update member details'),
    'giving': ('Giving records', LucideIcons.receipt,
        'View giving and offering records (read only)'),
    'media': ('Media', LucideIcons.video, 'Upload sermons and klips'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(delegationsProvider(tenantId));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Delegate Permissions',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () => ref.invalidate(delegationsProvider(tenantId)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _grant(context, ref),
        icon: const Icon(LucideIcons.userPlus),
        label: const Text('DELEGATE'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(delegationsProvider(tenantId)),
        ),
        data: (rows) {
          // Group by person so one row per delegate reads clearly.
          final byUser = <String, List<Delegation>>{};
          for (final d in rows) {
            byUser.putIfAbsent(d.userId, () => []).add(d);
          }
          if (byUser.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.shieldCheck,
                        size: 64, color: Colors.grey.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    const Text('Nobody is delegated yet',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Give an usher attendance, or a deacon the pastoral follow-ups, and stop being the only person who can do it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(delegationsProvider(tenantId)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final entry in byUser.entries) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
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
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color:
                                    theme.primaryColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(LucideIcons.userCog,
                                  size: 18, color: theme.primaryColor),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                entry.value.first.userName ?? 'Member',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                              ),
                            ),
                            Text('${entry.value.length} scope'
                                '${entry.value.length == 1 ? '' : 's'}',
                                style:
                                    TextStyle(fontSize: 11, color: Colors.grey[600])),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final d in entry.value)
                              InputChip(
                                label: Text(
                                  _scopes[d.scope]?.$1 ?? d.scope,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                avatar: Icon(
                                    _scopes[d.scope]?.$2 ?? LucideIcons.shield,
                                    size: 14),
                                onDeleted: () async {
                                  await ref
                                      .read(careServiceProvider)
                                      .revokeScope(d.id);
                                  ref.invalidate(delegationsProvider(tenantId));
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _grant(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ScopePickerSheet(tenantId: tenantId),
    );
    if (picked == null || !context.mounted) return;
    // picked = "userId|scope"
    final parts = picked.split('|');
    if (parts.length != 2) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(careServiceProvider).grantScope(
            tenantId: tenantId,
            userId: parts[0],
            scope: parts[1],
          );
      ref.invalidate(delegationsProvider(tenantId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not delegate: $e'),
          backgroundColor: Colors.red));
    }
  }
}

/// Search a member, then choose a scope to hand them.
class _ScopePickerSheet extends ConsumerStatefulWidget {
  const _ScopePickerSheet({required this.tenantId});

  final String tenantId;

  @override
  ConsumerState<_ScopePickerSheet> createState() => _ScopePickerSheetState();
}

class _ScopePickerSheetState extends ConsumerState<_ScopePickerSheet> {
  final _ctl = TextEditingController();
  List<PersonHit> _hits = const [];
  PersonHit? _selected;
  String? _scope;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    try {
      final hits = await ref
          .read(careServiceProvider)
          .searchPeople(widget.tenantId, q, limit: 20);
      if (mounted) setState(() => _hits = hits);
    } catch (_) {
      if (mounted) setState(() => _hits = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Delegate a permission',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Scoped access only — this never makes them an admin.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 14),
            if (_selected == null) ...[
              TextField(
                controller: _ctl,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: 'Search a member…',
                  prefixIcon: const Icon(LucideIcons.search, size: 20),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final h in _hits)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(LucideIcons.user, size: 18),
                        title: Text(h.name, style: const TextStyle(fontSize: 13)),
                        subtitle: h.role == null
                            ? null
                            : Text(h.role!, style: const TextStyle(fontSize: 11)),
                        onTap: () => setState(() => _selected = h),
                      ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                children: [
                  const Icon(LucideIcons.userCheck,
                      size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_selected!.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14))),
                  TextButton(
                    onPressed: () => setState(() => _selected = null),
                    child: const Text('CHANGE'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: _scope,
                onChanged: (v) => setState(() => _scope = v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in DelegationsScreen._scopes.entries)
                      RadioListTile<String>(
                        value: e.key,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.value.$1,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(e.value.$3,
                            style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _scope == null
                      ? null
                      : () => Navigator.pop(
                          context, '${_selected!.id}|$_scope'),
                  child: const Text('GRANT'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
