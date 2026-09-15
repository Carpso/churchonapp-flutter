import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

/// Tenant OWNER TIER management.
///
/// The owner tier is the set of people whose job is to keep the tenancy paid
/// up. They are never charged for themselves — they only receive payment
/// reminders and can settle the church's subscription.
///
///   * Role-based owners: pastor, bishop, apostle, prophet, general_secretary,
///     general_treasurer, treasurer (local church treasurer).
///   * Custom owners: added here by a PASTOR (for their own church) or by a
///     BISHOP (for any church in their organisation) via `grant_tenant_owner`.
///
/// Assistant pastor / assistant bishop are deliberately NOT owner tier.
class TenantOwnersScreen extends ConsumerStatefulWidget {
  const TenantOwnersScreen({super.key});

  @override
  ConsumerState<TenantOwnersScreen> createState() => _TenantOwnersScreenState();
}

class _TenantOwnersScreenState extends ConsumerState<TenantOwnersScreen> {
  static const _ownerRoles = [
    'pastor',
    'bishop',
    'apostle',
    'prophet',
    'general_secretary',
    'general_treasurer',
    'treasurer',
  ];

  bool _loading = true;
  bool _busy = false;
  bool _iAmOwner = false;
  List<Map<String, dynamic>> _roleOwners = [];
  List<Map<String, dynamic>> _customOwners = [];

  String? get _tenantId => ref.read(profileProvider).value?.tenantId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = ref.read(supabaseServiceProvider).client;
      final tid = _tenantId;

      final ownerCheck = await client.rpc('am_i_tenant_owner');
      final roleRows = tid == null
          ? const <dynamic>[]
          : await client
              .from('profiles')
              .select('id, full_name, role, avatar_url')
              .eq('tenant_id', tid)
              .inFilter('role', _ownerRoles);

      // Custom delegates (active) — two-step profile lookup.
      List<Map<String, dynamic>> custom = [];
      if (tid != null) {
        final deleg = await client
            .from('tenant_owner_delegates')
            .select('user_id, scope, created_at')
            .eq('tenant_id', tid)
            .eq('is_active', true);
        final ids = (deleg as List)
            .map((d) => d['user_id'].toString())
            .toList();
        if (ids.isNotEmpty) {
          final profs = await client
              .from('profiles')
              .select('id, full_name, role, avatar_url')
              .inFilter('id', ids);
          final byId = {
            for (final p in (profs as List)) p['id'].toString(): p,
          };
          custom = deleg
              .map((d) {
                final p = byId[d['user_id'].toString()];
                return p == null
                    ? null
                    : {
                        ...Map<String, dynamic>.from(p),
                        'scope': d['scope'],
                      };
              })
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      }

      if (!mounted) return;
      setState(() {
        _iAmOwner = ownerCheck == true;
        _roleOwners = roleRows.cast<Map<String, dynamic>>();
        _customOwners = custom;
        _loading = false;
      });
    } catch (e) {
      debugPrint('tenant owners load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOwner() async {
    final client = ref.read(supabaseServiceProvider).client;
    final tid = _tenantId;
    if (tid == null) return;

    // Pick a member of this tenant who is not already an owner.
    final already = {
      ..._roleOwners.map((p) => p['id'].toString()),
      ..._customOwners.map((p) => p['id'].toString()),
    };

    List<Map<String, dynamic>> members = [];
    try {
      final rows = await client
          .from('profiles')
          .select('id, full_name, role')
          .eq('tenant_id', tid)
          .limit(300);
      members = (rows as List)
          .cast<Map<String, dynamic>>()
          .where((m) => !already.contains(m['id'].toString()))
          .toList();
    } catch (e) {
      debugPrint('owner picker failed: $e');
    }

    if (!mounted) return;

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String q = '';
        return StatefulBuilder(builder: (ctx, setLocal) {
          final filtered = q.isEmpty
              ? members
              : members
                  .where((m) => (m['full_name'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(q.toLowerCase()))
                  .toList();
          return SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Add an owner',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search by name',
                      prefixIcon: Icon(LucideIcons.search, size: 18),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setLocal(() => q = v),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No members found'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (c, i) {
                            final m = filtered[i];
                            return ListTile(
                              leading: const CircleAvatar(
                                  child: Icon(LucideIcons.user, size: 18)),
                              title: Text(
                                  (m['full_name'] ?? 'Member').toString()),
                              subtitle: Text(
                                  (m['role'] ?? 'member')
                                      .toString()
                                      .toUpperCase(),
                                  style: const TextStyle(fontSize: 11)),
                              onTap: () => Navigator.of(ctx).pop(m),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        });
      },
    );

    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await client.rpc('grant_tenant_owner', params: {
        'p_user_id': picked['id'],
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : null;
      if (map?['granted'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_grantError(map?['reason']?.toString())),
            backgroundColor: Colors.orange,
          ));
        }
      } else {
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add owner: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _grantError(String? reason) {
    switch (reason) {
      case 'org_owner_required':
        return 'Only a bishop (or organisation leader) can add owners for another church.';
      case 'different_organisation':
        return 'That member belongs to a church outside your organisation.';
      case 'not_owner_of_this_church':
        return 'Only an owner of this church can add owners.';
      case 'target_has_no_tenant':
        return 'That user is not part of a church yet.';
      default:
        return 'Could not add that owner.';
    }
  }

  Future<void> _revoke(Map<String, dynamic> owner) async {
    final client = ref.read(supabaseServiceProvider).client;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${owner['full_name'] ?? 'owner'}?'),
        content: const Text(
            'They will no longer receive payment reminders for this church.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('CANCEL')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('REMOVE',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await client.rpc('revoke_tenant_owner', params: {
        'p_user_id': owner['id'],
      });
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Church Owners'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      floatingActionButton: _iAmOwner
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _addOwner,
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.black,
              icon: const Icon(LucideIcons.userPlus),
              label: const Text('ADD OWNER',
                  style:
                      TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: theme.primaryColor.withValues(alpha: 0.35)),
                    ),
                    child: const Text(
                      'These are the people responsible for keeping this church\'s subscription '
                      'paid up. They receive payment reminders and are never charged for themselves.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _section('OWNER ROLES'),
                  ..._roleOwners.map((p) => _tile(theme, p, isRole: true)),
                  const SizedBox(height: 26),
                  _section('ADDED BY LEADERSHIP'),
                  if (_customOwners.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'No custom owners yet. A pastor can add owners for this church, '
                        'or a bishop for any church in their organisation.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  else
                    ..._customOwners.map((p) => _tile(theme, p)),
                ],
              ),
            ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Colors.grey)),
      );

  Widget _tile(ThemeData theme, Map<String, dynamic> p, {bool isRole = false}) {
    final name = (p['full_name'] ?? 'Member').toString();
    final role = (p['role'] ?? '').toString().replaceAll('_', ' ').toUpperCase();
    final scope = (p['scope'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.primaryColor.withValues(alpha: 0.15),
            child: Icon(
              isRole ? LucideIcons.shieldCheck : LucideIcons.userCheck,
              size: 18,
              color: theme.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                Text(
                  isRole
                      ? role
                      : '$role${scope.isEmpty ? '' : ' · ${scope.toUpperCase()}'}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (!isRole && _iAmOwner)
            IconButton(
              icon: const Icon(LucideIcons.trash2, size: 18),
              color: Colors.red,
              tooltip: 'Remove owner',
              onPressed: _busy ? null : () => _revoke(p),
            ),
        ],
      ),
    );
  }
}
