import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../data/marketplace_service.dart';
import 'product_details_screen.dart';
import 'post_product_screen.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/features/navigation/presentation/carpso_suggestion_card.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class MarketplaceScreen extends ConsumerStatefulWidget {
  final String? initialCategory;
  const MarketplaceScreen({super.key, this.initialCategory});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  late String _selectedCategory;
  String _activeTab = "shop";
  List<MarketProduct> _products = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 30;

  bool _showCarpsoCard() {
    final day = DateTime.now().weekday;
    return day == DateTime.sunday || day == DateTime.wednesday || day == DateTime.friday;
  }

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? "all";
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final service = ref.read(marketplaceServiceProvider);
    final tenant = ref.read(currentTenantProvider);
    final batch = await service.fetchProducts(
      category: _selectedCategory,
      marketType: _tabs.firstWhere((t) => t['id'] == _activeTab)['marketType'] as String?,
      tenantId: tenant?.id,
      offset: 0,
      limit: _limit,
    );
    if (mounted) {
      setState(() {
        _products = batch;
        _hasMore = batch.length >= _limit;
      });
    }
  }

  void _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final service = ref.read(marketplaceServiceProvider);
      final tenant = ref.read(currentTenantProvider);
      final more = await service.fetchProducts(
        category: _selectedCategory,
        marketType: _tabs.firstWhere((t) => t['id'] == _activeTab)['marketType'] as String?,
        tenantId: tenant?.id,
        offset: _offset + _limit,
        limit: _limit,
      );
      if (mounted) {
        setState(() {
          _offset += _limit;
          _products = [..._products, ...more];
          _hasMore = more.length >= _limit;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  final List<Map<String, dynamic>> _tabs = [
    {'id': 'shop', 'label': 'Buy On App', 'marketType': 'general'},
    {'id': 'tuesday', 'label': 'Tue Market', 'marketType': 'tuesday'},
    {'id': 'saturday', 'label': 'Sat Market', 'marketType': 'saturday'},
    {'id': 'services', 'label': 'Services', 'marketType': null},
  ];

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Marketplace", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.shoppingBag),
                onPressed: () => context.push('/cart'),
              ),
              if (cartItems.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text(
                      cartItems.length.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabRibbon(),
          _buildCategoryRibbon(),
          if (_showCarpsoCard())
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SizedBox(
                height: 48,
                child: CarpsoSuggestionCard(contextType: 'marketplace'),
              ),
            ),
          Expanded(
            child: _products.isEmpty && !_isLoadingMore
                ? _buildEmptyState()
                : RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _products = [];
                      _offset = 0;
                      _hasMore = true;
                    });
                    await _loadProducts();
                  },
                  child: MasonryGridView.count(
                    padding: const EdgeInsets.all(20),
                    crossAxisCount: 2,
                    mainAxisSpacing: 15,
                    crossAxisSpacing: 15,
                    itemCount: _products.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _products.length) {
                        return _isLoadingMore
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : GestureDetector(
                                onTap: _loadMore,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Center(
                                    child: Text("Load More", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              );
                      }
                      return _buildMarketItem(_products[index]);
                    },
                  ),
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context, 
            MaterialPageRoute(
              builder: (context) => PostProductScreen(initialCategory: _selectedCategory == 'bookshop' ? 'bookshop' : null),
            ),
          );
        },
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(LucideIcons.plus, color: Colors.white),
        label: Text(_selectedCategory == 'bookshop' ? "Sell a Book" : "List Item", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildTabRibbon() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final isSelected = _activeTab == _tabs[index]['id'];
          return GestureDetector(
            onTap: () {
              setState(() => _activeTab = _tabs[index]['id']!);
              _offset = 0;
              _hasMore = true;
              _loadProducts();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Text(
                  _tabs[index]['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryRibbon() {
    final categories = ["all", "bookshop", "apparel", "worship", "tickets", "media"];
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedCategory == categories[index];
          return GestureDetector(
            onTap: () {
              setState(() => _selectedCategory = categories[index]);
              _offset = 0;
              _hasMore = true;
              _loadProducts();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).primaryColor : Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  categories[index].toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? Theme.of(context).colorScheme.secondary : Colors.grey,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMarketItem(MarketProduct product) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => ProductDetailsScreen(product: product)));
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: AppImage(
                    product.image ?? '',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              if (product.isCurated)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(8)),
                    child: const Row(
                      children: [
                        Icon(LucideIcons.shieldCheck, color: Colors.white, size: 10),
                        SizedBox(width: 4),
                        Text("VERIFIED", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(product.vendorName ?? "Verified Vendor", style: const TextStyle(color: Colors.grey, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("K ${product.price.toInt()}", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w900, fontSize: 14)),
                    GestureDetector(
                      onTap: () {
                        ref.read(cartProvider.notifier).addToCart(product);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Added to cart!"), duration: Duration(seconds: 1)),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                        child: Icon(LucideIcons.plus, size: 16, color: Theme.of(context).colorScheme.secondary),
                      ),
                    )
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.shoppingBag, size: 64, color: Colors.grey),
          const SizedBox(height: 20),
          const Text("No items found", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 8),
          Text("Try changing categories or tabs", style: TextStyle(color: Colors.grey.withValues(alpha: 0.6), fontSize: 12)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() { _selectedCategory = "all"; _activeTab = "shop"; });
              _offset = 0;
              _hasMore = true;
              _loadProducts();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Theme.of(context).colorScheme.secondary,
              minimumSize: const Size(180, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text("Browse All Items", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

