import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      condition: map['condition'],
      marketType: map['marketType'] ?? map['market_type'] ?? 'general',
      isCurated: map['is_curated'] ?? false,
    );
  }
}

class MarketplaceService {
  final SupabaseClient _client;
  MarketplaceService(this._client);

  Future<List<MarketProduct>> fetchProducts({String? category, String? marketType}) async {
    var query = _client.from('marketplace_items').select('*').eq('status', 'active');
    
    if (category != null && category != 'all') {
      query = query.eq('category', category);
    }
    
    if (marketType != null) {
      query = query.eq('market_type', marketType);
    }

    final data = await query.order('created_at', ascending: false);
    return (data as List).map((m) => MarketProduct.fromMap(m)).toList();
  }

  Future<void> postProduct(Map<String, dynamic> productData) async {
    await _client.from('marketplace_items').insert({
      ...productData,
      'status': 'active',
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

final marketplaceServiceProvider = Provider((ref) => MarketplaceService(Supabase.instance.client));

final productsProvider = FutureProvider.family<List<MarketProduct>, Map<String, String?>>((ref, filters) async {
  return ref.watch(marketplaceServiceProvider).fetchProducts(
    category: filters['category'],
    marketType: filters['marketType'],
  );
});



