import 'package:supabase_flutter/supabase_flutter.dart';

/// Generates and manages tenant-scoped employee roles.
/// e.g., "Grace Church_employee", "Faith Bookshop_employee"
class TenantEmployeeService {
  final SupabaseClient _client;

  TenantEmployeeService(this._client);

  /// Generate a tenant-scoped employee role name.
  /// Format: `{tenant_name}_employee`
  static String generateRoleName(String tenantName) {
    // Sanitize: remove special chars, trim, lowercase for consistency
    final sanitized = tenantName
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return '${sanitized}_employee';
  }

  /// Check if a role is a tenant employee role (ends with _employee and is NOT coa_employee)
  static bool isTenantEmployeeRole(String? role) {
    if (role == null || role.isEmpty) return false;
    return role.endsWith('_employee') && role != 'coa_employee';
  }

  /// Extract the tenant name from a tenant employee role name.
  /// e.g., "Grace Church_employee" → "Grace Church"
  static String? extractTenantName(String role) {
    if (!isTenantEmployeeRole(role)) return null;
    return role.substring(0, role.length - '_employee'.length);
  }

  /// Assign a tenant employee role to a user.
  /// The role name is auto-generated from the tenant name.
  Future<void> assignTenantEmployee({
    required String userId,
    required String tenantId,
    required String tenantName,
  }) async {
    final roleName = generateRoleName(tenantName);

    // Check if role exists in tenant_roles, create if not
    final existing = await _client
        .from('tenant_roles')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('role_name', roleName)
        .maybeSingle();

    if (existing == null) {
      await _client.from('tenant_roles').insert({
        'tenant_id': tenantId,
        'role_name': roleName,
        'display_name': 'Staff',
        'description': 'Staff member at $tenantName',
        'permissions': ['member_management', 'content_management', 'reports'],
      });
    }

    // Create role assignment
    await _client.from('role_assignments').insert({
      'user_id': userId,
      'role_name': roleName,
      'tenant_id': tenantId,
      'status': 'approved',
      'approved_at': DateTime.now().toUtc().toIso8601String(),
    });

    // Update profile
    await _client.from('profiles').update({
      'role': roleName,
    }).eq('id', userId);
  }
}
