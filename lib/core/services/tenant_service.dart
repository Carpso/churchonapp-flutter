import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Tenant {
  final String id;
  final String slug;
  final String name;
  final String? logoUrl;
  final Color primaryColor;
  final Color accentColor;
  final Map<String, dynamic>? settings;

  Tenant({
    required this.id,
    required this.slug,
    required this.name,
    this.logoUrl,
    required this.primaryColor,
    required this.accentColor,
    this.settings,
  });

  factory Tenant.fromMap(Map<String, dynamic> map) {
    return Tenant(
      id: map['id'] ?? '',
      slug: map['slug'] ?? '',
      name: map['name'] ?? 'Church On App',
      logoUrl: map['logo_url'] ?? map['logo'],
      primaryColor: _parseColor(map['primary_color'], const Color(0xFFFFD700)),
      accentColor: _parseColor(map['accent_color'], const Color(0xFF1A1A1A)),
      settings: map['settings'] is Map ? Map<String, dynamic>.from(map['settings']) : null,
    );
  }

  static Color _parseColor(String? colorString, Color fallback) {
    if (colorString == null || colorString.isEmpty) return fallback;
    try {
      final buffer = StringBuffer();
      if (colorString.length == 6 || colorString.length == 7) buffer.write('ff');
      buffer.write(colorString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return fallback;
    }
  }
}

class TenantService {
  final SupabaseClient _client;
  TenantService(this._client);

  Future<Tenant?> resolveTenant(String slug) async {
    try {
      final data = await _client
          .from('churches')
          .select('*')
          .eq('slug', slug.toLowerCase())
          .maybeSingle();
      
      if (data != null) {
        return Tenant.fromMap(data);
      }
    } catch (e) {
      debugPrint('Error resolving tenant: $e');
    }
    return null;
  }

  Future<Tenant?> getTenantById(String id) async {
    try {
      final data = await _client
          .from('churches')
          .select('*')
          .eq('id', id)
          .maybeSingle();
      
      if (data != null) {
        return Tenant.fromMap(data);
      }
    } catch (e) {
      debugPrint('Error getting tenant by ID: $e');
    }
    return null;
  }
}

final tenantServiceProvider = Provider((ref) => TenantService(Supabase.instance.client));

class CurrentTenantNotifier extends Notifier<Tenant?> {
  @override
  Tenant? build() {
    _loadTenant();
    return null;
  }

  Future<void> _loadTenant() async {
    final prefs = await SharedPreferences.getInstance();
    final tenantId = prefs.getString('selected_tenant_id');
    if (tenantId != null) {
      final service = ref.read(tenantServiceProvider);
      final tenant = await service.getTenantById(tenantId);
      state = tenant;
    }
  }

  Future<void> setTenant(Tenant? tenant) async {
    state = tenant;
    final prefs = await SharedPreferences.getInstance();
    if (tenant != null) {
      await prefs.setString('selected_tenant_id', tenant.id);
    } else {
      await prefs.remove('selected_tenant_id');
    }
  }
}

final currentTenantProvider = NotifierProvider<CurrentTenantNotifier, Tenant?>(() => CurrentTenantNotifier());

final tenantInitializerProvider = FutureProvider<void>((ref) async {
  // Navigation may happen elsewhere, but we ensure at least one attempt to load is made
});
