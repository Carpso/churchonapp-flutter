import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/admin/data/order_service.dart';

class OrderTrackingScreen extends ConsumerWidget {
  const OrderTrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: ordersAsync.when(
        data: (orders) => orders.isEmpty
            ? const Center(child: Text('No orders yet'))
            : ListView.builder(
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final statusColor = switch (order.status) {
                    'delivered' => Colors.green,
                    'shipped' => Theme.of(context).primaryColor,
                    'processing' => Colors.orange,
                    'cancelled' => Colors.red,
                    _ => Colors.grey,
                  };
                  final statusIcon = switch (order.status) {
                    'delivered' => LucideIcons.checkCircle,
                    'shipped' => LucideIcons.truck,
                    'processing' => LucideIcons.loader,
                    'cancelled' => LucideIcons.xCircle,
                    _ => LucideIcons.clock,
                  };

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ExpansionTile(
                      leading: Icon(statusIcon, color: statusColor, size: 28),
                      title: Text('Order #${order.id.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('K ${order.totalAmount.toStringAsFixed(2)} - ${order.status.toUpperCase()}'),
                      children: [
                        if (order.items != null) ...[
                          for (final item in order.items!)
                            ListTile(
                              leading: const Icon(LucideIcons.package, size: 20),
                              title: Text(item.itemName),
                              subtitle: Text('Qty: ${item.quantity} x K${item.unitPrice.toStringAsFixed(2)}'),
                              trailing: Text('K${item.totalPrice.toStringAsFixed(2)}'),
                            ),
                          const Divider(),
                        ],
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (order.shippingAddress != null)
                                Text('Shipping: ${order.shippingAddress}', style: const TextStyle(fontSize: 12)),
                              if (order.paymentReference != null)
                                Text('Payment Ref: ${order.paymentReference}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              Text('Payment: ${order.paymentStatus.toUpperCase()}', style: TextStyle(fontSize: 12, color: order.paymentStatus == 'paid' ? Colors.green : Colors.red)),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: FutureBuilder<List<Delivery>>(
                            future: ref.read(orderServiceProvider).getDeliveriesForOrder(order.id),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                return const Text('No delivery info yet', style: TextStyle(color: Colors.grey));
                              }
                              final delivery = snapshot.data!.first;
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Delivery: ${delivery.status.toUpperCase()}',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: delivery.status == 'delivered' ? Colors.green : Theme.of(context).primaryColor)),
                                    if (delivery.recipientName != null) Text('Recipient: ${delivery.recipientName}'),
                                    if (delivery.proofOfDeliveryUrl != null)
                                      TextButton.icon(
                                        onPressed: () {},
                                        icon: const Icon(LucideIcons.image, size: 16),
                                        label: const Text('View Proof of Delivery'),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
