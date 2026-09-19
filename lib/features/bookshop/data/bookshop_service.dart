import 'package:supabase_flutter/supabase_flutter.dart';

/// A bookshop staff candidate / member shown in the picker and staff list.
class BookshopUser {
  final String id;
  final String fullName;
  final String email;
  final String role;
  final String? tenantId;

  const BookshopUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.tenantId,
  });

  factory BookshopUser.fromMap(Map<String, dynamic> map) {
    return BookshopUser(
      id: map['id']?.toString() ?? '',
      fullName: (map['full_name'] ?? '').toString().trim(),
      email: (map['email'] ?? '').toString().trim(),
      role: (map['role'] ?? 'member').toString(),
      tenantId: map['tenant_id']?.toString(),
    );
  }

  String get displayName => fullName.isEmpty ? 'Unnamed member' : fullName;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return fullName.toLowerCase().contains(q) || email.toLowerCase().contains(q);
  }
}

/// Real-data access for the bookshop tenant: staff picker, cross-listing toggle,
/// order state machine, and range-scoped sales summary.
class BookshopService {
  final SupabaseClient _client;
  BookshopService(this._client);

  static const List<String> staffRoles = [
    'bookshop_owner',
    'store_manager',
    'assistant',
    'cashier',
  ];

  /// Users searchable for the "Add Shop Staff" picker.
  ///
  /// Platform staff (superadmin/COA) can pick any user; a bookshop owner only
  /// picks from their own tenant. The RLS policies enforce this server-side.
  Future<List<BookshopUser>> fetchCandidates({
    required String? tenantId,
    required bool isPlatformStaff,
  }) async {
    var query = _client.from('profiles').select('id, full_name, email, role, tenant_id');
    if (!isPlatformStaff && tenantId != null && tenantId.isNotEmpty) {
      query = query.eq('tenant_id', tenantId);
    }
    final res = await query.order('full_name').limit(300);
    return (res as List)
        .map((e) => BookshopUser.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// The bookshop's own staff (for the searchable staff list). Falls back to
  /// the tenant's own profiles when the shop row is not readable.
  Future<List<BookshopUser>> fetchStaff(String tenantId) async {
    final res = await _client
        .from('profiles')
        .select('id, full_name, email, role, tenant_id')
        .eq('tenant_id', tenantId)
        .inFilter('role', staffRoles)
        .order('full_name');
    return (res as List)
        .map((e) => BookshopUser.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<bool> fetchShowInMarketplace(String tenantId) async {
    final row = await _client
        .from('bookshops')
        .select('show_in_marketplace')
        .eq('tenant_id', tenantId)
        .maybeSingle();
    return (row?['show_in_marketplace'] as bool?) ?? false;
  }

  Future<void> setShowInMarketplace(String tenantId, bool value) async {
    final updated = await _client
        .from('bookshops')
        .update({'show_in_marketplace': value})
        .eq('tenant_id', tenantId)
        .select('id');
    if ((updated as List).isEmpty) {
      throw Exception('Could not update listing preference');
    }
  }

  /// Orders for the shop, newest first. When [search] is set it matches the
  /// order id, phone, shipping address or notes.
  Future<List<Map<String, dynamic>>> fetchOrders({
    required String tenantId,
    String search = '',
    int limit = 200,
  }) async {
    var query = _client
        .from('orders')
        .select(
          'id, user_id, status, total_amount, payment_status, payment_reference, '
          'shipping_address, contact_phone, notes, created_at, '
          'confirmed_at, processing_at, shipped_at, delivered_at, cancelled_at, refunded_at',
        )
        .eq('tenant_id', tenantId);
    final s = search.trim();
    if (s.isNotEmpty) {
      final safe = s.replaceAll(RegExp(r'[,()]'), ' ');
      query = query.or(
        'id.ilike.%$safe%,'
        'shipping_address.ilike.%$safe%,'
        'contact_phone.ilike.%$safe%,'
        'notes.ilike.%$safe%',
      );
    }
    final res = await query.order('created_at', ascending: false).limit(limit);
    return (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Validate + apply an order status transition server-side.
  Future<void> setOrderStatus(String orderId, String status) async {
    await _client.rpc('set_order_status', params: {
      'p_order_id': orderId,
      'p_status': status,
    });
  }

  /// Real customers: unique buyers of this shop with names + order counts.
  Future<List<Map<String, dynamic>>> fetchCustomers(String tenantId) async {
    final res = await _client.rpc('get_bookshop_customers', params: {
      'p_tenant': tenantId,
    });
    return (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Real, range-scoped summary: order count, revenue, units, AOV.
  Future<Map<String, dynamic>> salesSummary({
    required String tenantId,
    required DateTime from,
    required DateTime to,
  }) async {
    final res = await _client.rpc('get_bookshop_sales_summary', params: {
      'p_tenant': tenantId,
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return const {};
  }

  /// RFC-4180 CSV of the given orders (safe for Excel).
  String ordersToCsv(List<Map<String, dynamic>> orders) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Order ID,Created,Status,Payment,Total,Currency,Phone,Shipping Address,Notes',
    );
    for (final o in orders) {
      String cell(Object? v) {
        final s = (v ?? '').toString().replaceAll('"', '""');
        return '"$s"';
      }

      buffer.writeln([
        cell(o['id']),
        cell(o['created_at']),
        cell(o['status']),
        cell(o['payment_status']),
        cell(o['total_amount']),
        cell('ZMW'),
        cell(o['contact_phone']),
        cell(o['shipping_address']),
        cell(o['notes']),
      ].join(','));
    }
    return buffer.toString();
  }
}
