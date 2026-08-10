import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'package:church_on_app/features/admin/data/role_hierarchy_service.dart';
import '../../marketplace/presentation/post_product_screen.dart';

class BookshopDashboardScreen extends ConsumerStatefulWidget {
  const BookshopDashboardScreen({super.key});

  @override
  ConsumerState<BookshopDashboardScreen> createState() => _BookshopDashboardScreenState();
}

class _BookshopDashboardScreenState extends ConsumerState<BookshopDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  int _totalProducts = 0;
  int _lowStockCount = 0;
  int _totalSales = 0;
  double _monthRevenue = 0;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _recentOrders = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    final tenantId = ref.read(profileProvider).value?.tenantId;
    if (tenantId == null) { setState(() { _isLoading = false; _error = "No shop assigned"; }); return; }

    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);

    try {
      final productsRes = await Supabase.instance.client
          .from('marketplace_products')
          .select('id, title, price, stock, sale_count, status, created_at')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false);

      final products = List<Map<String, dynamic>>.from(productsRes);
      int lowStock = 0, sales = 0;
      for (final p in products) {
        final stock = (p['stock'] as num?)?.toInt() ?? 0;
        if (stock < 10) lowStock++;
        sales += (p['sale_count'] as num?)?.toInt() ?? 0;
      }

      final ordersRes = await Supabase.instance.client
          .from('marketplace_orders')
          .select('id, total_amount, status, created_at')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false)
          .limit(20);

      double monthRev = 0;
      for (final o in ordersRes) {
        final amount = (o['total_amount'] as num?)?.toDouble() ?? 0;
        final created = o['created_at']?.toString() ?? '';
        final dt = DateTime.tryParse(created);
        if (dt != null && dt.isAfter(firstOfMonth)) monthRev += amount;
      }

      if (mounted) {
        setState(() {
          _totalProducts = products.length;
          _lowStockCount = lowStock;
          _totalSales = sales;
          _monthRevenue = monthRev;
          _products = products;
          _recentOrders = List<Map<String, dynamic>>.from(ordersRes);
          _isLoading = false; _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  Future<void> _addStaffMember() async {
    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController(text: 'assistant');
    String staffRole = 'assistant';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("Add Shop Staff"),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "User ID (UUID)", hintText: "Paste the user's ID")),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: staffRole,
                items: ['store_manager', 'assistant', 'cashier'].map((r) => DropdownMenuItem(value: r, child: Text(r.replaceAll('_', ' ')))).toList(),
                onChanged: (v) {
                  setDialogState(() => staffRole = v ?? 'assistant');
                  roleCtrl.text = v ?? 'assistant';
                },
                decoration: const InputDecoration(labelText: "Staff Role", hintText: "Select role"),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, {'userId': nameCtrl.text.trim(), 'role': staffRole}), child: const Text("Add Staff")),
          ],
        ),
      ),
    );

    if (result != null) {
      final uid = result['userId'];
      final role = result['role'];
      if (uid != null && uid.isNotEmpty && role != null && role.isNotEmpty) {
        final svc = ref.read(roleHierarchyServiceProvider);
        try {
          await svc.elevateRole(userId: uid, roleName: role);
          if (mounted) {
            showAppSnackBar(
              context,
              "$role added to shop!",
              status: AppStatus.success,
            );
          }
          _loadDashboard();
        } catch (e) {
          if (mounted) {
            showAppSnackBar(
              context,
              AppErrorView.friendlyMessage(e),
              status: AppStatus.error,
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Bookshop Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PostProductScreen(initialCategory: "bookshop")),
            ).then((_) => _loadDashboard()),
          ),
          IconButton(icon: const Icon(LucideIcons.users), onPressed: _addStaffMember, tooltip: "Add Staff"),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _isLoading ? null : _loadDashboard,
          ),
        ],
      ),
      body: _isLoading
          ? _buildShimmer()
          : _error != null
              ? _buildErrorView()
              : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildHeader(theme),
                  const SizedBox(height: 25), _buildStatsGrid(theme),
                  const SizedBox(height: 30),
                  Text("Inventory", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 15),
                  ..._products.isNotEmpty ? _products.take(10).map((p) => _productTile(theme, p)) : [_emptyCard(theme, "No products yet. Tap + to add one.")],
                  const SizedBox(height: 30),
                  Text("Recent Orders", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 15),
                  ..._recentOrders.isNotEmpty ? _recentOrders.take(5).map((o) => _orderRow(theme, o)) : [_emptyCard(theme, "No orders yet")],
                ]),
              ),
            ),
    );
  }

  Widget _buildShimmer() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(children: [
      ShimmerLoader.rectangular(height: 120, width: double.infinity),
      const SizedBox(height: 20), Row(children: [Expanded(child: ShimmerLoader.rectangular(height: 90)), const SizedBox(width: 12), Expanded(child: ShimmerLoader.rectangular(height: 90))]),
      const SizedBox(height: 25), ShimmerLoader.rectangular(height: 18, width: 100),
      const SizedBox(height: 15), ...List.generate(3, (_) => Padding(padding: const EdgeInsets.only(bottom: 10), child: ShimmerLoader.rectangular(height: 65))),
    ]),
  );

  Widget _buildErrorView() => AppErrorView(error: _error, onRetry: _loadDashboard);

  Widget _buildHeader(ThemeData theme) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.orange.shade800, Colors.orange.shade500], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.orange.shade200.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
          child: const Icon(LucideIcons.bookOpen, color: Colors.white, size: 28)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Bookshop Management", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
          Text("$_totalProducts products • ${currency.format(_monthRevenue)} MTD", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
        ])),
      ]),
    );
  }

  Widget _buildStatsGrid(ThemeData theme) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.2,
      children: [
        _statCard("Products", "$_totalProducts", LucideIcons.package, Colors.orange),
        _statCard("Total Sales", "$_totalSales", LucideIcons.shoppingCart, Colors.green),
        _statCard("Low Stock", "$_lowStockCount", LucideIcons.alertTriangle, Colors.amber),
        _statCard("Revenue (MTD)", currency.format(_monthRevenue), LucideIcons.trendingUp, Colors.blue),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _productTile(ThemeData theme, Map<String, dynamic> product) {
    final title = product['title'] as String? ?? 'Untitled';
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final stock = (product['stock'] as num?)?.toInt() ?? 0;
    final status = stock == 0 ? 'Out of Stock' : stock < 10 ? 'Low Stock' : 'In Stock';
    final statusColor = stock == 0 ? Colors.red : stock < 10 ? Colors.orange : Colors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.book, color: Colors.orange, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(
                  "K ${NumberFormat.decimalPattern().format(price)} • Stock: $stock",
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderRow(ThemeData theme, Map<String, dynamic> order) {
    final amount = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final status = order['status'] as String? ?? 'pending';
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.shoppingBag,
            size: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              currency.format(amount),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Text(
            status,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(ThemeData theme, String msg) => Container(
    width: double.infinity, padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Center(child: Text(msg, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4)))),
  );
}
