import 'package:flutter/foundation.dart';
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
  final String? tenantId;
  final String? condition;
  final String marketType;
  final bool isCurated;
  final int stock;
  final String? downloadUrl;

  /// Optional book metadata (set when the listing is a BOOK). `downloadUrl`
  /// present + category 'book' means a digital/eBook; otherwise a physical book.
  final String? isbn;
  final String? author;
  final int? pages;

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
    this.stock = 0,
    this.downloadUrl,
    this.isbn,
    this.author,
    this.pages,
  });

  /// A book listing sold as a digital/eBook (has a download URL).
  bool get isDigitalBook =>
      category == 'book' && (downloadUrl?.isNotEmpty ?? false);

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
      stock: (map['stock'] as num?)?.toInt() ?? 0,
      downloadUrl: map['download_url']?.toString(),
      isbn: map['isbn']?.toString(),
      author: map['author']?.toString(),
      pages: (map['pages'] as num?)?.toInt(),
    );
  }
}

class MarketplaceService {
  final SupabaseClient _client;
  MarketplaceService(this._client);

  /// [includeCrossListedBookshops] should be true only for a CHURCH tenant:
  /// the church marketplace then also shows catalogue items from bookshops
  /// whose owner enabled `show_in_marketplace`. A bookshop storefront keeps
  /// `false` so it stays scoped to its own products. RLS enforces the same
  /// visibility server-side, so this can never widen beyond opted-in shops.
  Future<List<MarketProduct>> fetchProducts({
    String? category,
    String? marketType,
    String? tenantId,
    bool includeCrossListedBookshops = false,
    int offset = 0,
    int limit = 30,
  }) async {
    var query = _client.from('marketplace_items').select('id, name, price, category, image, description, vendor_name, vendor_id, tenant_id, condition, market_type, is_curated, stock, download_url, isbn, author, pages').eq('status', 'active');

    if (tenantId != null && tenantId.isNotEmpty) {
      List<String> crossListed = const [];
      if (includeCrossListedBookshops) {
        try {
          final res = await _client.rpc('get_marketplace_bookshop_tenants');
          crossListed = (res as List)
              .map((e) => (e is Map ? e['tenant_id'] : e)?.toString())
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toList();
        } catch (e) {
          debugPrint('Cross-listed bookshops lookup failed: $e');
        }
      }
      if (crossListed.isEmpty) {
        query = query.eq('tenant_id', tenantId);
      } else {
        query = query.or(
          'tenant_id.eq.$tenantId,tenant_id.in.(${crossListed.join(",")})',
        );
      }
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
    final user = _client.auth.currentUser;
    await _client.from('marketplace_items').insert({
      ...productData,
      if (tenantId != null) 'tenant_id': tenantId,
      'status': 'active',
      'created_at': DateTime.now().toIso8601String(),
    });

    // Notify church members of new listing (fire-and-forget)
    if (tenantId != null && tenantId.isNotEmpty && user != null) {
      try {
        final name = productData['name']?.toString() ?? 'New item';
        _client
            .from('profiles')
            .select('id')
            .eq('tenant_id', tenantId)
            .neq('id', user.id)
            .limit(200)
            .then((members) {
          for (final m in (members as List)) {
            final uid = m['id']?.toString();
            if (uid == null) continue;
            try {
              _client.functions.invoke('push-notifications', body: {
                'userId': uid,
                'title': 'New Listing',
                'body': 'New item "$name" posted in the marketplace.',
                'type': 'marketplace',
              });
            } catch (_) {}
          }
        });
      } catch (_) {}
    }
  }

  /// Update an existing listing. Only the fields present in `changes` are
  /// written; RLS still scopes the row to its owner/vendor. Returns false when
  /// no row was written (owner/RLS mismatch) so callers can surface an error
  /// instead of reporting a silent success.
  Future<bool> updateProduct(String productId, Map<String, dynamic> changes) async {
    final rows = await _client
        .from('marketplace_items')
        .update(changes)
        .eq('id', productId)
        .select('id');
    return (rows as List).isNotEmpty;
  }

  /// Delete a listing the caller owns. Returns false when nothing was deleted.
  Future<bool> deleteProduct(String productId) async {
    final rows = await _client
        .from('marketplace_items')
        .delete()
        .eq('id', productId)
        .select('id');
    return (rows as List).isNotEmpty;
  }
}

final marketplaceServiceProvider = Provider((ref) => MarketplaceService(Supabase.instance.client));

/// Filter key for [productsProvider].
///
/// IMPORTANT: this is a Dart record, NOT a Map. A `Map` argument has no value
/// equality, so `{'category': 'all'} != {'category': 'all'}` — Riverpod would
/// treat every rebuild as a NEW family instance, start it in `loading`, resolve,
/// rebuild again… an endless fetch/reload loop that made the home Marketplace
/// section (and its siblings) flash and vanish. Records compare structurally.
typedef ProductFilter = ({String? category, String? marketType});

final productsProvider = FutureProvider.family<List<MarketProduct>, ProductFilter>((ref, filters) async {
  final service = ref.watch(marketplaceServiceProvider);
  // Marketplace is global — all active items visible to all users.
  return service.fetchProducts(
    category: filters.category,
    marketType: filters.marketType,
  );
});



