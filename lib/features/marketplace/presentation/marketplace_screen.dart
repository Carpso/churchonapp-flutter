import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
// Theme via context
import '../data/marketplace_service.dart';
import 'product_details_screen.dart';

class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  String _selectedCategory = "all";
  String _activeTab = "shop";

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
                onPressed: () => _showCartSheet(),
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
                return MasonryGridView.count(
                  padding: const EdgeInsets.all(20),
                  crossAxisCount: 2,
                  mainAxisSpacing: 15,
                  crossAxisSpacing: 15,
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    return _buildMarketItem(products[index]);
                  },
                );
              },
              loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),
              error: (err, stack) => _buildMockGrid(), // Fallback for prototype
            ),
          ),
        ],
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
                border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2)),
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
    final categories = ["all", "books", "merch", "music", "tickets", "media"];
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
                color: isSelected ? Theme.of(context).primaryColor : Colors.white.withOpacity(0.5),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
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
                    Text("${product.price.toInt()} CC", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w900, fontSize: 14)),
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
          Text("Try changing categories or tabs", style: TextStyle(color: Colors.grey.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildMockGrid() {
    final mockProducts = [
      MarketProduct(id: '1', name: "Study Bible", price: 150, category: "books", isCurated: true),
      MarketProduct(id: '2', name: "Faith T-Shirt", price: 85, category: "merch"),
      MarketProduct(id: '3', name: "Worship CD", price: 45, category: "music"),
      MarketProduct(id: '4', name: "Conference Ticket", price: 200, category: "tickets"),
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

  void _showCartSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const CartSheet(),
    );
  }
}

class CartSheet extends ConsumerWidget {
  const CartSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final total = ref.read(cartProvider.notifier).total;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Your Cart", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text("${items.length} Items", style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const Divider(height: 30),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text("Cart is empty", style: TextStyle(color: Colors.grey)),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.package, color: Theme.of(context).primaryColor),
                  title: Text(items[index].product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${items[index].quantity} x ${items[index].product.price} CC"),
                  trailing: IconButton(
                    icon: const Icon(LucideIcons.trash2, size: 18, color: Colors.grey),
                    onPressed: () => ref.read(cartProvider.notifier).removeFromCart(items[index].product.id),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text("${total.toInt()} CC", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).primaryColor)),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: items.isEmpty ? null : () {
              Navigator.pop(context);
              _showCheckoutSuccess(context);
              ref.read(cartProvider.notifier).clear();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text("PROCEED TO CHECKOUT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCheckoutSuccess(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.checkCircle, color: Colors.green, size: 60),
            SizedBox(height: 20),
            Text("Order Placed!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text("Your purchase was successful. View your items in 'My Library'.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("DONE")),
        ],
      ),
    );
  }
}
