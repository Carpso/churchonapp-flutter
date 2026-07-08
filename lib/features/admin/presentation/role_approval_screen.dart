import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/admin/data/role_hierarchy_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class RoleApprovalScreen extends ConsumerWidget {
  const RoleApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingRoleApprovalsProvider);
    final profile = ref.watch(profileProvider).asData?.value;

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

  void _showElevateDialog(BuildContext context, WidgetRef ref) {
    final emailC = TextEditingController();
    final roleC = TextEditingController();
    final tenants = ref.watch(currentTenantProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elevate User Role'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: emailC, decoration: const InputDecoration(labelText: 'User Email', hintText: 'user@email.com')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: null,
              items: 'superadmin,employee,admin,pastor,bishop,prophet,apostle,bookshop_owner,driver,writer,leader,vendor,usher,merchant'
                  .split(',').map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => roleC.text = v ?? '',
              decoration: const InputDecoration(labelText: 'Role'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                final userResult = await ref.read(supabaseServiceProvider).client
                    .from('profiles')
                    .select('id')
                    .eq('email', emailC.text.trim())
                    .maybeSingle();
                if (userResult == null) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('User not found'), backgroundColor: Colors.red));
                  return;
                }
                await ref.read(roleHierarchyServiceProvider).elevateRole(
                  userId: userResult['id'],
                  roleName: roleC.text,
                  tenantId: tenants?.id,
                );
                ref.invalidate(pendingRoleApprovalsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role elevated!'), backgroundColor: Colors.green));
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('Elevate'),
          ),
        ],
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
