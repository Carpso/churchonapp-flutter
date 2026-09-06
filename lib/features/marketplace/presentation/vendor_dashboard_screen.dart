import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:church_on_app/features/marketplace/presentation/post_product_screen.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/features/admin/data/order_service.dart';

final vendorStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null) return {'products': 0, 'active': 0, 'orders': 0, 'revenue': 0.0};

  final products = await Supabase.instance.client
      .from('marketplace_items')
      .select('id, status')
      .eq('vendor_id', userId);

  final productList = (products as List);
  final totalProducts = productList.length;
  final activeListings = productList.where((p) => p['status'] == 'active').length;

  final orderItems = await Supabase.instance.client
      .from('order_items')
      .select('order_id, total_price')
      .eq('vendor_id', userId);

  final itemsList = (orderItems as List);
  final orderIds = itemsList.map((o) => o['order_id'] as String).toSet();
  final totalOrders = orderIds.length;
  final totalRevenue = itemsList.fold<double>(0, (sum, item) => sum + (item['total_price'] as num).toDouble());

  return {
    'products': totalProducts,
    'active': activeListings,
    'orders': totalOrders,
    'revenue': totalRevenue,
  };
});

final vendorProductsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null) return [];
  final data = await Supabase.instance.client
      .from('marketplace_items')
      .select('id, name, price, image, status, created_at, vendor_id')
      .eq('vendor_id', userId)
      .order('created_at', ascending: false);
  return (data as List).cast<Map<String, dynamic>>();
});

final vendorRecentOrdersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null) return [];

  final orderItemsData = await Supabase.instance.client
      .from('order_items')
      .select('order_id, total_price, item_name, item_id, unit_price, quantity')
      .eq('vendor_id', userId);

  if ((orderItemsData as List).isEmpty) return [];

  final orderIds = orderItemsData.map((o) => o['order_id'] as String).toSet().toList();
  if (orderIds.isEmpty) return [];

  final ordersData = await Supabase.instance.client
      .from('orders')
      .select('id, user_id, tenant_id, status, total_amount, delivery_fee, platform_fee, payment_reference, payment_status, shipping_address, contact_phone, notes, created_at')
      .filter('id', 'in', '(${orderIds.join(",")})')
      .order('created_at', ascending: false)
      .limit(10);

  return (ordersData as List).map((o) {
    final order = Order.fromMap(o);
    final items = orderItemsData
        .where((oi) => oi['order_id'] == o['id'])
        .map((oi) => OrderItem.fromMap(oi))
        .toList();
    return {'order': order, 'items': items};
  }).toList();
});

class VendorDashboardScreen extends ConsumerStatefulWidget {
  const VendorDashboardScreen({super.key});

  @override
  ConsumerState<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends ConsumerState<VendorDashboardScreen> {
  Future<void> _deleteProduct(String productId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Product"),
        content: const Text("Are you sure you want to delete this product?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await Supabase.instance.client
          .from('marketplace_items')
          .delete()
          .eq('id', productId);
      ref.invalidate(vendorProductsProvider);
      ref.invalidate(vendorStatsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Product deleted"), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(vendorStatsProvider);
    final productsAsync = ref.watch(vendorProductsProvider);
    final ordersAsync = ref.watch(vendorRecentOrdersProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Vendor Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PostProductScreen()));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(vendorStatsProvider);
          ref.invalidate(vendorProductsProvider);
          ref.invalidate(vendorRecentOrdersProvider);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              statsAsync.when(
                data: (stats) => _buildStatsGrid(stats),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _buildStatsGrid({'products': 0, 'active': 0, 'orders': 0, 'revenue': 0.0}),
              ),
              const SizedBox(height: 30),
              Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 15),
              _buildQuickActions(),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("My Products", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PostProductScreen()));
                    },
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text("Add New"),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              productsAsync.when(
                data: (products) => products.isEmpty
                    ? _buildEmptyProducts()
                    : Column(children: products.map((p) => _buildProductCard(p)).toList()),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const Text("Error loading products"),
              ),
              const SizedBox(height: 30),
              Text("Recent Orders", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 15),
              ordersAsync.when(
                data: (orders) => orders.isEmpty
                    ? _buildEmptyOrders()
                    : Column(children: orders.take(5).map((o) => _buildOrderCard(o)).toList()),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const Text("Error loading orders"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(Map<String, dynamic> stats) {
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard("Total Products", "${stats['products']}", LucideIcons.package, Theme.of(context).primaryColor),
        _buildStatCard("Active Listings", "${stats['active']}", LucideIcons.checkCircle, Colors.green),
        _buildStatCard("Total Orders", "${stats['orders']}", LucideIcons.shoppingCart, Colors.orange),
        _buildStatCard("Total Revenue", "K ${(stats['revenue'] as num).toStringAsFixed(0)}", LucideIcons.coins, Colors.amber),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(child: _buildActionButton(LucideIcons.plus, "Add Product", () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const PostProductScreen()));
        })),
        const SizedBox(width: 10),
        Expanded(child: _buildActionButton(LucideIcons.list, "View Orders", () {
          context.push('/orders');
        })),
        const SizedBox(width: 10),
        // Vendors have no separate shop record — their public shop identity is
        // their profile (name/avatar shown as vendor_name on their listings).
        Expanded(child: _buildActionButton(LucideIcons.store, "Edit Shop", () {
          context.push('/account-settings');
        })),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
        ),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor, size: 24),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final status = product['status'] as String?;
    final statusColor = status == 'active' ? Colors.green : status == 'inactive' ? Colors.grey : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AppImage(
              product['image']?.toString() ?? '',
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              placeholder: Container(
                width: 60,
                height: 60,
                color: Colors.grey.shade200,
                child: const Icon(LucideIcons.image, color: Colors.grey),
              ),
              errorWidget: (_, __) => Container(
                width: 60,
                height: 60,
                color: Colors.grey.shade200,
                child: const Icon(LucideIcons.image, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text("K ${(product['price'] as num?)?.toStringAsFixed(0) ?? '0'}", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              (status ?? 'unknown').toUpperCase(),
              style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(LucideIcons.pencil, size: 16),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PostProductScreen(product: product),
                ),
              );
              ref.invalidate(vendorProductsProvider);
              ref.invalidate(vendorStatsProvider);
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.red),
            onPressed: () => _deleteProduct(product['id'] as String),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> orderData) {
    final order = orderData['order'] as Order;
    final items = orderData['items'] as List<OrderItem>;
    final statusColor = order.status == 'delivered'
        ? Colors.green
        : order.status == 'cancelled'
            ? Colors.red
            : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.shoppingBag, color: statusColor, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Order #${order.id.substring(0, 8).toUpperCase()}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  "${items.length} item(s) \u00b7 K ${order.totalAmount.toStringAsFixed(0)}",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              order.status.toUpperCase(),
              style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyProducts() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.package, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 15),
          const Text("No products yet", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 5),
          const Text("Tap 'Add Product' to get started", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildEmptyOrders() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.shoppingBag, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 15),
          const Text("No orders yet", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 5),
          const Text("Orders will appear here when customers buy", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}
