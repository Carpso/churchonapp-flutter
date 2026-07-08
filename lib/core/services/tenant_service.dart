import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Tenant {
  final String id;
  final String slug;
  final String name;
  final String? shortName;
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
  final DateTime? subscriptionEndsAt;
  final String? paymentReference;
  final DateTime? paymentSubmittedAt;

  Tenant({
    required this.id,
    required this.slug,
    required this.name,
    this.shortName,
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
    this.subscriptionEndsAt,
    this.paymentReference,
    this.paymentSubmittedAt,
  });

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

  factory Tenant.fromMap(Map<String, dynamic> map) {
    return Tenant(
      id: map['id'] ?? '',
      slug: map['slug'] ?? '',
      name: map['name'] ?? 'Church On App',
      shortName: map['short_name'] as String?,
      logoUrl: map['logo_url'] ?? map['logo'],
      primaryColor: _parseColor(map['primary_color'], const Color(0xFFFFD700)),
      accentColor: _parseColor(map['accent_color'], const Color(0xFF1A1A1A)),
      surfaceColor: _parseColor(map['surface_color'], const Color(0xFFFFFAEB)),
      fontFamily: map['font_family']?.toString() ?? 'Plus Jakarta Sans',
      darkMode: map['dark_mode']?.toString() ?? 'light',
      settings: map['settings'] is Map ? Map<String, dynamic>.from(map['settings']) : null,
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
      treasurerPhone: map['treasurer_phone'],
      subscriptionEndsAt: map['subscription_ends_at'] != null 
          ? DateTime.parse(map['subscription_ends_at']) 
          : (map['id']?.toString().startsWith('zm_') == true || map['id']?.toString().startsWith('zw_') == true || map['slug'] == 'rock-of-ages-kabulonga'
              ? DateTime.now().add(const Duration(days: 3650))
              : null),
      paymentReference: map['payment_reference'],
      paymentSubmittedAt: map['payment_submitted_at'] != null ? DateTime.parse(map['payment_submitted_at']) : null,
    );
  }

  bool get isSubscriptionExpired {
    if (subscriptionEndsAt == null) return false;
    return DateTime.now().isAfter(subscriptionEndsAt!);
  }

  bool isFeatureEnabled(String featureKey) {
    if (settings == null) return true; // Default enabled
    return settings![featureKey] ?? true;
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

  static final List<Map<String, dynamic>> fallbackChurches = [
    // ── LUSAKA (Zambia) ──
    {'id': 'zm_1', 'slug': 'st-peters-lusaka', 'name': 'St. Peters Anglican Church', 'address': 'Parliament Rd, Lusaka', 'latitude': -15.4200, 'longitude': 28.3200, 'primary_color': '#8B5CF6', 'country': 'Zambia'},
    {'id': 'zm_2', 'slug': 'bread-of-life', 'name': 'Bread of Life Church Int.', 'address': 'Makeni Road, Lusaka', 'latitude': -15.4500, 'longitude': 28.2500, 'primary_color': '#10B981', 'country': 'Zambia'},
    {'id': 'zm_3', 'slug': 'mushili-catholic', 'name': 'St. Johns Catholic Mushili', 'address': 'Mushili, Ndola', 'latitude': -12.9800, 'longitude': 28.6500, 'primary_color': '#EF4444', 'country': 'Zambia'},
    {'id': 'zm_4', 'slug': 'mount-zion-lusaka', 'name': 'Mount Zion Christian Centre', 'address': 'Chamba Valley, Lusaka', 'latitude': -15.3800, 'longitude': 28.3500, 'primary_color': '#F59E0B', 'country': 'Zambia'},
    {'id': 'zm_5', 'slug': 'praise-christian', 'name': 'Praise Christian Centre', 'address': 'Showgrounds, Lusaka', 'latitude': -15.4000, 'longitude': 28.3100, 'primary_color': '#3B82F6', 'country': 'Zambia'},
    {'id': 'zm_11', 'slug': 'rhema-word', 'name': 'Rhema Bible Church', 'address': 'Makeni, Lusaka', 'latitude': -15.4300, 'longitude': 28.3400, 'primary_color': '#0EA5E9', 'country': 'Zambia'},
    {'id': 'zm_12', 'slug': 'livingstone-central', 'name': 'Central SDA Church Lusaka', 'address': 'Woodlands, Lusaka', 'latitude': -15.3950, 'longitude': 28.3000, 'primary_color': '#14B8A6', 'country': 'Zambia'},
    {'id': 'zm_13', 'slug': 'zambia-shall-be-saved', 'name': 'Zambia Shall Be Saved Ministry', 'address': 'Cairo Road, Lusaka', 'latitude': -15.4166, 'longitude': 28.2870, 'primary_color': '#F97316', 'country': 'Zambia'},
    {'id': 'zm_31', 'slug': 'harvest-lsk', 'name': 'Harvest House International Lusaka', 'address': 'Leopards Hill, Lusaka', 'latitude': -15.4350, 'longitude': 28.3700, 'primary_color': '#EF4444', 'country': 'Zambia'},
    {'id': 'zm_32', 'slug': 'st-ignatius', 'name': 'St. Ignatius Catholic Church', 'address': 'Rhodes Park, Lusaka', 'latitude': -15.4080, 'longitude': 28.3020, 'primary_color': '#3B82F6', 'country': 'Zambia'},
    {'id': 'zm_33', 'slug': 'emmanuel-church', 'name': 'Emmanuel Baptist Church', 'address': 'Longacres, Lusaka', 'latitude': -15.4120, 'longitude': 28.3150, 'primary_color': '#10B981', 'country': 'Zambia'},
    {'id': 'zm_36', 'slug': 'rock-of-ages-kabulonga', 'name': 'Rock Of Ages Chapel Kabulonga', 'address': 'Kabulonga Road next to Dill restaurant, Lusaka', 'latitude': -15.4190, 'longitude': 28.3490, 'primary_color': '#DC2626', 'country': 'Zambia'},

    // ── KITWE ──
    {'id': 'zm_14', 'slug': 'kitwe-chapel', 'name': 'Kitwe Chapel', 'address': 'Obote Avenue, Kitwe', 'latitude': -12.8024, 'longitude': 28.2132, 'primary_color': '#3B82F6', 'country': 'Zambia'},
    {'id': 'zm_15', 'slug': 'ucz-mindolo', 'name': 'UCZ Mindolo Congregation', 'address': 'Mindolo, Kitwe', 'latitude': -12.8100, 'longitude': 28.2300, 'primary_color': '#6366F1', 'country': 'Zambia'},
    {'id': 'zm_16', 'slug': 'sol-kitwe', 'name': 'Salvation Army Kitwe Citadel', 'address': 'Independence Avenue, Kitwe', 'latitude': -12.8050, 'longitude': 28.2100, 'primary_color': '#DC2626', 'country': 'Zambia'},
    {'id': 'zm_34', 'slug': 'riverside-church', 'name': 'Riverside Chapel Kitwe', 'address': 'Riverside, Kitwe', 'latitude': -12.7950, 'longitude': 28.2350, 'primary_color': '#F59E0B', 'country': 'Zambia'},

    // ── NDOLA ──
    {'id': 'zm_17', 'slug': 'ndola-baptist', 'name': 'Ndola Baptist Church', 'address': 'Broadway, Ndola', 'latitude': -12.9587, 'longitude': 28.6366, 'primary_color': '#10B981', 'country': 'Zambia'},
    {'id': 'zm_18', 'slug': 'dag-ndola', 'name': 'Dag Heward-Mills Church Ndola', 'address': 'Kansenshi, Ndola', 'latitude': -12.9700, 'longitude': 28.6400, 'primary_color': '#8B5CF6', 'country': 'Zambia'},
    {'id': 'zm_35', 'slug': 'st-andrews-ndola', 'name': 'St. Andrews United Church Ndola', 'address': 'Broadway, Ndola', 'latitude': -12.9620, 'longitude': 28.6320, 'primary_color': '#6366F1', 'country': 'Zambia'},

    // ── ZIMBABWE ──
    {'id': 'zw_1', 'slug': 'celebration', 'name': 'Celebration Church International', 'address': '162 Borrowdale Rd, Harare', 'latitude': -17.7562, 'longitude': 31.0847, 'primary_color': '#8B5CF6', 'country': 'Zimbabwe'},
    {'id': 'zw_2', 'slug': 'zaoga-fif', 'name': 'ZAOGA Forward in Faith', 'address': 'Zindoga, Waterfalls, Harare', 'latitude': -17.8820, 'longitude': 31.0250, 'primary_color': '#3B82F6', 'country': 'Zimbabwe'},
    {'id': 'zw_3', 'slug': 'harvest-house', 'name': 'Harvest House International', 'address': 'Fife St, Bulawayo', 'latitude': -20.1550, 'longitude': 28.5830, 'primary_color': '#EF4444', 'country': 'Zimbabwe'},
    {'id': 'zw_4', 'slug': 'methodist-zw', 'name': 'Methodist Church in Zimbabwe', 'address': 'Central Ave, Harare', 'latitude': -17.8250, 'longitude': 31.0530, 'primary_color': '#FFD700', 'country': 'Zimbabwe'},
  ];

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
    
    // Fallback
    final fallback = fallbackChurches.where((c) => c['slug'] == slug).firstOrNull;
    if (fallback != null) return Tenant.fromMap(fallback);
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

    // Fallback for hardcoded ones
    final fallback = fallbackChurches.where((c) => c['id'] == id).firstOrNull;
    if (fallback != null) return Tenant.fromMap(fallback);
    return null;
  }

  Future<List<Tenant>> getNearbyChurches(double lat, double lng, {double radiusKm = 50}) async {
    try {
      // In a real app with PostGIS: 
      // return await _client.rpc('nearby_churches', params: {'lat': lat, 'lng': lng, 'radius': radiusKm});
      
      // Simple fallback: Get all churches with coordinates and filter (or use simple box)
      final data = await _client
          .from('churches')
          .select('*')
          .not('latitude', 'is', null);
      
      return (data as List).map((map) => Tenant.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error fetching nearby churches: $e');
      return fallbackChurches.map((map) => Tenant.fromMap(map)).toList();
    }
  }
}

final tenantServiceProvider = Provider((ref) => TenantService(Supabase.instance.client));

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
  final notifier = ref.read(currentTenantProvider.notifier);
  await notifier.loadTenant();
});

