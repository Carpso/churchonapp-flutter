import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OrderItem {
  final String id;
  final String orderId;
  final String? itemId;
  final String itemName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String? vendorId;

  OrderItem({
    required this.id,
    required this.orderId,
    this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.vendorId,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      itemId: map['item_id'] as String?,
      itemName: map['item_name'] as String,
      quantity: map['quantity'] as int? ?? 1,
      unitPrice: (map['unit_price'] as num).toDouble(),
      totalPrice: (map['total_price'] as num).toDouble(),
      vendorId: map['vendor_id'] as String?,
    );
  }
}

class Order {
  final String id;
  final String userId;
  final String? tenantId;
  final String status;
  final double totalAmount;
  final double deliveryFee;
  final double platformFee;
  final String? paymentReference;
  final String paymentStatus;
  final String? shippingAddress;
  final String? contactPhone;
  final String? notes;
  final DateTime createdAt;
  List<OrderItem>? items;

  Order({
    required this.id,
    required this.userId,
    this.tenantId,
    required this.status,
    required this.totalAmount,
    this.deliveryFee = 0,
    this.platformFee = 0,
    this.paymentReference,
    this.paymentStatus = 'pending',
    this.shippingAddress,
    this.contactPhone,
    this.notes,
    required this.createdAt,
    this.items,
  });

  factory Order.fromMap(Map<String, dynamic> map, {List<OrderItem>? items}) {
    return Order(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      tenantId: map['tenant_id'] as String?,
      status: map['status'] as String? ?? 'pending',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      deliveryFee: (map['delivery_fee'] as num?)?.toDouble() ?? 0,
      platformFee: (map['platform_fee'] as num?)?.toDouble() ?? 0,
      paymentReference: map['payment_reference'] as String?,
      paymentStatus: map['payment_status'] as String? ?? 'pending',
      shippingAddress: map['shipping_address'] as String?,
      contactPhone: map['contact_phone'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      items: items,
    );
  }
}

class Delivery {
  final String id;
  final String? orderId;
  final String? deliveryRequestId;
  final String? driverId;
  final String status;
  final String? pickupAddress;
  final String? deliveryAddress;
  final double? pickupLat;
  final double? pickupLng;
  final double? deliveryLat;
  final double? deliveryLng;
  final DateTime? estimatedDeliveryTime;
  final DateTime? actualDeliveryTime;
  final String? proofOfDeliveryUrl;
  final String? recipientName;
  final String? recipientPhone;
  final String? notes;
  final DateTime createdAt;

  Delivery({
    required this.id,
    this.orderId,
    this.deliveryRequestId,
    this.driverId,
    required this.status,
    this.pickupAddress,
    this.deliveryAddress,
    this.pickupLat,
    this.pickupLng,
    this.deliveryLat,
    this.deliveryLng,
    this.estimatedDeliveryTime,
    this.actualDeliveryTime,
    this.proofOfDeliveryUrl,
    this.recipientName,
    this.recipientPhone,
    this.notes,
    required this.createdAt,
  });

  factory Delivery.fromMap(Map<String, dynamic> map) {
    return Delivery(
      id: map['id'] as String,
      orderId: map['order_id'] as String?,
      deliveryRequestId: map['delivery_request_id'] as String?,
      driverId: map['driver_id'] as String?,
      status: map['status'] as String? ?? 'pending',
      pickupAddress: map['pickup_address'] as String?,
      deliveryAddress: map['delivery_address'] as String?,
      pickupLat: (map['pickup_lat'] as num?)?.toDouble(),
      pickupLng: (map['pickup_lng'] as num?)?.toDouble(),
      deliveryLat: (map['delivery_lat'] as num?)?.toDouble(),
      deliveryLng: (map['delivery_lng'] as num?)?.toDouble(),
      estimatedDeliveryTime: map['estimated_delivery_time'] != null ? DateTime.parse(map['estimated_delivery_time'] as String) : null,
      actualDeliveryTime: map['actual_delivery_time'] != null ? DateTime.parse(map['actual_delivery_time'] as String) : null,
      proofOfDeliveryUrl: map['proof_of_delivery_url'] as String?,
      recipientName: map['recipient_name'] as String?,
      recipientPhone: map['recipient_phone'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class OrderService {
  final SupabaseService _supabase;

  OrderService(this._supabase);

  Future<List<Order>> getMyOrders() async {
    final user = _supabase.client.auth.currentUser;
    if (user == null) return [];
    final result = await _supabase.client
        .from('orders')
        .select('*, order_items(*)')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return (result as List).map((e) {
      final items = (e['order_items'] as List?)
          ?.map((i) => OrderItem.fromMap(i as Map<String, dynamic>))
          .toList();
      return Order.fromMap(e, items: items);
    }).toList();
  }

  Future<List<OrderItem>> _getOrderItems(String orderId) async {
    final result = await _supabase.client
        .from('order_items')
        .select('id, order_id, item_id, item_name, quantity, unit_price, total_price, vendor_id')
        .eq('order_id', orderId);
    return (result as List).map((e) => OrderItem.fromMap(e)).toList();
  }

  Future<Order?> getOrderById(String orderId) async {
    final result = await _supabase.client
        .from('orders')
        .select('id, user_id, tenant_id, status, total_amount, delivery_fee, platform_fee, payment_reference, payment_status, shipping_address, contact_phone, notes, created_at')
        .eq('id', orderId)
        .single();
    final items = await _getOrderItems(orderId);
    return Order.fromMap(result, items: items);
  }

  Future<String> createOrder({
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    double deliveryFee = 0,
    double platformFee = 0,
    String? paymentReference,
    String? shippingAddress,
    String? contactPhone,
    String? notes,
    String? tenantId,
  }) async {
    final user = _supabase.client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");
    final userId = user.id;
    final orderResult = await _supabase.client.from('orders').insert({
      'user_id': userId,
      'tenant_id': tenantId,
      'total_amount': totalAmount,
      'delivery_fee': deliveryFee,
      'platform_fee': platformFee,
      'payment_reference': paymentReference,
      'payment_status': paymentReference != null ? 'paid' : 'pending',
      'shipping_address': shippingAddress,
      'contact_phone': contactPhone,
      'notes': notes,
    }).select('id').single();
    final orderId = orderResult['id'] as String;

    for (final item in items) {
      await _supabase.client.from('order_items').insert({
        'order_id': orderId,
        'item_id': item['item_id'],
        'item_name': item['item_name'],
        'quantity': item['quantity'],
        'unit_price': item['unit_price'],
        'total_price': item['total_price'],
        'vendor_id': item['vendor_id'],
        'tenant_id': tenantId,
        'church_id': tenantId,
      });
      try {
        await _supabase.client.from('user_purchases').insert({
          'user_id': userId,
          'item_id': item['item_id'],
          'order_id': orderId,
          'price': item['total_price'],
          'quantity': item['quantity'],
          'tenant_id': tenantId,
        });
      } catch (_) {
        // user_purchases may not have tenant_id column in older installs
        await _supabase.client.from('user_purchases').insert({
          'user_id': userId,
          'item_id': item['item_id'],
          'order_id': orderId,
          'price': item['total_price'],
          'quantity': item['quantity'],
        });
      }
      // Decrement stock atomically — non-fatal if item has no stock tracking
      try {
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        if (qty > 0 && item['item_id'] != null) {
          await _supabase.client.rpc('decrement_marketplace_stock', params: {
            'p_item_id': item['item_id'],
            'p_qty': qty,
          });
        }
      } catch (_) {
        // stock decrement is best-effort (e.g. digital items with no stock)
      }
    }

    return orderId;
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    await _supabase.client.from('orders').update({
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }

  Future<List<Delivery>> getDeliveriesForOrder(String orderId) async {
    final result = await _supabase.client
        .from('deliveries')
        .select('id, order_id, delivery_request_id, driver_id, status, pickup_address, delivery_address, pickup_lat, pickup_lng, delivery_lat, delivery_lng, estimated_delivery_time, actual_delivery_time, proof_of_delivery_url, recipient_name, recipient_phone, notes, created_at')
        .eq('order_id', orderId)
        .order('created_at', ascending: false);
    return (result as List).map((e) => Delivery.fromMap(e)).toList();
  }

  Future<Delivery?> getMyActiveDelivery() async {
    final user = _supabase.client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");
    final userId = user.id;
    final result = await _supabase.client
        .from('deliveries')
        .select('*, orders!inner(user_id)')
        .eq('orders.user_id', userId)
        .or('status.eq.pending,status.eq.assigned,status.eq.picked_up,status.eq.in_transit')
        .limit(1)
        .maybeSingle();
    if (result == null) return null;
    return Delivery.fromMap(result);
  }
}

final orderServiceProvider = Provider<OrderService>((ref) {
  final supabase = ref.read(supabaseServiceProvider);
  return OrderService(supabase);
});

final myOrdersProvider = FutureProvider<List<Order>>((ref) async {
  return ref.read(orderServiceProvider).getMyOrders();
});
