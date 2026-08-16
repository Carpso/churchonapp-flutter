import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'plan_service.dart';

class Tenant {
  final String id;
  final String slug;
  final String? organizationId;
  final String name;
  final String type;

  final String? logoUrl;
  final Color primaryColor;
  final Color accentColor;
  final Color surfaceColor;
  final String fontFamily;
  final String darkMode;
  final double? latitude;
  final double? longitude;
  final Map<String, dynamic>? settings;
  final String? treasurerPhone;
  final String? pastorPhone;
  final String? contactPhone;
  final DateTime? subscriptionEndsAt;
  final String? paymentReference;
  final DateTime? paymentSubmittedAt;
  final TenantPlan plan;
  final bool onboardingFeePaid;
  final DateTime? promotionPlatinumUntil;
  final double onboardingBalanceDue;

  Tenant({
    required this.id,
    required this.slug,
    this.organizationId,
    required this.name,
    this.type = 'church',

    this.logoUrl,
    required this.primaryColor,
    required this.accentColor,
    required this.surfaceColor,
    required this.fontFamily,
    required this.darkMode,
    this.settings,
    this.latitude,
    this.longitude,
    this.treasurerPhone,
    this.pastorPhone,
    this.contactPhone,
    this.subscriptionEndsAt,
    this.paymentReference,
    this.paymentSubmittedAt,
    this.plan = TenantPlan.silver,
    this.onboardingFeePaid = false,
    this.promotionPlatinumUntil,
    this.onboardingBalanceDue = 0,
  });

  bool get isChurch => type == 'church';
  bool get isBookshop => type == 'bookshop';

  ThemeMode get themeMode {
    switch (darkMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  /// The effective plan — if promotion platinum is active, returns platinum.
  TenantPlan get effectivePlan {
    if (promotionPlatinumUntil != null &&
        DateTime.now().isBefore(promotionPlatinumUntil!)) {
      return TenantPlan.platinum;
    }
    return plan;
  }

  PlanLimits get limits => PlanLimits.forPlan(effectivePlan);

  factory Tenant.fromMap(Map<String, dynamic> map) {
    final rawId = (map['id'] ?? map['slug'] ?? '').toString().trim();
    final rawSlug = (map['slug'] ?? map['id'] ?? '').toString().trim();
    return Tenant(
      id: rawId.isNotEmpty ? rawId : 'zm_1',
      slug: rawSlug.isNotEmpty ? rawSlug : 'rock-of-ages-kabulonga',
      organizationId: map['organization_id']?.toString(),
      name: (map['name'] ?? 'Church On App').toString().trim(),
      type: map['type']?.toString() ?? 'church',
      logoUrl: (map['logo_url'] ?? map['logo'])?.toString(),
      primaryColor: _parseColor(
        map['primary_color']?.toString(),
        const Color(0xFFFFD700),
      ),
      accentColor: _parseColor(
        map['accent_color']?.toString(),
        const Color(0xFF1A1A1A),
      ),
      surfaceColor: _parseColor(
        map['surface_color']?.toString(),
        const Color(0xFFFFFAEB), // TODO: replace with Theme.of(context).scaffoldBackgroundColor when context is available
      ),
      fontFamily: map['font_family']?.toString() ?? 'Plus Jakarta Sans',
      darkMode: map['dark_mode']?.toString() ?? 'light',
      settings: (map['settings'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(map['settings'] as Map)
          : null,
      latitude: _parseDouble(map['latitude']),
      longitude: _parseDouble(map['longitude']),
      treasurerPhone: map['treasurer_phone']?.toString(),
      pastorPhone: map['pastor_phone']?.toString(),
      contactPhone: map['contact_phone']?.toString(),
      subscriptionEndsAt:
          _parseDateTime(map['subscription_ends_at']) ??
          (map['seed_ref'] != null ||
                  map['slug'] == 'rock-of-ages-kabulonga' ||
                  rawId.startsWith('zm_') ||
                  rawId.startsWith('zw_')
              ? DateTime.now().add(const Duration(days: 3650))
              : null),
      paymentReference: map['payment_reference']?.toString(),
      paymentSubmittedAt: _parseDateTime(map['payment_submitted_at']),
      plan: PlanLimits.fromString(map['plan']?.toString()),
      onboardingFeePaid: map['onboarding_fee_paid'] == true,
      promotionPlatinumUntil:
          _parseDateTime(map['promotion_platinum_until']),
      onboardingBalanceDue:
          (map['onboarding_balance_due'] as num?)?.toDouble() ?? 0,
    );
  }

  String? get announcement => settings?['announcement']?.toString();

  /// Trial period starts when church is created (30 days).
  bool get isInTrialPeriod {
    if (subscriptionEndsAt == null) return false;
    return DateTime.now().isBefore(subscriptionEndsAt!);
  }

  /// Subscription is expired only AFTER trial + any paid period.
  bool get isSubscriptionExpired {
    if (subscriptionEndsAt == null) return false;
    return DateTime.now().isAfter(subscriptionEndsAt!);
  }

  bool isFeatureEnabled(String featureKey) {
    if (settings == null) return true;
    return (settings?[featureKey] as bool?) ?? true;
  }

  static DateTime? _parseDateTime(dynamic val) {
    if (val == null) return null;
    if (val is DateTime) return val;
    final str = val.toString().trim();
    if (str.isEmpty) return null;
    try {
      return DateTime.parse(str);
    } catch (_) {
      return null;
    }
  }

  static double? _parseDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.trim());
    return null;
  }

  static Color _parseColor(String? colorString, Color fallback) {
    if (colorString == null || colorString.isEmpty) return fallback;
    try {
      final cleanHex = colorString.replaceFirst('#', '');
      final hex = cleanHex.length == 6 ? 'ff$cleanHex' : cleanHex;
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return fallback;
    }
  }
}

class TenantService {
  final SupabaseClient _client;
  TenantService(this._client);

  // Empty by design: churches are loaded from the database only. No church is
  // hardcoded as a default for users — registration/verification data decides.
  static final List<Map<String, dynamic>> fallbackChurches = [];

  /// Resolve a tenant by slug. Queries the `tenants` table first,
  /// then joins to `churches` for church-specific fields.
  Future<Tenant?> resolveTenant(String slug) async {
    try {
      // Try to find via tenants table (works for all tenant types)
      final tenantData = await _client
          .from('tenants')
          .select('id, name, type')
          .eq('id', slug) // slug might be the tenant id
          .maybeSingle();

      if (tenantData != null) {
        return Tenant.fromMap(tenantData);
      }

      // Fallback: query churches table by slug
      final data = await _client
          .from('churches')
          .select(
            'id, slug, name, logo_url, logo, primary_color, accent_color, surface_color, font_family, dark_mode, settings, latitude, longitude, treasurer_phone, subscription_ends_at, payment_reference, payment_submitted_at, plan, onboarding_fee_paid, promotion_platinum_until',
          )
          .eq('slug', slug.toLowerCase())
          .maybeSingle();

      if (data != null) {
        return Tenant.fromMap({...data, 'type': 'church'});
      }
    } catch (e) {
      debugPrint('Error resolving tenant: $e');
    }

    // Fallback
    final fallback = fallbackChurches
        .where((c) => c['slug'] == slug)
        .firstOrNull;
    if (fallback != null) return Tenant.fromMap(fallback);
    return null;
  }

  /// Get a tenant by ID. Queries tenants table first, then churches.
  Future<Tenant?> getTenantById(String id) async {
    try {
      // First try tenants table (works for all types)
      final tenantData = await _client
          .from('tenants')
          .select('id, name, type')
          .eq('id', id)
          .maybeSingle();

      if (tenantData != null) {
        final type = tenantData['type']?.toString() ?? 'church';

        // If church type, also fetch church-specific fields
        if (type == 'church') {
          final churchData = await _client
              .from('churches')
              .select(
                'id, slug, name, logo_url, logo, primary_color, accent_color, surface_color, font_family, dark_mode, settings, latitude, longitude, treasurer_phone, subscription_ends_at, payment_reference, payment_submitted_at, plan, onboarding_fee_paid, promotion_platinum_until',
              )
              .eq('id', id)
              .maybeSingle();

          if (churchData != null) {
            return Tenant.fromMap({...churchData, 'type': 'church'});
          }
        }

        return Tenant.fromMap({...tenantData, 'id': id, 'slug': id});
      }

      // Fallback: query churches table directly
      final data = await _client
          .from('churches')
          .select(
            'id, slug, name, logo_url, logo, primary_color, accent_color, surface_color, font_family, dark_mode, settings, latitude, longitude, treasurer_phone, subscription_ends_at, payment_reference, payment_submitted_at, plan, onboarding_fee_paid, promotion_platinum_until',
          )
          .eq('id', id)
          .maybeSingle();

      if (data != null) {
        return Tenant.fromMap({...data, 'type': 'church'});
      }
    } catch (e) {
      debugPrint('Error getting tenant by ID: $e');
    }

    // Fallback for hardcoded ones
    final fallback = fallbackChurches.where((c) => c['id'] == id).firstOrNull;
    if (fallback != null) return Tenant.fromMap(fallback);
    return null;
  }

  /// Get all tenants (churches + bookshops) for the select screen
  Future<List<Map<String, dynamic>>> getAllTenants() async {
    try {
      // Fetch all churches + bookshops in parallel (avoids N+1 round trips
      // which previously timed out on mobile and fell back to seed data).
      final churchesFuture = _client
          .from('churches')
          .select(
            'id, slug, name, logo_url, primary_color, latitude, longitude, address, country, is_verified, subscription_ends_at',
          )
          .order('name', ascending: true);
      final bookshopsFuture = _client
          .from('bookshops')
          .select('id, name, logo_url, latitude, longitude, address, is_active, tenant_id, subscription_ends_at, plan, onboarding_fee_paid');

      final results = await Future.wait([churchesFuture, bookshopsFuture]);

      final result = <Map<String, dynamic>>[];

      for (final church in (results[0] as List)) {
        final map = Map<String, dynamic>.from(church as Map);
        result.add({
          ...map,
          'type': 'church',
          // Only Rock of Ages Chapel Kabulonga is registered on the platform
          // right now; every other church shows as "Coming Soon".
          '_registered': map['slug'] == 'rock-of-ages-kabulonga',
        });
      }

      for (final shop in (results[1] as List)) {
        final map = Map<String, dynamic>.from(shop as Map);
        result.add({
          ...map,
          'type': 'bookshop',
          '_registered': map['is_active'] == true,
        });
      }

      if (result.isEmpty) {
        return fallbackChurches
            .map(
              (c) => ({...c, '_registered': c['slug'] == 'rock-of-ages-kabulonga'}),
            )
            .toList();
      }
      return result;
    } catch (e) {
      debugPrint('Error fetching all tenants: $e');
      return fallbackChurches
          .map(
            (c) => ({...c, '_registered': c['slug'] == 'rock-of-ages-kabulonga'}),
          )
          .toList();
    }
  }

  Future<List<Tenant>> getNearbyChurches(
    double lat,
    double lng, {
    double radiusKm = 50,
  }) async {
    try {
      final data = await _client
          .from('churches')
          .select(
            'id, slug, name, logo_url, logo, primary_color, accent_color, surface_color, font_family, dark_mode, settings, latitude, longitude, treasurer_phone, subscription_ends_at, payment_reference, payment_submitted_at, plan, onboarding_fee_paid, promotion_platinum_until',
          )
          .not('latitude', 'is', null);

      return (data as List)
          .map((map) => Tenant.fromMap({...map, 'type': 'church'}))
          .toList();
    } catch (e) {
      debugPrint('Error fetching nearby churches: $e');
      return fallbackChurches.map((map) => Tenant.fromMap(map)).toList();
    }
  }
}

final tenantServiceProvider = Provider(
  (ref) => TenantService(Supabase.instance.client),
);

class CurrentTenantNotifier extends Notifier<Tenant?> {
  @override
  Tenant? build() {
    return null;
  }

  Future<void> loadTenant() async {
    final prefs = await SharedPreferences.getInstance();
    final tenantId = prefs.getString('selected_tenant_id');
    if (tenantId != null) {
      final service = ref.read(tenantServiceProvider);
      final tenant = await service.getTenantById(tenantId);
      state = tenant;
    }
  }

  /// Re-fetch the currently selected tenant WITHOUT clearing state first.
  /// Pull-to-refresh on the home tab must not bounce the router to
  /// /select-church (invalidating the provider resets state to null and the
  /// router redirect kicks in). The old tenant stays visible until the
  /// refreshed one arrives.
  Future<void> reload() async {
    final current = state;
    final prefs = await SharedPreferences.getInstance();
    final tenantId = prefs.getString('selected_tenant_id') ?? current?.id;
    if (tenantId == null) return;
    try {
      final service = ref.read(tenantServiceProvider);
      final tenant = await service.getTenantById(tenantId);
      if (tenant != null) state = tenant;
    } catch (e) {
      debugPrint('Error reloading tenant: $e');
    }
  }

  Future<void> setTenant(Tenant? tenant) async {
    state = tenant;
    final prefs = await SharedPreferences.getInstance();
    if (tenant != null) {
      await prefs.setString('selected_tenant_id', tenant.id);
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && tenant.id.isNotEmpty) {
        try {
          await Supabase.instance.client
              .from('profiles')
              .update({'tenant_id': tenant.id})
              .eq('id', user.id);

          // DERIVE ROLE FROM role_assignments FOR NEW TENANT
          // Prevents role carryover: a pastor in Tenant1 is NOT a pastor in Tenant2
          // unless Tenant2 explicitly assigns them that role
          final assignment = await Supabase.instance.client
              .from('role_assignments')
              .select('role_name')
              .eq('user_id', user.id)
              .eq('tenant_id', tenant.id)
              .eq('status', 'approved')
              .order('created_at', ascending: false)
              .maybeSingle();

          final assignedRole = assignment?['role_name'] as String? ?? 'member';
          await Supabase.instance.client
              .from('profiles')
              .update({'role': assignedRole})
              .eq('id', user.id);
        } catch (e) {
          debugPrint('Error updating profile tenant_id on setTenant: $e');
        }
      }
    } else {
      await prefs.remove('selected_tenant_id');
    }
  }
}

final currentTenantProvider = NotifierProvider<CurrentTenantNotifier, Tenant?>(
  () => CurrentTenantNotifier(),
);

final tenantInitializerProvider = FutureProvider<void>((ref) async {
  final notifier = ref.read(currentTenantProvider.notifier);
  await notifier.loadTenant();
});
