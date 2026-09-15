import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/admin/data/role_hierarchy_service.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class RoleApprovalScreen extends ConsumerWidget {
  const RoleApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingRoleApprovalsProvider);
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Role Approvals'),
        actions: [
          if (profile?.isSuperadmin == true || profile?.isEmployee == true)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              onPressed: () => _showElevateDialog(context, ref),
              tooltip: 'Elevate User Role',
            ),
        ],
      ),
      body: pendingAsync.when(
        data: (assignments) => assignments.isEmpty
            ? const Center(child: Text('No pending role approvals'))
            : ListView.builder(
                itemCount: assignments.length,
                itemBuilder: (context, index) {
                  final a = assignments[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(LucideIcons.shield, color: Colors.amber)),
                      title: Text(a.userFullName ?? 'User'),
                      subtitle: Text('${a.roleName}${a.tenantName != null ? " @ ${a.tenantName}" : ""}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.checkCircle, color: Colors.green),
                            onPressed: () async {
                              await ref.read(roleHierarchyServiceProvider).approveRole(a.id);
                              ref.invalidate(pendingRoleApprovalsProvider);
                            },
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.xCircle, color: Colors.red),
                            onPressed: () => _rejectDialog(context, ref, a),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  static const List<String> _assignableRoles = [
    'superadmin',
    'coa_employee',
    'admin',
    'pastor',
    'bishop',
    'prophet',
    'apostle',
    'general_secretary',
    'general_treasurer',
    'treasurer',
    'bookshop_owner',
    'store_manager',
    'assistant',
    'cashier',
    'driver',
    'rider',
    'vendor',
    'merchant',
    'writer',
    'leader',
    'usher',
    'department_leader',
    'worship_leader',
    'praise_team_leader',
    'praise_team_member',
    'member',
  ];

  /// Assign a role by PICKING the user from a searchable list — no email typing.
  ///
  /// Scope: platform staff (superadmin/COA) see every user; a tenant leader
  /// (pastor/bishop/apostle/admin/…) sees only their own church's members, so
  /// they can promote their own people without knowing an email address.
  Future<void> _showElevateDialog(BuildContext context, WidgetRef ref) async {
    final client = ref.read(supabaseServiceProvider).client;
    final me = ref.read(profileProvider).value;
    final isPlatform = me?.role == 'superadmin' ||
        me?.role == 'coa_employee' ||
        me?.role == 'employee';
    final tenantId = me?.tenantId;

    List<Map<String, dynamic>> users = [];
    try {
      var query = client
          .from('profiles')
          .select('id, full_name, email, tenant_id, role');
      if (!isPlatform && tenantId != null && tenantId.isNotEmpty) {
        query = query.eq('tenant_id', tenantId);
      }
      final res = await query.order('full_name').limit(300);
      users = List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load users: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (!context.mounted) return;

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var search = '';
        return StatefulBuilder(builder: (ctx, setSheet) {
          final filtered = users.where((u) {
            if (search.isEmpty) return true;
            final s = search.toLowerCase();
            return (u['full_name'] ?? '').toString().toLowerCase().contains(s) ||
                (u['email'] ?? '').toString().toLowerCase().contains(s);
          }).toList();

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.75,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                const Text('SELECT A USER',
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 12),
                TextField(
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'Search by name…',
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  onChanged: (v) => setSheet(() => search = v.trim()),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text('No users found',
                              style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final u = filtered[i];
                            final name = (u['full_name'] ?? '').toString().trim();
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                              ),
                              title: Text(name.isEmpty ? 'Unnamed member' : name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text(
                                '${u['email'] ?? ''} · ${(u['role'] ?? 'member').toString().replaceAll('_', ' ')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(ctx, u),
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

    if (picked == null || !context.mounted) return;

    // Now choose the role for the picked user.
    String? role;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Assign role to ${picked['full_name'] ?? 'user'}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: DropdownButtonFormField<String>(
            initialValue: role,
            items: _assignableRoles
                .map((r) => DropdownMenuItem(
                    value: r, child: Text(r.replaceAll('_', ' '))))
                .toList(),
            onChanged: (v) => setDlg(() => role = v),
            decoration: const InputDecoration(labelText: 'Role'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (role == null || role!.isEmpty) return;
                try {
                  await ref.read(roleHierarchyServiceProvider).elevateRole(
                        userId: picked['id'].toString(),
                        roleName: role!,
                        tenantId: picked['tenant_id']?.toString(),
                      );
                  ref.invalidate(pendingRoleApprovalsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        '${picked['full_name'] ?? 'User'} is now ${role!.replaceAll('_', ' ')}'),
                    backgroundColor: Colors.green,
                  ));
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('$e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  void _rejectDialog(BuildContext context, WidgetRef ref, RoleApproval approval) {
    final reasonC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Role'),
        content: TextField(
          controller: reasonC,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(roleHierarchyServiceProvider).rejectRole(approval.id, reason: reasonC.text);
              ref.invalidate(pendingRoleApprovalsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}
