import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
export 'cart_provider.dart';

class MarketProduct {
  final String id;
  final String name;
  final double price;
  final String? category;
  final String? image;
  final String? description;
  final String? vendorName;
  final String? vendorId;
  final String? tenantId;
  final String? condition;
  final String marketType;
  final bool isCurated;

  MarketProduct({
    required this.id,
    required this.name,
    required this.price,
    this.category,
    this.image,
    this.description,
    this.vendorName,
    this.vendorId,
    this.tenantId,
    this.condition,
    this.marketType = 'general',
    this.isCurated = false,
  });

  factory MarketProduct.fromMap(Map<String, dynamic> map) {
    return MarketProduct(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      category: map['category'],
      image: map['image'],
      description: map['description'],
      vendorName: map['vendorName'] ?? map['vendor_name'],
      vendorId: map['vendorId'] ?? map['vendor_id'],
      tenantId: map['tenant_id']?.toString(),
      condition: map['condition'],
      marketType: map['marketType'] ?? map['market_type'] ?? 'general',
      isCurated: map['is_curated'] ?? false,
    );
  }
}

class MarketplaceService {
  final SupabaseClient _client;
  MarketplaceService(this._client);

  Future<List<MarketProduct>> fetchProducts({String? category, String? marketType, String? tenantId, int offset = 0, int limit = 30}) async {
    var query = _client.from('marketplace_items').select('id, name, price, category, image, description, vendor_name, vendor_id, tenant_id, condition, market_type, is_curated').eq('status', 'active');
    
    if (tenantId != null) {
      query = query.eq('tenant_id', tenantId);
    }
    
    if (category != null && category != 'all') {
      query = query.eq('category', category);
    }
    
    if (marketType != null) {
      query = query.eq('market_type', marketType);
    }

    final data = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
    return (data as List).map((m) => MarketProduct.fromMap(m)).toList();
  }

  Future<void> postProduct(Map<String, dynamic> productData, {String? tenantId}) async {
    await _client.from('marketplace_items').insert({
      ...productData,
      if (tenantId != null) 'tenant_id': tenantId,
      'status': 'active',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Update an existing listing. Only the fields present in `changes` are
  /// written; RLS still scopes the row to its owner/vendor.
  Future<void> updateProduct(String productId, Map<String, dynamic> changes) async {
    await _client
        .from('marketplace_items')
        .update(changes)
        .eq('id', productId);
  }
}

final marketplaceServiceProvider = Provider((ref) => MarketplaceService(Supabase.instance.client));

final productsProvider = FutureProvider.family<List<MarketProduct>, Map<String, String?>>((ref, filters) async {
  final tenant = ref.watch(currentTenantProvider);
  final service = ref.watch(marketplaceServiceProvider);
  final tenantProducts = await service.fetchProducts(
    category: filters['category'],
    marketType: filters['marketType'],
    tenantId: tenant?.id,
  );
  if (tenantProducts.isNotEmpty || tenant == null) return tenantProducts;
  return service.fetchProducts(
    category: filters['category'],
    marketType: filters['marketType'],
  );
});



