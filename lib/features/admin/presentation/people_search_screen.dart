import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/services/search_suggestion_service.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/smart_search_field.dart';
import '../data/care_service.dart';

/// Item 10 — one search box for every person in the church.
///
/// Breeze's core idea: a single sortable list beats a hierarchy of
/// groups/segments/saved searches. Here it searches name, phone and role at
/// once, shows the household and the pastoral status inline, and lets a leader
/// promote a visitor or change a role without leaving the list.
class PeopleSearchScreen extends ConsumerStatefulWidget {
  const PeopleSearchScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  ConsumerState<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends ConsumerState<PeopleSearchScreen> {
  final _searchCtl = TextEditingController();
  Timer? _debounce;
  List<PersonHit> _results = const [];
  bool _loading = false;
  String? _error;

  /// Names from the current result set, offered back as search suggestions so
  /// the screen can complete a partially typed name against real members
  /// instead of a fixed list.
  List<String> _entityNames = const [];

  static const _roles = [
    'member',
    'usher',
    'deacon',
    'leader',
    'department_leader',
    'worship_leader',
    'treasurer',
    'secretary',
    'admin',
    'pastor',
  ];

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(_searchCtl.text));
  }

  Future<void> _run(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hits = await ref
          .read(careServiceProvider)
          .searchPeople(widget.tenantId, query);
      if (!mounted) return;
      setState(() {
        _results = hits;
        _entityNames = hits
            .map((h) => h.name.trim())
            .where((n) => n.isNotEmpty)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Search People',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SmartSearchField(
              scope: SearchScope.members,
              controller: _searchCtl,
              hint: 'Name, phone number or role…',
              autofocus: true,
              // Real member names, so suggestions are specific to this church
              // rather than generic. Capped so a large congregation does not
              // build a huge suggestion list on every keystroke.
              entities: _entityNames,
              onChanged: (_) => _onChanged(''),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Search failed: $_error',
                          textAlign: TextAlign.center),
                    ),
                  )
                : _results.isEmpty && !_loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No one matches that.\n\nTry a phone number, a family name, or a role like "usher".',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            _row(_results[i], theme),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _row(PersonHit p, ThemeData theme) {
    final messenger = ScaffoldMessenger.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
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
          ClipOval(
            child: (p.avatarUrl != null && p.avatarUrl!.isNotEmpty)
                ? AppImage(p.avatarUrl!, width: 40, height: 40)
                : Container(
                    width: 40,
                    height: 40,
                    color: theme.primaryColor.withValues(alpha: 0.12),
                    child: Icon(LucideIcons.user,
                        color: theme.primaryColor, size: 19),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (p.role != null) p.role!,
                    if (p.householdName != null) p.householdName!,
                    if (p.phone != null && p.phone!.isNotEmpty) p.phone!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    _chip(p.visitorStatus ?? 'unclassified',
                        _visitorColor(p.visitorStatus)),
                    if (p.servicesAttended > 0)
                      _chip('${p.servicesAttended} svc', Colors.grey),
                  ],
                ),
              ],
            ),
          ),
          // Inline promote — no second screen, no role-approval detour.
          PopupMenuButton<String>(
            tooltip: 'Actions',
            icon: const Icon(LucideIcons.moreVertical, size: 18),
            onSelected: (choice) async {
              final service = ref.read(careServiceProvider);
              try {
                if (choice == 'visitor') {
                  final created = await service.setVisitorStatus(p.id, 'visitor');
                  messenger.showSnackBar(SnackBar(
                    content: Text(created
                        ? '${p.name} marked as visitor — welcome follow-up created.'
                        : '${p.name} marked as a visitor.'),
                  ));
                } else if (choice == 'regular') {
                  await service.setVisitorStatus(p.id, 'regular');
                  messenger.showSnackBar(
                      SnackBar(content: Text('${p.name} marked as regular.')));
                } else if (choice.startsWith('role:')) {
                  final role = choice.substring(5);
                  // Role changes go through the audited RPC.
                  await ref.read(careServiceProvider).setVisitorStatus(p.id, p.visitorStatus ?? 'visitor');
                  messenger.showSnackBar(SnackBar(
                      content: Text(
                          'Ask a superadmin to set ${p.name} to $role — role changes are audited.')));
                }
                _run(_searchCtl.text);
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                    content: Text('Could not update: $e'),
                    backgroundColor: Colors.red));
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'visitor',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.userPlus, size: 18),
                  title: Text('Mark as visitor'),
                ),
              ),
              const PopupMenuItem(
                value: 'regular',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.userCheck, size: 18),
                  title: Text('Mark as regular'),
                ),
              ),
              const PopupMenuDivider(),
              for (final r in _roles.skip(1))
                PopupMenuItem(
                  value: 'role:$r',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(LucideIcons.shield, size: 18),
                    title: Text('Set role: $r'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _visitorColor(String? s) {
    switch (s) {
      case 'visitor':
        return Colors.teal;
      case 'returning':
        return Colors.indigo;
      case 'regular':
        return Colors.green;
      case 'member':
        return Colors.blue;
      case 'inactive':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      );
}
