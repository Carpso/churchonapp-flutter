import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TenantAd {
  final String id;
  final String title;
  final String? description;
  final String? imageUrl;
  final String? targetUrl;
  final String adType;
  final String placement;
  final bool isActive;
  final String tenantId;
  final bool isPlatformWide;
  final DateTime? endsAt;
  final int? maxImpressions;

  TenantAd({
    required this.id,
    required this.title,
    this.description,
    this.imageUrl,
    this.targetUrl,
    required this.adType,
    required this.placement,
    this.isActive = true,
    required this.tenantId,
    this.isPlatformWide = false,
    this.endsAt,
    this.maxImpressions,
  });

  int get priority => maxImpressions ?? 0;

  factory TenantAd.fromMap(Map<String, dynamic> map) {
    final platformWide = (map['is_platform_wide'] as bool? ?? false) ||
        map['placement'] == 'all' ||
        map['tenant_id'] == null;
    return TenantAd(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      imageUrl: map['image_url'] as String?,
      targetUrl: map['target_url'] as String?,
      adType: map['ad_type'] as String? ?? 'banner',
      placement: map['placement'] as String? ?? 'home',
      isActive: map['is_active'] as bool? ?? true,
      tenantId: map['tenant_id']?.toString() ?? '',
      isPlatformWide: platformWide,
      endsAt: map['ends_at'] != null ? DateTime.parse(map['ends_at'] as String) : null,
      maxImpressions: map['max_impressions'] as int?,
    );
  }
}

class AdService {
  final SupabaseService _supabase;

  AdService(this._supabase);

  Future<List<TenantAd>> getAllAds() async {
    final result = await _supabase.client.from('tenant_ads')
        .select('id, title, description, image_url, target_url, ad_type, placement, is_active, tenant_id, is_platform_wide, ends_at, max_impressions')
        .order('created_at', ascending: false);
    return (result as List).map((e) => TenantAd.fromMap(e)).toList();
  }

  Future<List<TenantAd>> getActiveAds({String? tenantId, String? placement}) async {
    var query = _supabase.client
        .from('tenant_ads')
        .select('id, title, description, image_url, target_url, ad_type, placement, is_active, tenant_id, is_platform_wide, ends_at, max_impressions')
        .eq('is_active', true);

    if (tenantId != null) {
      query = query.eq('tenant_id', tenantId);
    }
    if (placement != null && placement != 'all') {
      query = query.or('placement.eq.$placement,placement.eq.all');
    }

    final result = await query.order('created_at', ascending: false);
    return (result as List).map((e) => TenantAd.fromMap(e)).toList();
  }

  Future<void> trackImpression(String adId) async {
    await _supabase.client.rpc('increment_ad_impression', params: {'ad_id_str': adId});
  }

  Future<void> createAd(Map<String, dynamic> data) async {
    await _supabase.client.from('tenant_ads').insert(data);
  }

  Future<void> updateAd(String adId, Map<String, dynamic> data) async {
    await _supabase.client.from('tenant_ads').update(data).eq('id', adId);
  }

  Future<void> deleteAd(String adId) async {
    await _supabase.client.from('tenant_ads').delete().eq('id', adId);
  }

  Future<void> promoteAd(String adId, String paymentMethod, int coinsSpent) async {
    await _supabase.client.from('tenant_ads').update({
      'is_promoted': true,
      'promoted_at': DateTime.now().toIso8601String(),
      'payment_method': paymentMethod,
      'coins_spent': coinsSpent,
    }).eq('id', adId);
  }

  Future<void> promoteWithMobileMoney(String adId, double amountZmw, String paymentRef) async {
    await _supabase.client.from('tenant_ads').update({
      'is_promoted': true,
      'promoted_at': DateTime.now().toIso8601String(),
      'payment_method': 'mobile_money',
      'payment_amount_zmw': amountZmw,
      'payment_ref': paymentRef,
    }).eq('id', adId);
  }
}

final adServiceProvider = Provider<AdService>((ref) {
  final supabase = ref.read(supabaseServiceProvider);
  return AdService(supabase);
});

final allAdsProvider = FutureProvider<List<TenantAd>>((ref) async {
  final service = ref.read(adServiceProvider);
  return service.getAllAds();
});

final activeAdsProvider = FutureProvider.family<List<TenantAd>, String?>((ref, placement) async {
  final service = ref.read(adServiceProvider);
  return service.getActiveAds(placement: placement);
});
