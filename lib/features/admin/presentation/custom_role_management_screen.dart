import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/admin/data/role_hierarchy_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class CustomRoleManagementScreen extends ConsumerStatefulWidget {
  const CustomRoleManagementScreen({super.key});

  @override
  ConsumerState<CustomRoleManagementScreen> createState() => _CustomRoleManagementScreenState();
}

class _CustomRoleManagementScreenState extends ConsumerState<CustomRoleManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final rolesAsync = ref.watch(_tenantRolesProvider(tenant?.id));
    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.value;
    final canManage = profile?.isSuperadmin == true || profile?.isEmployee == true ||
        profile?.role == 'bishop' || profile?.role == 'pastor' ||
        profile?.role == 'bookshop_owner' || profile?.role == 'prophet' ||
        profile?.role == 'apostle' || profile?.role == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Roles'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              onPressed: () => _createRole(context, tenant?.id),
            ),
        ],
      ),
      body: rolesAsync.when(
        data: (roles) => roles.isEmpty
            ? const Center(child: Text('No custom roles defined'))
            : ListView.builder(
                itemCount: roles.length,
                itemBuilder: (context, index) {
                  final role = roles[index];
                  return ListTile(
                    leading: CircleAvatar(child: Icon(LucideIcons.shield, size: 20)),
                    title: Text(role.displayName ?? role.roleName),
                    subtitle: Text(role.isSystemRole ? 'System role' : 'Custom role'),
                    trailing: canManage && !role.isSystemRole
                        ? IconButton(
                            icon: const Icon(LucideIcons.trash2, color: Colors.red, size: 18),
                            onPressed: () async {
                              await ref.read(roleHierarchyServiceProvider).deleteTenantRole(role.id);
                              ref.invalidate(_tenantRolesProvider(tenant?.id));
                            },
                          )
                        : null,
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }

  void _createRole(BuildContext context, String? tenantId) {
    final nameC = TextEditingController();
    final displayC = TextEditingController();
    final descC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Custom Role'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Role Key (e.g., worship_leader)')),
            TextField(controller: displayC, decoration: const InputDecoration(labelText: 'Display Name')),
            TextField(controller: descC, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(roleHierarchyServiceProvider).createTenantRole(
                TenantRole(
                  id: '',
                  tenantId: tenantId,
                  roleName: nameC.text.trim(),
                  displayName: displayC.text.trim(),
                  description: descC.text.trim(),
                  createdBy: ref.read(supabaseServiceProvider).client.auth.currentUser?.id,
                ),
              );
              ref.invalidate(_tenantRolesProvider(tenantId));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

final _tenantRolesProvider = FutureProvider.family<List<TenantRole>, String?>((ref, tenantId) async {
  return ref.read(roleHierarchyServiceProvider).getTenantRoles(tenantId);
});
