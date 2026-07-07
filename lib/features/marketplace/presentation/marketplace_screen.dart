import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../data/marketplace_service.dart';
import 'product_details_screen.dart';
import 'post_product_screen.dart';
import '../../../core/widgets/shimmer_loader.dart';

class MarketplaceScreen extends ConsumerStatefulWidget {
  final String? initialCategory;
  const MarketplaceScreen({super.key, this.initialCategory});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  late String _selectedCategory;
  String _activeTab = "shop";

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? "all";
  }

  final List<Map<String, dynamic>> _tabs = [
    {'id': 'shop', 'label': 'Buy On App', 'marketType': 'general'},
    {'id': 'tuesday', 'label': 'Tue Market', 'marketType': 'tuesday'},
    {'id': 'saturday', 'label': 'Sat Market', 'marketType': 'saturday'},
    {'id': 'services', 'label': 'Services', 'marketType': null},
  ];

  @override
  Widget build(BuildContext context) {
    final filters = {
      'category': _selectedCategory,
      'marketType': _tabs.firstWhere((t) => t['id'] == _activeTab)['marketType'] as String?,
    };
    final productsAsync = ref.watch(productsProvider(filters));
    final cartItems = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Marketplace", style: TextStyle(fontWeight: FontWeight.bold)),
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
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return _buildEmptyState();
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(productsProvider(filters));
                  },
                  child: MasonryGridView.count(
                    padding: const EdgeInsets.all(20),
                    crossAxisCount: 2,
                    mainAxisSpacing: 15,
                    crossAxisSpacing: 15,
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                    return _buildMarketItem(products[index]);
                  },
                ),
                );
              },
              loading: () => const ListSkeleton(),
              error: (err, stack) => RefreshIndicator(
                onRefresh: () async {
                  setState(() {});
                  await Future.delayed(const Duration(seconds: 1));
                },
                child: _buildMockGrid(),
              ), // Fallback for prototype
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
            onTap: () => setState(() => _activeTab = _tabs[index]['id']!),
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
            onTap: () => setState(() => _selectedCategory = categories[index]),
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                child: Image.network(
                  product.image ?? "https://images.unsplash.com/photo-1543165796-5426273ea430?w=400&q=60",
                  fit: BoxFit.cover,
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
                Text(product.vendorName ?? "Verified Vendor", style: const TextStyle(color: Colors.grey, fontSize: 10)),
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
          const Icon(LucideIcons.shoppingBag, size: 50, color: Colors.grey),
          const SizedBox(height: 20),
          const Text("No items found", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          Text("Try changing categories or tabs", style: TextStyle(color: Colors.grey.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildMockGrid() {
    final mockProducts = [
      // Books & Bibles
      MarketProduct(id: '1', name: "Dake Annotated Reference Bible", price: 450, category: "bookshop", isCurated: true, vendorName: "Kingdom Bookshop"),
      MarketProduct(id: '5', name: "Purpose Driven Life Book", price: 200, category: "bookshop", vendorName: "Kingdom Bookshop"),
      MarketProduct(id: '7', name: "NKJV Study Bible, Leather Bound", price: 350, category: "bookshop", vendorName: "Bible Society"),
      MarketProduct(id: '8', name: "Morning & Evening by Spurgeon", price: 120, category: "bookshop", vendorName: "Grace Publishers"),
      MarketProduct(id: '9', name: "My Bible Storybook for Kids", price: 90, category: "bookshop", vendorName: "Kingdom Kids"),
      
      // Apparel & Fashion
      MarketProduct(id: '2', name: "Faith Over Fear Hoodie", price: 250, category: "apparel", vendorName: "Ziba Fashion"),
      MarketProduct(id: '10', name: "Yahweh Embroidered Cap", price: 80, category: "apparel", vendorName: "Ziba Fashion"),
      MarketProduct(id: '11', name: "Proverbs 31 Woman T-Shirt", price: 120, category: "apparel", vendorName: "Daughters of Zion"),
      MarketProduct(id: '12', name: "Jesus Saves Denom Jacket", price: 450, category: "apparel", vendorName: "Street Preachers Apparel"),
      MarketProduct(id: '13', name: "Armor of God Youth T-Shirt", price: 65, category: "apparel", vendorName: "Kingdom Kids"),

      // Spiritual Tools & Elements
      MarketProduct(id: '6', name: "Anointing Oil (Frankincense & Myrrh)", price: 65, category: "merch", vendorName: "Church Store"),
      MarketProduct(id: '14', name: "Communion Wafer & Juice Set (100pk)", price: 300, category: "merch", vendorName: "Church Supply Co."),
      MarketProduct(id: '15', name: "Olive Wood Prayer Cross", price: 45, category: "merch", vendorName: "Holy Land Crafts"),
      MarketProduct(id: '16', name: "Shofar Ram's Horn", price: 800, category: "merch", vendorName: "Prophetic Instruments"),
      MarketProduct(id: '17', name: "Clergy Collar & Shirt Set", price: 400, category: "merch", vendorName: "Clerical Wear Intl."),

      // Gifts & Stationary (Pens, Journals, etc)
      MarketProduct(id: '18', name: "Philippians 4:13 Engraved Metal Pen", price: 45, category: "merch", vendorName: "Kingdom Stationers"),
      MarketProduct(id: '19', name: "Leather Prayer Journal", price: 110, category: "bookshop", vendorName: "Kingdom Stationers"),
      MarketProduct(id: '20', name: "Scripture Coffee Mug", price: 75, category: "merch", vendorName: "Daily Bread Mugs"),
      MarketProduct(id: '21', name: "Faith Mustard Seed Keychain", price: 35, category: "merch", vendorName: "Gift Corner"),
      MarketProduct(id: '22', name: "Bible Verse Bookmarks (Set of 10)", price: 25, category: "merch", vendorName: "Kingdom Stationers"),
      MarketProduct(id: '23', name: "Christian Refrigerator Magnets", price: 30, category: "merch", vendorName: "Gift Corner"),

      // Worship & Media
      MarketProduct(id: '3', name: "Oceans (Live Worship Anthems)", price: 85, category: "worship", vendorName: "Kingdom Radio"),
      MarketProduct(id: '24', name: "Instrumental Prayer Music Vol 1", price: 60, category: "worship", vendorName: "Kingdom Radio"),
      MarketProduct(id: '25', name: "Sermon Series: Book of Romans (Audio)", price: 150, category: "media", vendorName: "Church Media"),

      // Events & Tickets
      MarketProduct(id: '4', name: "Men of Valor Conference Ticket", price: 150, category: "tickets", isCurated: true, vendorName: "Admin Hub"),
      MarketProduct(id: '26', name: "Women's Retreat 2026 Registration", price: 500, category: "tickets", isCurated: true, vendorName: "Admin Hub"),
      MarketProduct(id: '27', name: "Youth Summer Camp Early Bird", price: 350, category: "tickets", vendorName: "Youth Ministry"),
    ];
    return MasonryGridView.count(
      padding: const EdgeInsets.all(20),
      crossAxisCount: 2,
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      itemCount: mockProducts.length,
      itemBuilder: (context, index) => _buildMarketItem(mockProducts[index]),
    );
  }

}

