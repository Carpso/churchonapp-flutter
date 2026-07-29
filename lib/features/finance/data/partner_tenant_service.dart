import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/code_generator_service.dart';

class PartnerTenant {
  final String id;
  final String name;
  final String type; // 'bookshop', 'coffee_shop', 'restaurant', 'other'
  final String? description;
  final String? location;
  final String? logoUrl;
  final bool isActive;
  final DateTime createdAt;

  PartnerTenant({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.location,
    this.logoUrl,
    required this.isActive,
    required this.createdAt,
  });

  factory PartnerTenant.fromMap(Map<String, dynamic> map) {
    return PartnerTenant(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Partner',
      type: map['type'] as String? ?? 'other',
      description: map['description'] as String?,
      location: map['location'] as String?,
      logoUrl: map['logo_url'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now(),
    );
  }
}

class PartnerOffer {
  final String id;
  final String partnerId;
  final String title;
  final String? description;
  final int coinsRequired;
  final String? imageUrl;
  final bool isActive;
  final int redeemedCount;
  final DateTime createdAt;

  PartnerOffer({
    required this.id,
    required this.partnerId,
    required this.title,
    this.description,
    required this.coinsRequired,
    this.imageUrl,
    required this.isActive,
    required this.redeemedCount,
    required this.createdAt,
  });

  factory PartnerOffer.fromMap(Map<String, dynamic> map) {
    return PartnerOffer(
      id: map['id'] as String,
      partnerId: map['partner_id'] as String,
      title: map['title'] as String? ?? 'Offer',
      description: map['description'] as String?,
      coinsRequired: (map['coins_required'] as num?)?.toInt() ?? 100,
      imageUrl: map['image_url'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      redeemedCount: (map['redeemed_count'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now(),
    );
  }
}

class PartnerTenantService {
  final SupabaseClient _client;
  PartnerTenantService(this._client);

  Future<List<PartnerTenant>> getPartnerTenants() async {
    try {
      final res = await _client
          .from('partner_tenants')
          .select()
          .eq('is_active', true)
          .order('name');
      return (res as List).map((m) => PartnerTenant.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error fetching partner tenants: $e');
      // Return default COA partner fallback list
      return [
        PartnerTenant(
          id: 'partner_bookshop_1',
          name: 'Bookshop & Stationery',
          type: 'bookshop',
          description: 'Redeem Church Coins for Bibles, Christian literature & study guides.',
          location: 'Cairo Road, Lusaka',
          logoUrl: null,
          isActive: true,
          createdAt: DateTime.now(),
        ),
        PartnerTenant(
          id: 'partner_coffee_1',
          name: 'Grace & Bean Coffee House',
          type: 'coffee_shop',
          description: 'Enjoy handcrafted coffees and pastries in exchange for Church Coins.',
          location: 'East Park Mall, Lusaka',
          logoUrl: null,
          isActive: true,
          createdAt: DateTime.now(),
        ),
      ];
    }
  }

  Future<List<PartnerOffer>> getPartnerOffers(String partnerId) async {
    try {
      final res = await _client
          .from('partner_offers')
          .select()
          .eq('partner_id', partnerId)
          .eq('is_active', true)
          .order('coins_required');
      return (res as List).map((m) => PartnerOffer.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error fetching partner offers: $e');
      return [
        PartnerOffer(
          id: 'offer_1',
          partnerId: partnerId,
          title: 'K50 Discount Voucher',
          description: 'Redeem 500 Church Coins for K50 voucher at checkout.',
          coinsRequired: 500,
          isActive: true,
          redeemedCount: 12,
          createdAt: DateTime.now(),
        ),
        PartnerOffer(
          id: 'offer_2',
          partnerId: partnerId,
          title: 'Free Christian Journal / Book',
          description: 'Redeem 1,000 Church Coins for a hardcover journal.',
          coinsRequired: 1000,
          isActive: true,
          redeemedCount: 8,
          createdAt: DateTime.now(),
        ),
      ];
    }
  }

  Future<String> redeemOffer({
    required String offerId,
    required String partnerId,
    required int coinsRequired,
    required String offerTitle,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    // Check user coin balance
    final profile = await _client
        .from('profiles')
        .select('coins')
        .eq('id', user.id)
        .maybeSingle();

    final currentCoins = (profile?['coins'] as num?)?.toInt() ?? 0;
    if (currentCoins < coinsRequired) {
      throw Exception("Insufficient Church Coins! You have $currentCoins CC but need $coinsRequired CC.");
    }

    // Generate unique redemption voucher code
    final codeGen = CodeGeneratorService(_client);
    final formattedVoucher = await codeGen.generateVoucherCode('Zambia');

    // Deduct coins using RPC or profile update
    try {
      await _client.rpc('add_coins', params: {
        'user_id': user.id,
        'amount': -coinsRequired,
      });
    } catch (_) {
      await _client.from('profiles').update({
        'coins': currentCoins - coinsRequired,
      }).eq('id', user.id);
    }

    // Log redemption in DB
    try {
      await _client.from('coin_redemptions').insert({
        'user_id': user.id,
        'amount': coinsRequired,
        'redemption_type': 'partner_offer',
        'partner_id': partnerId,
        'description': '$offerTitle (Voucher: $formattedVoucher)',
        'status': 'completed',
      });

      // Register code in code registry
      await codeGen.registerCode(
        codeType: 'partner_voucher',
        codeValue: formattedVoucher,
        countryIso: 'ZM',
        userId: user.id,
        metadata: {'offer_id': offerId, 'partner_id': partnerId, 'coins': coinsRequired},
      );
    } catch (e) {
      debugPrint('Warning logging redemption: $e');
    }

    return formattedVoucher;
  }

  Future<void> createPartnerTenant({
    required String name,
    required String type,
    String? description,
    String? location,
    String? logoUrl,
  }) async {
    await _client.from('partner_tenants').insert({
      'name': name,
      'type': type,
      'description': description,
      'location': location,
      'logo_url': logoUrl,
      'is_active': true,
    });
  }

  Future<void> createPartnerOffer({
    required String partnerId,
    required String title,
    String? description,
    required int coinsRequired,
    String? imageUrl,
  }) async {
    await _client.from('partner_offers').insert({
      'partner_id': partnerId,
      'title': title,
      'description': description,
      'coins_required': coinsRequired,
      'image_url': imageUrl,
      'is_active': true,
    });
  }
}

final partnerTenantServiceProvider = Provider<PartnerTenantService>((ref) {
  return PartnerTenantService(Supabase.instance.client);
});
