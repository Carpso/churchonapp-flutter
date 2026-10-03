import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/church_audit_service.dart';

/// Who changed what, in this church.
///
/// Aimed at a pastor or treasurer answering "who changed this?" after a
/// dispute, so it reads as plain sentences rather than a database dump.
class ChurchAuditScreen extends StatefulWidget {
  final String? tenantId;

  const ChurchAuditScreen({super.key, this.tenantId});

  @override
  State<ChurchAuditScreen> createState() => _ChurchAuditScreenState();
}

class _ChurchAuditScreenState extends State<ChurchAuditScreen> {
  late final ChurchAuditService _service =
      ChurchAuditService(Supabase.instance.client);

  List<ChurchAuditEntry> _entries = const [];
  List<String> _types = const [];
  String? _filter;
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
        _service.fetchRecent(entityType: _filter),
        if (_filter == null) _service.fetchEntityTypes(),
      ]);
      if (!mounted) return;
      setState(() {
        _entries = results[0] as List<ChurchAuditEntry>;
        if (results.length > 1) {
          _types = results[1] as List<String>;
        }
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
      appBar: AppBar(
        title: const Text('Church Activity Log',
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      body: Column(
        children: [
          if (_types.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _chip('All', null),
                  for (final t in _types) _chip(_typeLabel(t), t),
                ],
              ),
            ),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 40, color: theme.disabledColor),
              const SizedBox(height: 12),
              const Text(
                'The activity log is available to church leadership only.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No recorded changes yet.\n\nMember edits, attendance corrections '
            'and money changes appear here automatically.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => _row(_entries[i], theme),
      ),
    );
  }

  Widget _row(ChurchAuditEntry e, ThemeData theme) {
    final when = _relative(e.createdAt);
    final who = (e.actorRole == null || e.actorRole!.isEmpty)
        ? 'System'
        : e.actorRole!.replaceAll('_', ' ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        child: Icon(_iconFor(e.entityType), size: 18, color: theme.primaryColor),
      ),
      title: Text(e.actionLabel,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$who · ${e.entityLabel} · $when',
              style: theme.textTheme.labelSmall),
          for (final entry in e.changed.entries.take(4)) ...[
            const SizedBox(height: 3),
            _diffLine(theme, entry.key, entry.value['from'], entry.value['to']),
          ],
        ],
      ),
    );
  }

  /// One field change as "phone: 097… → 096…", truncating so a long value does
  /// not blow out the row.
  Widget _diffLine(ThemeData theme, String field, String? from, String? to) {
    String clip(String? v) {
      if (v == null || v.isEmpty) return '(empty)';
      return v.length > 28 ? '${v.substring(0, 28)}…' : v;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
          children: [
            TextSpan(
              text: '${field.replaceAll('_', ' ')}: ',
              style: TextStyle(color: theme.disabledColor),
            ),
            TextSpan(text: clip(from), style: const TextStyle(decoration: TextDecoration.lineThrough)),
            const TextSpan(text: ' → '),
            TextSpan(text: clip(to), style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String? value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _filter = value);
          _load();
        },
      ),
    );
  }

  static String _typeLabel(String t) => switch (t) {
        'profiles' => 'Members',
        'member_attendance' => 'Attendance',
        'transactions' => 'Money',
        'payout_tasks' => 'Payouts',
        _ => t,
      };

  static IconData _iconFor(String t) => switch (t) {
        'profiles' => Icons.person,
        'member_attendance' => Icons.how_to_reg,
        'transactions' => Icons.payments,
        'payout_tasks' => Icons.account_balance,
        _ => Icons.history,
      };

  static String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}