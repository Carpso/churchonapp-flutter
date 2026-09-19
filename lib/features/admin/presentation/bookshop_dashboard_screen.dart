import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'package:church_on_app/features/admin/data/role_hierarchy_service.dart';
import 'package:church_on_app/features/bookshop/data/bookshop_service.dart';
import 'package:church_on_app/features/bookshop/presentation/user_picker_sheet.dart';
import 'package:church_on_app/features/auth/presentation/select_church_screen.dart'
    show SelectTenantScreen;
import '../../marketplace/presentation/post_product_screen.dart';

class BookshopDashboardScreen extends ConsumerStatefulWidget {
  const BookshopDashboardScreen({super.key});

  @override
  ConsumerState<BookshopDashboardScreen> createState() => _BookshopDashboardScreenState();
}

class _BookshopDashboardScreenState extends ConsumerState<BookshopDashboardScreen> {
  static const int _lowStockThreshold = 10;

  static const Map<String, List<String>> _transitions = {
    'pending': ['confirmed', 'cancelled'],
    'confirmed': ['processing', 'cancelled'],
    'processing': ['shipped', 'cancelled'],
    'shipped': ['delivered'],
    'delivered': ['refunded'],
    'cancelled': [],
    'refunded': [],
  };

  final _searchC = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _lowStockOnly = false;

  bool _isLoading = true;
  String? _error;
  String? _tenantId;
  int _totalProducts = 0;
  double _inventoryValue = 0;
  bool _showInMarketplace = false;
  DateTimeRange _range = _initialRange();
  Map<String, dynamic> _summary = const {};

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _customers = [];
  List<BookshopUser> _staff = [];

  static DateTimeRange _initialRange() {
    final now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
  }

  BookshopService get _service => BookshopService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    ref.listen(profileProvider, (prev, next) {
      if (next.hasValue && next.value != null) _loadDashboard();
      if (next.hasError) {
        setState(() {
          _isLoading = false;
          _error = next.error.toString();
        });
      }
    });
    _loadDashboard();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchC.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim().toLowerCase());
    });
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    final profile = ref.read(profileProvider).value;
    if (profile == null) {
      setState(() => _isLoading = false);
      return;
    }
    final tenantId = profile.tenantId;
    if (tenantId == null) {
      setState(() {
        _isLoading = false;
        _error = "No shop assigned";
      });
      return;
    }
    _tenantId = tenantId;

    try {
      final productsRes = await Supabase.instance.client
          .from('marketplace_items')
          .select('id, name, price, stock, status, created_at')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false);

      final products = List<Map<String, dynamic>>.from(productsRes);
      double inventoryValue = 0;
      for (final p in products) {
        final stock = (p['stock'] as num?)?.toInt() ?? 0;
        final price = (p['price'] as num?)?.toDouble() ?? 0;
        inventoryValue += price * stock;
      }

      final service = _service;
      final results = await Future.wait([
        service.fetchOrders(tenantId: tenantId),
        service.fetchStaff(tenantId),
        service.fetchShowInMarketplace(tenantId),
        service.salesSummary(
          tenantId: tenantId,
          from: _range.start,
          to: _range.end.add(const Duration(days: 1)),
        ),
        service.fetchCustomers(tenantId),
      ]);

      final orders = results[0] as List<Map<String, dynamic>>;
      final staff = results[1] as List<BookshopUser>;
      final showInMarketplace = results[2] as bool;
      final summary = results[3] as Map<String, dynamic>;
      final customers = results[4] as List<Map<String, dynamic>>;

      if (mounted) {
        setState(() {
          _totalProducts = products.length;
          _inventoryValue = inventoryValue;
          _products = products;
          _orders = orders;
          _staff = staff;
          _customers = customers;
          _showInMarketplace = showInMarketplace;
          _summary = summary;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  Future<void> _reloadSummary() async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    try {
      final summary = await _service.salesSummary(
        tenantId: tenantId,
        from: _range.start,
        to: _range.end.add(const Duration(days: 1)),
      );
      if (mounted) setState(() => _summary = summary);
    } catch (e) {
      debugPrint('sales summary failed: $e');
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked != null && mounted) {
      setState(() => _range = picked);
      await _reloadSummary();
    }
  }

  Future<void> _addStaffMember() async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    final me = ref.read(profileProvider).value;
    final isPlatform = me?.role == 'superadmin' ||
        me?.role == 'coa_employee' ||
        me?.role == 'employee';

    List<BookshopUser> candidates;
    try {
      candidates = await _service.fetchCandidates(
        tenantId: tenantId,
        isPlatformStaff: isPlatform,
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Could not load users: ${AppErrorView.friendlyMessage(e)}',
            status: AppStatus.error);
      }
      return;
    }
    if (!mounted) return;

    final picked = await showBookshopUserPicker(context, candidates: candidates);
    if (picked == null || !mounted) return;

    String? role;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Role for ${picked.displayName}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: DropdownButtonFormField<String>(
            initialValue: role,
            items: BookshopService.staffRoles
                .map((r) => DropdownMenuItem(
                    value: r, child: Text(r.replaceAll('_', ' '))))
                .toList(),
            onChanged: (v) => setDlg(() => role = v),
            decoration: const InputDecoration(labelText: 'Staff Role'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: role == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Add Staff'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || role == null || !mounted) return;

    try {
      await ref.read(roleHierarchyServiceProvider).elevateRole(
            userId: picked.id,
            roleName: role!,
            tenantId: tenantId,
          );
      if (mounted) {
        showAppSnackBar(context, '${picked.displayName} is now ${role!.replaceAll('_', ' ')}',
            status: AppStatus.success);
      }
      _loadDashboard();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, AppErrorView.friendlyMessage(e), status: AppStatus.error);
      }
    }
  }

  Future<void> _setOrderStatus(String orderId, String status) async {
    try {
      await _service.setOrderStatus(orderId, status);
      if (mounted) {
        showAppSnackBar(context, 'Order marked ${status.toUpperCase()}',
            status: AppStatus.success);
      }
      _loadDashboard();
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, AppErrorView.friendlyMessage(e), status: AppStatus.error);
      }
    }
  }

  Future<void> _toggleMarketplace(bool value) async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    setState(() => _showInMarketplace = value);
    try {
      await _service.setShowInMarketplace(tenantId, value);
      if (mounted) {
        showAppSnackBar(
          context,
          value
              ? 'Your catalogue is now listed for churches'
              : 'Your catalogue is hidden from churches',
          status: AppStatus.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _showInMarketplace = !value);
        showAppSnackBar(context, AppErrorView.friendlyMessage(e), status: AppStatus.error);
      }
    }
  }

  Future<void> _exportOrders() async {
    final orders = _filteredOrders;
    if (orders.isEmpty) {
      showAppSnackBar(context, 'No orders to export', status: AppStatus.info);
      return;
    }
    try {
      final csv = _service.ordersToCsv(orders);
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final file = XFile.fromData(
        Uint8List.fromList(const Utf8Encoder().convert(csv)),
        mimeType: 'text/csv',
        name: 'bookshop_orders_$stamp.csv',
      );
      await SharePlus.instance.share(ShareParams(
        files: [file],
        text: 'Bookshop orders export',
      ));
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Export failed: ${AppErrorView.friendlyMessage(e)}',
            status: AppStatus.error);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredProducts {
    return _products.where((p) {
      final stock = (p['stock'] as num?)?.toInt() ?? 0;
      if (_lowStockOnly && stock >= _lowStockThreshold) return false;
      if (_query.isEmpty) return true;
      return (p['name'] ?? '').toString().toLowerCase().contains(_query);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredOrders {
    return _orders.where((o) {
      if (_query.isEmpty) return true;
      return (o['id'] ?? '').toString().toLowerCase().contains(_query) ||
          (o['shipping_address'] ?? '').toString().toLowerCase().contains(_query) ||
          (o['contact_phone'] ?? '').toString().toLowerCase().contains(_query) ||
          (o['notes'] ?? '').toString().toLowerCase().contains(_query);
    }).toList();
  }

  List<BookshopUser> get _filteredStaff =>
      _staff.where((s) => s.matches(_query)).toList();

  List<Map<String, dynamic>> get _filteredCustomers {
    return _customers.where((c) {
      if (_query.isEmpty) return true;
      return (c['full_name'] ?? '').toString().toLowerCase().contains(_query) ||
          (c['email'] ?? '').toString().toLowerCase().contains(_query);
    }).toList();
  }

  int get _lowStockCount => _products
      .where((p) => ((p['stock'] as num?)?.toInt() ?? 0) < _lowStockThreshold)
      .length;

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
            tooltip: "Add product",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PostProductScreen(initialCategory: "bookshop")),
            ).then((_) => _loadDashboard()),
          ),
          IconButton(
            icon: const Icon(LucideIcons.fileDown),
            tooltip: "Export orders (CSV)",
            onPressed: _isLoading ? null : _exportOrders,
          ),
          IconButton(
              icon: const Icon(LucideIcons.users), onPressed: _addStaffMember, tooltip: "Add Staff"),
          IconButton(
            icon: const Icon(LucideIcons.arrowLeftRight),
            tooltip: "Switch church / bookshop",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SelectTenantScreen()),
            ),
          ),
          IconButton(
             icon: const Icon(LucideIcons.settings2),
             tooltip: "Shop settings",
             onPressed: () => context.push('/account-settings'),
          ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _isLoading ? null : _loadDashboard,
          ),
        ],
      ),
      body: _isLoading
          ? _buildShimmer()
          : _error != null
              ? AppErrorView(error: _error, onRetry: _loadDashboard)
              : RefreshIndicator(
                  onRefresh: _loadDashboard,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _buildHeader(theme),
                      const SizedBox(height: 20),
                      _buildRangeBar(theme),
                      const SizedBox(height: 20),
                      _buildStatsGrid(theme),
                      const SizedBox(height: 20),
                      _buildMarketplaceToggle(theme),
                      const SizedBox(height: 20),
                      _buildSearchField(),
                      const SizedBox(height: 12),
                      _buildLowStockFilter(),
                      const SizedBox(height: 24),
                      _sectionTitle(theme, "Inventory"),
                      const SizedBox(height: 12),
                      ..._filteredProducts.isNotEmpty
                          ? _filteredProducts.take(30).map((p) => _productTile(theme, p))
                          : [_emptyCard(theme, _query.isEmpty
                              ? "No products yet. Tap + to add one."
                              : "No products match \u201C$_query\u201D.")],
                      const SizedBox(height: 28),
                      _sectionTitle(theme, "Orders"),
                      const SizedBox(height: 12),
                      ..._filteredOrders.isNotEmpty
                          ? _filteredOrders.take(50).map((o) => _orderRow(theme, o))
                          : [_emptyCard(theme, _query.isEmpty
                              ? "No orders yet"
                              : "No orders match \u201C$_query\u201D.")],
                      const SizedBox(height: 28),
                      _sectionTitle(theme, "Staff"),
                      const SizedBox(height: 12),
                      ..._filteredStaff.isNotEmpty
                          ? _filteredStaff.map((s) => _staffTile(theme, s))
                          : [_emptyCard(theme, _query.isEmpty
                              ? "No staff yet. Tap the people icon to add one."
                              : "No staff match \u201C$_query\u201D.")],
                      const SizedBox(height: 28),
                      _sectionTitle(theme, "Customers"),
                      const SizedBox(height: 12),
                      ..._filteredCustomers.isNotEmpty
                          ? _filteredCustomers.map((c) => _customerTile(theme, c))
                          : [_emptyCard(theme, _query.isEmpty
                              ? "No customers yet"
                              : "No customers match \u201C$_query\u201D.")],
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

  Widget _sectionTitle(ThemeData theme, String title) => Text(
      title,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface));

  Widget _buildHeader(ThemeData theme) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    final shopPrimary = theme.primaryColor;
    final rangeRevenue = (_summary['revenue'] as num?)?.toDouble() ?? 0;
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(22),
       decoration: BoxDecoration(
         gradient: LinearGradient(colors: [shopPrimary, shopPrimary.withValues(alpha: 0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
         boxShadow: [BoxShadow(color: shopPrimary.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
          child: const Icon(LucideIcons.bookOpen, color: Colors.white, size: 28)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Bookshop Management", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
          Text("$_totalProducts products • ${currency.format(rangeRevenue)} in range", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
        ])),
      ]),
    );
  }

  Widget _buildRangeBar(ThemeData theme) {
    final fmt = DateFormat('d MMM');
    return InkWell(
      onTap: _pickRange,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Icon(LucideIcons.calendarRange, size: 18, color: theme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${fmt.format(_range.start)} – ${fmt.format(_range.end)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          Text('CHANGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: theme.primaryColor)),
        ]),
      ),
    );
  }

  Widget _buildStatsGrid(ThemeData theme) {
    final currency = NumberFormat.currency(symbol: 'K ', decimalDigits: 0);
    final revenue = (_summary['revenue'] as num?)?.toDouble() ?? 0;
    final orders = (_summary['order_count'] as num?)?.toInt() ?? 0;
    final units = (_summary['units_sold'] as num?)?.toInt() ?? 0;
    final aov = (_summary['avg_order_value'] as num?)?.toDouble() ?? 0;
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.2,
      children: [
         _statCard("Products", "$_totalProducts", LucideIcons.package, Theme.of(context).primaryColor),
        _statCard("Orders (range)", "$orders", LucideIcons.shoppingCart, Colors.green),
        _statCard("Units sold", "$units", LucideIcons.shoppingBag, Colors.blue),
        _statCard("Revenue (range)", currency.format(revenue), LucideIcons.trendingUp, Colors.purple),
        _statCard("Avg order", currency.format(aov), LucideIcons.circleDollarSign, Colors.teal),
        _statCard("Low Stock", "$_lowStockCount", LucideIcons.alertTriangle, Colors.amber),
        _statCard("Inventory Value", currency.format(_inventoryValue), LucideIcons.box, Colors.indigo),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ),
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

  Widget _buildMarketplaceToggle(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SwitchListTile(
        value: _showInMarketplace,
        onChanged: _toggleMarketplace,
        secondary: Icon(LucideIcons.store, color: theme.primaryColor),
        title: const Text('List in church marketplaces',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: const Text(
          'Show your catalogue to church members shopping in the app',
          style: TextStyle(fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchC,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Search products, orders, staff, customers…',
        prefixIcon: const Icon(LucideIcons.search, size: 18),
        suffixIcon: _searchC.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.x, size: 16),
                onPressed: () {
                  _searchC.clear();
                  _onSearchChanged('');
                },
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        isDense: true,
      ),
    );
  }

  Widget _buildLowStockFilter() {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilterChip(
        selected: _lowStockOnly,
        onSelected: (v) => setState(() => _lowStockOnly = v),
        avatar: const Icon(LucideIcons.alertTriangle, size: 16),
        label: Text("Low stock (<$_lowStockThreshold) · $_lowStockCount"),
      ),
    );
  }

  Widget _productTile(ThemeData theme, Map<String, dynamic> product) {
    final title = product['name'] as String? ?? 'Untitled';
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final stock = (product['stock'] as num?)?.toInt() ?? 0;
    final status = stock == 0 ? 'Out of Stock' : stock < _lowStockThreshold ? 'Low Stock' : 'In Stock';
    final statusColor = stock == 0 ? Colors.red : stock < _lowStockThreshold ? Colors.orange : Colors.green;
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
               color: theme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
             child: Icon(LucideIcons.book, color: theme.primaryColor, size: 18),
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
    final id = order['id']?.toString() ?? '';
    final amount = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final status = (order['status'] as String? ?? 'pending');
    final next = _transitions[status] ?? const <String>[];
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${id.length >= 8 ? id.substring(0, 8) : id} · ${currency.format(amount)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                Text(
                  _statusLabel(status),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (next.isEmpty)
            Text(status.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)))
          else
            PopupMenuButton<String>(
              tooltip: 'Update status',
              onSelected: (value) => _setOrderStatus(id, value),
              itemBuilder: (_) => next
                  .map((s) => PopupMenuItem(value: s, child: Text(_statusLabel(s))))
                  .toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Text(status.toUpperCase(),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor)),
                  const Icon(LucideIcons.chevronDown, size: 12),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'confirmed':
        return 'Confirmed';
      case 'processing':
        return 'Processing';
      case 'shipped':
        return 'Shipped';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      case 'refunded':
        return 'Refunded';
      default:
        return 'Pending';
    }
  }

  Widget _staffTile(ThemeData theme, BookshopUser user) {
    final name = user.displayName;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        CircleAvatar(radius: 16, child: Text(name[0].toUpperCase())),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(user.email.isEmpty ? 'no email' : user.email,
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(user.role.replaceAll('_', ' '),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: theme.primaryColor)),
        ),
      ]),
    );
  }

  Widget _customerTile(ThemeData theme, Map<String, dynamic> customer) {
    final name = (customer['full_name'] ?? '').toString().trim();
    final label = name.isEmpty ? 'Unnamed customer' : name;
    final count = (customer['order_count'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        CircleAvatar(radius: 16, child: Text(label[0].toUpperCase())),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text((customer['email'] ?? '').toString(),
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          ]),
        ),
        Text('$count order${count == 1 ? '' : 's'}',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
      ]),
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
