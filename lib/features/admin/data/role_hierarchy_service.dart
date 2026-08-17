import 'package:flutter/foundation.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoleApproval {
  final String id;
  final String? tenantId;
  final String userId;
  final String roleName;
  final String? assignedBy;
  final String status;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final String? userFullName;
  final String? userEmail;
  final String? tenantName;

  RoleApproval({
    required this.id,
    this.tenantId,
    required this.userId,
    required this.roleName,
    this.assignedBy,
    this.status = 'pending',
    this.approvedAt,
    required this.createdAt,
    this.userFullName,
    this.userEmail,
    this.tenantName,
  });

  factory RoleApproval.fromMap(Map<String, dynamic> map, {Map<String, dynamic>? profile, Map<String, dynamic>? church}) {
    return RoleApproval(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String?,
      userId: map['user_id'] as String,
      roleName: map['role_name'] as String,
      assignedBy: map['assigned_by'] as String?,
      status: map['status'] as String? ?? 'pending',
      approvedAt: map['approved_at'] != null ? DateTime.parse(map['approved_at'] as String) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      userFullName: profile?['full_name'] as String?,
      userEmail: profile?['email'] as String?,
      tenantName: church?['name'] as String?,
    );
  }
}

class TenantRole {
  final String id;
  final String? tenantId;
  final String roleName;
  final String? displayName;
  final String? description;
  final bool isSystemRole;
  final String? createdBy;

  TenantRole({
    required this.id,
    this.tenantId,
    required this.roleName,
    this.displayName,
    this.description,
    this.isSystemRole = false,
    this.createdBy,
  });

  factory TenantRole.fromMap(Map<String, dynamic> map) {
    return TenantRole(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String?,
      roleName: map['role_name'] as String,
      displayName: map['display_name'] as String?,
      description: map['description'] as String?,
      isSystemRole: map['is_system_role'] as bool? ?? false,
      createdBy: map['created_by'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'tenant_id': tenantId,
    'role_name': roleName,
    'display_name': displayName,
    'description': description,
    'is_system_role': isSystemRole,
    'created_by': createdBy,
  };
}

class RoleHierarchyService {
  final SupabaseService _supabase;

  RoleHierarchyService(this._supabase);

  Future<List<RoleApproval>> getPendingApprovals() async {
    final result = await _supabase.client
        .from('role_assignments')
        .select('*, churches!left(name)')
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    final rows = (result as List).cast<Map<String, dynamic>>();

    final userIds = rows
        .map((e) => e['user_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    Map<String, Map<String, dynamic>> profiles = {};
    if (userIds.isNotEmpty) {
      try {
        final res = await _supabase.client
            .from('profiles')
            .select('id, full_name, email')
            .inFilter('id', userIds);
        profiles = {
          for (final p in (res as List).cast<Map<String, dynamic>>())
            p['id'].toString(): p,
        };
      } catch (e) {
        debugPrint('RoleHierarchyService: profiles fetch error: $e');
      }
    }

    return rows.map((e) {
      final church = e['churches'] as Map<String, dynamic>?;
      return RoleApproval.fromMap(
        e,
        profile: profiles[e['user_id']?.toString()],
        church: church,
      );
    }).toList();
  }

  Future<List<RoleApproval>> getUserAssignments(String userId) async {
    final result = await _supabase.client
        .from('role_assignments')
        .select('*, churches!left(name)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (result as List).map((e) {
      final church = e['churches'] as Map<String, dynamic>?;
      return RoleApproval.fromMap(e, church: church);
    }).toList();
  }

  Future<void> assignRole({
    required String userId,
    required String roleName,
    String? tenantId,
  }) async {
    final currentUser = _supabase.client.auth.currentUser;
    if (currentUser == null) throw Exception("Not authenticated");

    final callerProfile = await _supabase.client
        .from('profiles')
        .select('role, tenant_id')
        .eq('id', currentUser.id)
        .maybeSingle();

    final callerRole = callerProfile?['role'] as String? ?? 'member';
    final callerTenantId = callerProfile?['tenant_id'] as String?;
    final isSuper = callerRole == 'superadmin' || callerRole == 'coa_employee';

    final targetProfile = await _supabase.client
        .from('profiles')
        .select('tenant_id')
        .eq('id', userId)
        .maybeSingle();

    if (targetProfile == null) {
      throw Exception("Target user profile not found");
    }

    final targetTenantId = targetProfile['tenant_id'] as String?;

    if (!isSuper) {
      if (callerTenantId == null || callerTenantId.isEmpty) {
        throw Exception("Security Exception: You must belong to a church to delegate roles.");
      }
      if (targetTenantId != callerTenantId) {
        throw Exception("Security Exception: Pastor/Leader of one tenant cannot access or delegate roles to members of another tenant.");
      }
    }

    final effectiveTenantId = isSuper ? (tenantId ?? callerTenantId) : callerTenantId;

    // Non-superadmins cannot assign platform-level roles
    if (!isSuper && ['superadmin', 'coa_employee'].contains(roleName)) {
      throw Exception("Security Exception: Only COA management can assign platform-level roles.");
    }

    await _supabase.client.from('role_assignments').insert({
      'user_id': userId,
      'role_name': roleName,
      'tenant_id': effectiveTenantId,
      'assigned_by': currentUser.id,
      'status': 'pending',
    });

    final admins = await _supabase
        .client
        .from('profiles')
        .select('id')
        .inFilter('role', ['superadmin', 'coa_employee']);

    if (admins.isNotEmpty) {
      for (final admin in admins as List) {
        if (admin is Map && admin['id'] != null) {
          await _supabase.client.from('notifications').insert({
            'user_id': admin['id'],
            'title': 'New Role Request',
            'body': '$roleName assignment pending approval for user $userId${effectiveTenantId != null ? ' in tenant $effectiveTenantId' : ''}',
            'type': 'role_approval',
            'reference_id': userId,
          });
        }
      }
    }
  }

  Future<void> approveRole(String assignmentId) async {
    final currentUser = _supabase.client.auth.currentUser;
    if (currentUser == null) throw Exception("Not authenticated");

    // Authorization check — only superadmins/coa_employees or the original assigner can approve
    final callerProfile = await _supabase.client
        .from('profiles')
        .select('role')
        .eq('id', currentUser.id)
        .maybeSingle();
    final callerRole = callerProfile?['role'] as String? ?? 'member';
    final isSuper = callerRole == 'superadmin' || callerRole == 'coa_employee';

    final assignment = await _supabase.client
        .from('role_assignments')
        .select('user_id, role_name, assigned_by, status')
        .eq('id', assignmentId)
        .maybeSingle();

    if (assignment == null) throw Exception("Assignment not found");
    if (assignment['status'] != 'pending') throw Exception("Assignment already processed");

    if (!isSuper && assignment['assigned_by'] != currentUser.id) {
      throw Exception("Security Exception: Only COA management or the original assigner can approve role assignments.");
    }

    // Non-superadmins cannot approve platform-level roles
    if (!isSuper && ['superadmin', 'coa_employee'].contains(assignment['role_name'])) {
      throw Exception("Security Exception: Only COA management can approve platform-level roles.");
    }

    await _supabase.client.from('role_assignments').update({
      'status': 'approved',
      'approved_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', assignmentId);

    await _supabase.client.from('profiles').update({
      'role': assignment['role_name'],
    }).eq('id', assignment['user_id']);
  }

  Future<void> rejectRole(String assignmentId, {String? reason}) async {
    await _supabase.client.from('role_assignments').update({
      'status': 'rejected',
      'rejected_at': DateTime.now().toUtc().toIso8601String(),
      'rejection_reason': reason,
    }).eq('id', assignmentId);
  }

  Future<List<TenantRole>> getTenantRoles(String? tenantId) async {
    if (tenantId == null) return [];
    final result = await _supabase.client
        .from('tenant_roles')
        .select('id, tenant_id, role_name, display_name, description, is_system_role, created_by')
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false);
    return (result as List).map((e) => TenantRole.fromMap(e)).toList();
  }

  Future<List<TenantRole>> getSystemRoles() async {
    final result = await _supabase.client
        .from('tenant_roles')
        .select('id, tenant_id, role_name, display_name, description, is_system_role, created_by')
        .eq('is_system_role', true)
        .order('role_name', ascending: true);
    return (result as List).map((e) => TenantRole.fromMap(e)).toList();
  }

  Future<void> createTenantRole(TenantRole role) async {
    await _supabase.client.from('tenant_roles').insert(role.toMap());
  }

  Future<void> deleteTenantRole(String roleId) async {
    await _supabase.client.from('tenant_roles').delete().eq('id', roleId);
  }

  Future<void> elevateRole({
    required String userId,
    required String roleName,
    String? tenantId,
  }) async {
    final currentUser = _supabase.client.auth.currentUser;
    if (currentUser == null) throw Exception("Not authenticated");

    // CRITICAL: Authorization check — only superadmins and coa_employees can elevate
    final callerProfile = await _supabase.client
        .from('profiles')
        .select('role, tenant_id')
        .eq('id', currentUser.id)
        .maybeSingle();
    final callerRole = callerProfile?['role'] as String? ?? 'member';
    final callerTenantId = callerProfile?['tenant_id'] as String?;
    final isSuper = callerRole == 'superadmin' || callerRole == 'coa_employee';

    if (!isSuper) {
      // Tenant leaders can only elevate within their own tenant
      if (callerTenantId == null || callerTenantId.isEmpty) {
        throw Exception("Security Exception: You must belong to a church to elevate roles.");
      }
      final targetProfile = await _supabase.client
          .from('profiles')
          .select('tenant_id')
          .eq('id', userId)
          .maybeSingle();
      if (targetProfile == null) throw Exception("Target user not found");
      if (targetProfile['tenant_id'] != callerTenantId) {
        throw Exception("Security Exception: Cannot elevate users from another tenant.");
      }
      // Non-superadmins cannot elevate to coa_employee or superadmin
      if (['superadmin', 'coa_employee'].contains(roleName)) {
        throw Exception("Security Exception: Only COA management can assign platform-level roles.");
      }
    }

    await _supabase.client.from('role_assignments').insert({
      'user_id': userId,
      'role_name': roleName,
      'tenant_id': tenantId ?? callerTenantId,
      'assigned_by': currentUser.id,
      'status': 'approved',
      'approved_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _supabase.client.from('profiles').update({
      'role': roleName,
    }).eq('id', userId);
  }
}

final roleHierarchyServiceProvider = Provider<RoleHierarchyService>((ref) {
  final supabase = ref.read(supabaseServiceProvider);
  return RoleHierarchyService(supabase);
});

final pendingRoleApprovalsProvider = FutureProvider<List<RoleApproval>>((ref) async {
  return ref.read(roleHierarchyServiceProvider).getPendingApprovals();
});
