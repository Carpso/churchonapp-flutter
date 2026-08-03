import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Represents a role defined for a specific tenant.
class TenantRole {
  final String id;
  final String tenantId;
  final String roleName;
  final String? displayName;
  final String? description;
  final List<String> permissions;
  final bool isSystemRole;
  final String? createdBy;
  final DateTime createdAt;

  TenantRole({
    required this.id,
    required this.tenantId,
    required this.roleName,
    this.displayName,
    this.description,
    this.permissions = const [],
    this.isSystemRole = false,
    this.createdBy,
    required this.createdAt,
  });

  factory TenantRole.fromMap(Map<String, dynamic> map) {
    final rawPerms = map['permissions'];
    List<String> perms = [];
    if (rawPerms is List) {
      perms = rawPerms.map((e) => e.toString()).toList();
    } else if (rawPerms is String) {
      // Handle JSON string
      perms = rawPerms.replaceAll('[', '').replaceAll(']', '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return TenantRole(
      id: map['id']?.toString() ?? '',
      tenantId: map['tenant_id']?.toString() ?? '',
      roleName: map['role_name']?.toString() ?? '',
      displayName: map['display_name']?.toString(),
      description: map['description']?.toString(),
      permissions: perms,
      isSystemRole: map['is_system_role'] ?? false,
      createdBy: map['created_by']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }
}

/// Service for managing dynamic tenant-scoped roles.
///
/// Role naming convention: `{tenant_name}_{role_key}`
/// e.g., "Grace Church_deacon", "Faith Bookshop_cashier"
///
/// Tenant admins (pastor/bishop/admin) can:
/// - Create custom roles for their tenant
/// - Assign/revoke roles to members within their tenant
/// - View all roles defined for their tenant
class TenantRoleService {
  final SupabaseClient _client;

  TenantRoleService(this._client);

  // ─── Role Name Generation ──────────────────────────────────────────

  /// Generate a tenant-scoped role name.
  /// Format: `{tenant_name}_{role_key}`
  static String generateRoleName(String tenantName, String roleKey) {
    final sanitizedTenant = tenantName
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
    final sanitizedRole = roleKey
        .replaceAll(RegExp(r'[^\w]'), '')
        .trim()
        .toLowerCase();
    return '${sanitizedTenant}_$sanitizedRole';
  }

  /// Check if a role is a tenant-scoped role (contains underscore, not a platform role).
  static bool isTenantScopedRole(String? role) {
    if (role == null || role.isEmpty) return false;
    // Platform roles — never tenant-scoped
    const platformRoles = {
      'superadmin', 'coa_employee', 'member', 'driver', 'rider',
      'pastor', 'bishop', 'prophet', 'apostle', 'admin',
    };
    if (platformRoles.contains(role)) return false;
    // Tenant roles have the pattern: {tenant_name}_{role_key}
    return role.contains('_');
  }

  /// Extract the role key from a tenant-scoped role name.
  /// e.g., "Grace_Church_deacon" → "deacon"
  static String? extractRoleKey(String role) {
    if (!isTenantScopedRole(role)) return null;
    final parts = role.split('_');
    return parts.last;
  }

  // ─── CRUD Operations ──────────────────────────────────────────────

  /// Get all roles defined for a tenant.
  Future<List<TenantRole>> getTenantRoles(String? tenantId) async {
    if (tenantId == null) return [];
    try {
      final res = await _client
          .from('tenant_roles')
          .select()
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: true);
      return (res as List).map((e) => TenantRole.fromMap(e)).toList();
    } catch (e) {
      debugPrint('TenantRoleService: getTenantRoles failed: $e');
      return [];
    }
  }

  /// Create a new role for a tenant.
  Future<TenantRole> createTenantRole({
    required String tenantId,
    required String roleName,
    required String displayName,
    String? description,
    List<String> permissions = const [],
  }) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) throw Exception("Not authenticated");

    // Check uniqueness within tenant
    final existing = await _client
        .from('tenant_roles')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('role_name', roleName)
        .maybeSingle();
    if (existing != null) throw Exception("Role '$roleName' already exists in this tenant");

    final res = await _client.from('tenant_roles').insert({
      'tenant_id': tenantId,
      'role_name': roleName,
      'display_name': displayName,
      'description': description,
      'permissions': permissions,
      'created_by': currentUser.id,
    }).select().single();

    return TenantRole.fromMap(res);
  }

  /// Delete a custom role (cannot delete system roles).
  Future<void> deleteTenantRole(String roleId) async {
    final role = await _client.from('tenant_roles').select('is_system_role').eq('id', roleId).maybeSingle();
    if (role?['is_system_role'] == true) throw Exception("Cannot delete system roles");
    await _client.from('tenant_roles').delete().eq('id', roleId);
  }

  // ─── Role Assignment ──────────────────────────────────────────────

  /// Assign a tenant role to a user (immediate, for tenant admins).
  /// Creates role_assignments record + updates profiles.role.
  Future<void> assignRoleToUser({
    required String userId,
    required String roleName,
    required String tenantId,
  }) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) throw Exception("Not authenticated");

    // Verify caller is authorized (tenant admin or superadmin)
    final callerProfile = await _client
        .from('profiles')
        .select('role, tenant_id')
        .eq('id', currentUser.id)
        .maybeSingle();
    final callerRole = callerProfile?['role'] as String? ?? 'member';
    final callerTenantId = callerProfile?['tenant_id'] as String?;
    final isSuper = callerRole == 'superadmin' || callerRole == 'coa_employee';

    if (!isSuper) {
      if (callerTenantId == null || callerTenantId.isEmpty) {
        throw Exception("You must belong to a church to assign roles.");
      }
      if (callerTenantId != tenantId) {
        throw Exception("Cannot assign roles to users in another tenant.");
      }
      // Tenant admins cannot assign platform-level roles
      if (['superadmin', 'coa_employee'].contains(roleName)) {
        throw Exception("Only COA management can assign platform-level roles.");
      }
    }

    // Verify the role exists in tenant_roles (if it's a tenant-scoped role)
    if (isTenantScopedRole(roleName)) {
      final roleExists = await _client
          .from('tenant_roles')
          .select('id')
          .eq('tenant_id', tenantId)
          .eq('role_name', roleName)
          .maybeSingle();
      if (roleExists == null) {
        throw Exception("Role '$roleName' does not exist in this tenant's role catalog. Create it first.");
      }
    }

    // Verify target user is in the same tenant
    final targetProfile = await _client
        .from('profiles')
        .select('tenant_id')
        .eq('id', userId)
        .maybeSingle();
    if (targetProfile == null) throw Exception("Target user not found");
    if (!isSuper && targetProfile['tenant_id'] != tenantId) {
      throw Exception("Cannot assign roles to users in another tenant.");
    }

    // Deactivate previous role assignments for this user in this tenant
    await _client
        .from('role_assignments')
        .update({'status': 'superseded'})
        .eq('user_id', userId)
        .eq('tenant_id', tenantId)
        .eq('status', 'approved');

    // Create new assignment (approved immediately by tenant admin)
    await _client.from('role_assignments').insert({
      'user_id': userId,
      'role_name': roleName,
      'tenant_id': tenantId,
      'assigned_by': currentUser.id,
      'status': 'approved',
      'approved_at': DateTime.now().toUtc().toIso8601String(),
    });

    // Update profile.role ONLY if the target user's current tenant matches
    // the assignment's tenant. If they're in a different tenant, their
    // profile.role will be derived from role_assignments when they switch.
    if (targetProfile['tenant_id'] == tenantId) {
      await _client.from('profiles').update({'role': roleName}).eq('id', userId);
    }
  }

  /// Revoke a user's role (revert to member).
  Future<void> revokeRole({
    required String userId,
    required String tenantId,
  }) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) throw Exception("Not authenticated");

    // Deactivate all approved role assignments for this user
    await _client
        .from('role_assignments')
        .update({'status': 'revoked'})
        .eq('user_id', userId)
        .eq('tenant_id', tenantId)
        .eq('status', 'approved');

    // Reset profile.role to 'member' ONLY if the user's current tenant
    // matches the revocation tenant. Otherwise their profile.role will
    // be recalculated from role_assignments when they switch tenants.
    final targetProfile = await _client
        .from('profiles')
        .select('tenant_id')
        .eq('id', userId)
        .maybeSingle();
    if (targetProfile?['tenant_id'] == tenantId) {
      await _client.from('profiles').update({'role': 'member'}).eq('id', userId);
    }
  }

  /// Get all available role names for a tenant (from tenant_roles + built-in tenant roles).
  Future<List<Map<String, String>>> getAvailableRoles(String tenantId, String tenantName) async {
    // Built-in tenant roles
    final builtIn = [
      {'role_name': 'admin', 'display_name': 'Church Admin'},
      {'role_name': 'pastor', 'display_name': 'Pastor'},
      {'role_name': 'bishop', 'display_name': 'Bishop'},
      {'role_name': 'prophet', 'display_name': 'Prophet'},
      {'role_name': 'apostle', 'display_name': 'Apostle'},
      {'role_name': 'treasurer', 'display_name': 'Treasurer'},
      {'role_name': 'secretary', 'display_name': 'Secretary'},
      {'role_name': 'usher', 'display_name': 'Usher'},
      {'role_name': 'deacon', 'display_name': 'Deacon'},
      {'role_name': 'elder', 'display_name': 'Elder'},
      {'role_name': 'youth_leader', 'display_name': 'Youth Leader'},
      {'role_name': 'sunday_school_teacher', 'display_name': 'Sunday School Teacher'},
      {'role_name': 'worship_leader', 'display_name': 'Worship Leader'},
      {'role_name': 'department_leader', 'display_name': 'Department Leader'},
      {'role_name': 'leader', 'display_name': 'Leader'},
    ];

    // Custom roles from tenant_roles table
    final customRoles = await getTenantRoles(tenantId);
    final custom = customRoles.map((r) => {
      'role_name': r.roleName,
      'display_name': r.displayName ?? r.roleName,
    }).toList();

    return [...builtIn, ...custom];
  }

  /// Get all users in a tenant with their current roles.
  Future<List<Map<String, dynamic>>> getTenantMembersWithRoles(String tenantId) async {
    final res = await _client
        .from('profiles')
        .select('id, full_name, email, role, avatar_url')
        .eq('tenant_id', tenantId)
        .order('full_name');
    return List<Map<String, dynamic>>.from(res);
  }
}

final tenantRoleServiceProvider = Provider<TenantRoleService>((ref) {
  final client = Supabase.instance.client;
  return TenantRoleService(client);
});
