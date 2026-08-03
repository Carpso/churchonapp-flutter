import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/admin/data/tenant_role_service.dart';

class CustomRoleManagementScreen extends ConsumerStatefulWidget {
  const CustomRoleManagementScreen({super.key});

  @override
  ConsumerState<CustomRoleManagementScreen> createState() => _CustomRoleManagementScreenState();
}

class _CustomRoleManagementScreenState extends ConsumerState<CustomRoleManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final tenantId = tenant?.id;
    final tenantName = tenant?.name ?? '';
    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.value;
    final canManage = profile?.isTenantAdmin == true || profile?.isSuperadmin == true || profile?.isEmployee == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles & Permissions'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(LucideIcons.userPlus),
              onPressed: () => _showAssignRoleDialog(context, tenantId, tenantName),
              tooltip: 'Assign Role to Member',
            ),
          if (canManage)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              onPressed: () => _showCreateRoleDialog(context, tenantId, tenantName),
              tooltip: 'Create Custom Role',
            ),
        ],
      ),
      body: tenantId == null
          ? const Center(child: Text('Not assigned to a church'))
          : _buildContent(tenantId, tenantName, canManage),
    );
  }

  Widget _buildContent(String tenantId, String tenantName, bool canManage) {
    final rolesAsync = ref.watch(_tenantRolesProvider(tenantId));
    final membersAsync = ref.watch(_tenantMembersProvider(tenantId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Section 1: Built-in Church Roles ────────────────────────
        _sectionHeader('Church Roles', 'Standard roles available in every church'),
        const SizedBox(height: 8),
        _builtInRoleTile(LucideIcons.crown, 'Pastor', 'Senior spiritual leader', Colors.amber),
        _builtInRoleTile(LucideIcons.shield, 'Bishop', 'Overseer / diocese leader', Colors.indigo),
        _builtInRoleTile(LucideIcons.eye, 'Prophet', 'Prophetic ministry', Colors.purple),
        _builtInRoleTile(LucideIcons.star, 'Apostle', 'Foundational ministry', Colors.blue),
        _builtInRoleTile(LucideIcons.settings, 'Church Admin', 'Day-to-day operations', Colors.teal),
        const Divider(height: 32),

        // ── Section 2: Ministry & Department Roles ──────────────────
        _sectionHeader('Ministry Roles', 'Department and ministry leaders'),
        const SizedBox(height: 8),
        _builtInRoleTile(LucideIcons.banknote, 'Treasurer', 'Financial management', Colors.green),
        _builtInRoleTile(LucideIcons.fileText, 'Secretary', 'Administrative support', Colors.blueGrey),
        _builtInRoleTile(LucideIcons.users, 'Deacon', 'Service ministry', Colors.brown),
        _builtInRoleTile(LucideIcons.scroll, 'Elder', 'Governance & oversight', Colors.orange),
        _builtInRoleTile(LucideIcons.zap, 'Youth Leader', 'Youth ministry', Colors.cyan),
        _builtInRoleTile(LucideIcons.bookOpen, 'Sunday School Teacher', 'Children\'s education', Colors.pink),
        _builtInRoleTile(LucideIcons.music, 'Worship Leader', 'Praise & worship team', Colors.deepPurple),
        _builtInRoleTile(LucideIcons.layoutGrid, 'Department Leader', 'General department head', Colors.indigo),
        _builtInRoleTile(LucideIcons.users, 'Leader', 'Small group / cell leader', Colors.teal),
        _builtInRoleTile(LucideIcons.doorOpen, 'Usher', 'Hospitality & seating', Colors.amber),
        const Divider(height: 32),

        // ── Section 3: Custom Roles ────────────────────────────────
        _sectionHeader('Custom Roles', 'Roles created by your church'),
        const SizedBox(height: 8),
        rolesAsync.when(
          data: (roles) {
            if (roles.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No custom roles yet. Tap + to create one.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ),
              );
            }
            return Column(
              children: roles.map((role) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.shade50,
                    child: Icon(LucideIcons.shield, size: 18, color: Colors.teal),
                  ),
                  title: Text(role.displayName ?? role.roleName),
                  subtitle: Text(role.description ?? 'Custom role', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: canManage ? IconButton(
                    icon: const Icon(LucideIcons.trash2, color: Colors.red, size: 18),
                    onPressed: () => _confirmDeleteRole(context, role, tenantId),
                  ) : null,
                ),
              )).toList(),
              );
          },
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
        ),
        const Divider(height: 32),

        // ── Section 4: Members & Their Roles ───────────────────────
        _sectionHeader('Members & Roles', 'Current role assignments in your church'),
        const SizedBox(height: 8),
        membersAsync.when(
          data: (members) {
            if (members.isEmpty) return const Text('No members yet.');
            return Column(
              children: members.map((m) => ListTile(
                leading: CircleAvatar(
                  child: Text((m['full_name'] ?? '?').toString().substring(0, 1).toUpperCase()),
                ),
                title: Text(m['full_name'] ?? 'Unknown'),
                subtitle: Text(m['email'] ?? ''),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _roleColor(m['role']).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _formatRoleName(m['role'] ?? 'member'),
                    style: TextStyle(color: _roleColor(m['role']), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              )).toList(),
            );
          },
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _builtInRoleTile(IconData icon, String name, String description, Color color) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
    );
  }

  String _formatRoleName(String role) {
    // Convert snake_case or tenant_scoped names to display names
    final parts = role.split('_');
    if (parts.length > 1) {
      // If it's a tenant-scoped role, show only the role key
      return parts.sublist(1).map((p) => p[0].toUpperCase() + p.substring(1)).join(' ');
    }
    return role[0].toUpperCase() + role.substring(1);
  }

  Color _roleColor(String role) {
    if (['superadmin', 'coa_employee'].contains(role)) return Colors.red;
    if (['pastor', 'bishop', 'prophet', 'apostle'].contains(role)) return Colors.indigo;
    if (role == 'admin') return Colors.teal;
    if (['treasurer', 'secretary'].contains(role)) return Colors.green;
    if (['deacon', 'elder'].contains(role)) return Colors.brown;
    if (role.contains('youth')) return Colors.cyan;
    if (role.contains('worship') || role.contains('music')) return Colors.purple;
    if (role.contains('teacher') || role.contains('sunday')) return Colors.pink;
    if (role.contains('usher')) return Colors.amber;
    return Colors.blueGrey;
  }

  void _showCreateRoleDialog(BuildContext context, String? tenantId, String tenantName) {
    final nameC = TextEditingController();
    final displayC = TextEditingController();
    final descC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Custom Role'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(
                labelText: 'Role Key',
                hintText: 'e.g., choir_member',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: displayC,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'e.g., Choir Member',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descC,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameC.text.trim().isEmpty || displayC.text.trim().isEmpty) return;
              try {
                final service = ref.read(tenantRoleServiceProvider);
                await service.createTenantRole(
                  tenantId: tenantId!,
                  roleName: TenantRoleService.generateRoleName(tenantName, nameC.text.trim()),
                  displayName: displayC.text.trim(),
                  description: descC.text.trim(),
                );
                ref.invalidate(_tenantRolesProvider(tenantId));
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showAssignRoleDialog(BuildContext context, String? tenantId, String tenantName) {
    if (tenantId == null) return;

    String? selectedUserId;
    String? selectedRole;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Assign Role to Member'),
          content: FutureBuilder<List<Map<String, dynamic>>>(
            future: ref.read(tenantRoleServiceProvider).getTenantMembersWithRoles(tenantId),
            builder: (ctx, membersSnap) {
              final members = membersSnap.data ?? [];
              return FutureBuilder<List<Map<String, String>>>(
                future: ref.read(tenantRoleServiceProvider).getAvailableRoles(tenantId, tenantName),
                builder: (ctx, rolesSnap) {
                  final roles = rolesSnap.data ?? [];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedUserId,
                        decoration: const InputDecoration(labelText: 'Select Member'),
                        items: members.map((m) => DropdownMenuItem(
                          value: m['id'].toString(),
                          child: Text('${m['full_name'] ?? 'Unknown'} (${_formatRoleName(m['role'] ?? 'member')})'),
                        )).toList(),
                        onChanged: (v) => setDialogState(() => selectedUserId = v),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(labelText: 'Select Role'),
                        items: roles.map((r) => DropdownMenuItem(
                          value: r['role_name'],
                          child: Text(r['display_name']!),
                        )).toList(),
                        onChanged: (v) => setDialogState(() => selectedRole = v),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (selectedUserId == null || selectedRole == null) return;
                try {
                  await ref.read(tenantRoleServiceProvider).assignRoleToUser(
                    userId: selectedUserId!,
                    roleName: selectedRole!,
                    tenantId: tenantId,
                  );
                  ref.invalidate(_tenantMembersProvider(tenantId));
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Role assigned!'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
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

  void _confirmDeleteRole(BuildContext context, TenantRole role, String tenantId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Role?'),
        content: Text('Delete "${role.displayName ?? role.roleName}"? Users with this role will keep it until reassigned.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await ref.read(tenantRoleServiceProvider).deleteTenantRole(role.id);
                ref.invalidate(_tenantRolesProvider(tenantId));
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

final _tenantRolesProvider = FutureProvider.family<List<TenantRole>, String?>((ref, tenantId) async {
  return ref.read(tenantRoleServiceProvider).getTenantRoles(tenantId);
});

final _tenantMembersProvider = FutureProvider.family<List<Map<String, dynamic>>, String?>((ref, tenantId) async {
  if (tenantId == null) return [];
  return ref.read(tenantRoleServiceProvider).getTenantMembersWithRoles(tenantId);
});
