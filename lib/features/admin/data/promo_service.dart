import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PromoCampaign {
  final String id;
  final String title;
  final String? description;
  final String campaignType;
  final String? promoCode;
  final int? discountPercent;
  final double? discountAmountZmw;
  final int bonusCoins;
  final double? budgetZmw;
  final double budgetSpentZmw;
  final int? maxRedemptions;
  final int currentRedemptions;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? imageUrl;
  final String? targetUrl;
  final String placement;
  final String? createdBy;
  final DateTime createdAt;

  PromoCampaign({
    required this.id,
    required this.title,
    this.description,
    required this.campaignType,
    this.promoCode,
    this.discountPercent,
    this.discountAmountZmw,
    this.bonusCoins = 0,
    this.budgetZmw,
    this.budgetSpentZmw = 0,
    this.maxRedemptions,
    this.currentRedemptions = 0,
    this.isActive = true,
    this.startsAt,
    this.endsAt,
    this.imageUrl,
    this.targetUrl,
    this.placement = 'home',
    this.createdBy,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory PromoCampaign.fromMap(Map<String, dynamic> m) => PromoCampaign(
    id: m['id'] as String,
    title: m['title'] as String,
    description: m['description'] as String?,
    campaignType: m['campaign_type'] as String? ?? 'promo_code',
    promoCode: m['promo_code'] as String?,
    discountPercent: m['discount_percent'] as int?,
    discountAmountZmw: (m['discount_amount_zmw'] as num?)?.toDouble(),
    bonusCoins: m['bonus_coins'] as int? ?? 0,
    budgetZmw: (m['budget_zmw'] as num?)?.toDouble(),
    budgetSpentZmw: (m['budget_spent_zmw'] as num?)?.toDouble() ?? 0,
    maxRedemptions: m['max_redemptions'] as int?,
    currentRedemptions: m['current_redemptions'] as int? ?? 0,
    isActive: m['is_active'] as bool? ?? true,
    startsAt: m['starts_at'] != null ? DateTime.tryParse(m['starts_at'] as String) : null,
    endsAt: m['ends_at'] != null ? DateTime.tryParse(m['ends_at'] as String) : null,
    imageUrl: m['image_url'] as String?,
    targetUrl: m['target_url'] as String?,
    placement: m['placement'] as String? ?? 'home',
    createdBy: m['created_by'] as String?,
    createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'] as String) ?? DateTime.now() : DateTime.now(),
  );

  bool get isExpired => endsAt != null && endsAt!.isBefore(DateTime.now());
  bool get isBudgetExhausted => budgetZmw != null && budgetSpentZmw >= budgetZmw!;
  bool get isFullyRedeemed => maxRedemptions != null && currentRedemptions >= maxRedemptions!;
  bool get isRedeemable => isActive && !isExpired && !isFullyRedeemed && !isBudgetExhausted;
}

class PromoService {
  final SupabaseService _supabase;

  PromoService(this._supabase);

  Future<List<PromoCampaign>> getAllCampaigns() async {
    final result = await _supabase.client
        .from('promo_campaigns')
        .select()
        .order('created_at', ascending: false);
    return (result as List).map((e) => PromoCampaign.fromMap(e)).toList();
  }

  Future<List<PromoCampaign>> getActiveCampaigns({String? placement}) async {
    var query = _supabase.client
        .from('promo_campaigns')
        .select()
        .eq('is_active', true);
    if (placement != null && placement != 'all') {
      query = query.or('placement.eq.$placement,placement.eq.all');
    }
    final result = await query.order('created_at', ascending: false);
    return (result as List).map((e) => PromoCampaign.fromMap(e)).toList();
  }

  Future<PromoCampaign?> getByPromoCode(String code) async {
    final result = await _supabase.client
        .from('promo_campaigns')
        .select()
        .eq('promo_code', code.toUpperCase())
        .eq('is_active', true)
        .maybeSingle();
    if (result == null) return null;
    final campaign = PromoCampaign.fromMap(result);
    if (!campaign.isRedeemable) return null;
    return campaign;
  }

  Future<void> createCampaign(Map<String, dynamic> data) async {
    await _supabase.client.from('promo_campaigns').insert(data);
  }

  Future<void> updateCampaign(String id, Map<String, dynamic> data) async {
    await _supabase.client.from('promo_campaigns').update(data).eq('id', id);
  }

  Future<void> deleteCampaign(String id) async {
    await _supabase.client.from('promo_campaigns').delete().eq('id', id);
  }

  Future<bool> redeemPromoCode(String code) async {
    final user = _supabase.client.auth.currentUser;
    if (user == null) return false;

    final campaign = await getByPromoCode(code);
    if (campaign == null) return false;

    // Check if already redeemed by this user
    final existing = await _supabase.client
        .from('promo_redemptions')
        .select('id')
        .eq('campaign_id', campaign.id)
        .eq('user_id', user.id)
        .maybeSingle();
    if (existing != null) return false;

    await _supabase.client.from('promo_redemptions').insert({
      'campaign_id': campaign.id,
      'user_id': user.id,
      'reward_type': campaign.bonusCoins > 0 ? 'coins' : 'discount',
      'reward_amount': campaign.bonusCoins > 0 ? campaign.bonusCoins.toDouble() : (campaign.discountAmountZmw ?? 0),
    });

    // Update counters
    await _supabase.client.rpc('increment_promo_redemption', params: {
      'campaign_id_str': campaign.id,
      'amount': campaign.budgetZmw != null ? (campaign.bonusCoins > 0 ? campaign.bonusCoins.toDouble() : (campaign.discountAmountZmw ?? 0)) : 0,
    });

    // Award bonus coins if applicable
    if (campaign.bonusCoins > 0) {
      await _supabase.client.rpc('award_coins', params: {
        'user_id_str': user.id,
        'amount': campaign.bonusCoins,
        'reason_str': 'promo_${campaign.id}',
      });
    }

    return true;
  }
}

final promoServicesProvider = Provider<PromoService>((ref) {
  final supabase = ref.read(supabaseServiceProvider);
  return PromoService(supabase);
});

final allPromoCampaignsProvider = FutureProvider<List<PromoCampaign>>((ref) async {
  return ref.read(promoServicesProvider).getAllCampaigns();
});

final activePromoCampaignsProvider = FutureProvider.family<List<PromoCampaign>, String?>((ref, placement) async {
  return ref.read(promoServicesProvider).getActiveCampaigns(placement: placement);
});
