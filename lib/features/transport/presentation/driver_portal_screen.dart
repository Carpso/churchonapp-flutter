import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import '../data/transport_service.dart';
import '../data/ride_request_model.dart';
import '../data/delivery_model.dart';
import 'active_ride_tracking_screen.dart';

class DriverPortalScreen extends ConsumerStatefulWidget {
  const DriverPortalScreen({super.key});

  @override
  ConsumerState<DriverPortalScreen> createState() => _DriverPortalScreenState();
}

class _DriverPortalScreenState extends ConsumerState<DriverPortalScreen> {
  StreamSubscription<List<RideRequest>>? _acceptedRidesSub;
  StreamSubscription<List<DeliveryRequest>>? _acceptedDeliveriesSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _watchAccepted());
  }

  @override
  void dispose() {
    _acceptedRidesSub?.cancel();
    _acceptedDeliveriesSub?.cancel();
    super.dispose();
  }

  /// Auto-open live tracking the moment the passenger pays for an accepted
  /// ride/delivery; otherwise surface a "waiting for payment" banner.
  void _watchAccepted() {
    _acceptedRidesSub?.cancel();
    _acceptedDeliveriesSub?.cancel();
    final service = ref.read(transportServiceProvider);
    _acceptedRidesSub = service.getMyAcceptedRidesStream().listen((rides) {
      if (!mounted) return;
      for (final ride in rides) {
        if (ride.paymentStatus == 'paid') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ActiveRideTrackingScreen(
                startPos: ride.pickup,
                destPos: ride.destination,
                requestId: ride.id,
                type: 'ride',
              ),
            ),
          );
        }
      }
    });
    _acceptedDeliveriesSub = service.getMyAcceptedDeliveriesStream().listen((deliveries) {
      if (!mounted) return;
      for (final d in deliveries) {
        if (d.paymentStatus == 'paid') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ActiveRideTrackingScreen(
                startPos: d.pickup,
                destPos: d.destination,
                requestId: d.id,
                type: 'delivery',
              ),
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pendingRidesAsync = ref.watch(pendingRidesStreamProvider);
    final pendingDeliveriesAsync = ref.watch(pendingDeliveriesStreamProvider);
    final acceptedRidesAsync = ref.watch(myAcceptedRidesStreamProvider);
    final acceptedDeliveriesAsync = ref.watch(myAcceptedDeliveriesStreamProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text("Command", style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(LucideIcons.car), text: "RIDES"),
              Tab(icon: Icon(LucideIcons.package), text: "CARGO"),
            ],
            indicatorColor: Colors.amber,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          ),
          actions: [
            IconButton(icon: const Icon(LucideIcons.settings), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Driver settings coming soon")))),
          ],
        ),
        body: Column(
          children: [
            _buildStatusBanner(context),
            _buildAwaitingPaymentBanner(context, acceptedRidesAsync.value, acceptedDeliveriesAsync.value),
            Expanded(
              child: TabBarView(
                children: [
                  // Rides Tab
                  pendingRidesAsync.when(
                    data: (rides) => rides.isEmpty
                        ? _buildEmptyState("citizens")
                        : ListView.builder(
                            padding: const EdgeInsets.all(20),
                            itemCount: rides.length,
                            itemBuilder: (context, index) => _buildRideRequestCard(context, ref, rides[index]),
                          ),
                    loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
                    error: (e, s) => Center(child: Text("Error: $e")),
                  ),
                  // Cargo Tab
                  pendingDeliveriesAsync.when(
                    data: (deliveries) => deliveries.isEmpty
                        ? _buildEmptyState("cargo missions")
                        : ListView.builder(
                            padding: const EdgeInsets.all(20),
                            itemCount: deliveries.length,
                            itemBuilder: (context, index) => _buildDeliveryCard(context, ref, deliveries[index]),
                          ),
                    loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
                    error: (e, s) => Center(child: Text("Error: $e")),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.green,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.zap, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text("ON DUTY • ACCEPTING REQUESTS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildAwaitingPaymentBanner(BuildContext context, List<RideRequest>? rides, List<DeliveryRequest>? deliveries) {
    final awaiting = <String>[
      ...?rides?.where((r) => r.paymentStatus != 'paid').map((r) => "Ride · K${r.currentFare.toInt()}"),
      ...?deliveries?.where((d) => d.paymentStatus != 'paid').map((d) => "Cargo · K${d.currentFare.toInt()}"),
    ];
    if (awaiting.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.amber.shade800,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Text(
        "Awaiting passenger payment: ${awaiting.join('  •  ')}",
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildEmptyState(String target) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.search, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text("Scanning for $target...", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          const Text("Stay active to receive new missions", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildRideRequestCard(BuildContext context, WidgetRef ref, RideRequest ride) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("NEW REQUEST", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2)),
              Text("K ${ride.fare.toInt()}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              const Column(
                children: [
                  Icon(LucideIcons.mapPin, color: Colors.amber, size: 18),
                  SizedBox(height: 20),
                  Icon(LucideIcons.navigation, color: Colors.green, size: 18),
                ],
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Pickup", style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Text(ride.pickupLabel ?? "Pickup point", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 10),
                    const Text("Destination", style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Text(ride.destLabel ?? "Destination", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _counterRide(context, ref, ride),
                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  child: const Text("COUNTER"),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptRide(context, ref, ride),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Theme.of(context).colorScheme.secondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text("ACCEPT", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _counterRide(BuildContext context, WidgetRef ref, RideRequest ride) async {
    final controller = TextEditingController(text: ride.fare.toStringAsFixed(0));
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Counter-Offer Fare"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixText: "K ",
            labelText: "Your fare",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text("Cancel")),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v == null || v <= 0) return;
              Navigator.pop(dialogCtx, v);
            },
            child: const Text("Send Offer"),
          ),
        ],
      ),
    );
    if (amount == null) return;
    try {
      await ref.read(transportServiceProvider).counterFare(ride.id, amount);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Counter-offer K${amount.toInt()} sent — waiting for the passenger")));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _acceptRide(BuildContext context, WidgetRef ref, RideRequest ride) async {
    try {
      await ref.read(transportServiceProvider).acceptRide(ride.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Request accepted — waiting for the passenger to pay")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Widget _buildDeliveryCard(BuildContext context, WidgetRef ref, DeliveryRequest delivery) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text(delivery.itemCategory.toUpperCase(), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
              ),
              Text("K ${delivery.fare.toInt()}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
            ],
          ),
          const SizedBox(height: 15),
          Text(delivery.itemDescription, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text("Weight: ${delivery.weight}", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const Divider(height: 30),
          Row(
            children: [
              const Icon(LucideIcons.mapPin, color: Colors.amber, size: 16),
              const SizedBox(width: 10),
              Expanded(child: Text(delivery.pickupLabel ?? "Pickup point", style: const TextStyle(fontSize: 13))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(LucideIcons.navigation, color: Colors.green, size: 16),
              const SizedBox(width: 10),
              Expanded(child: Text(delivery.destLabel ?? "Delivery point", style: const TextStyle(fontSize: 13))),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _counterDelivery(context, ref, delivery),
                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  child: const Text("COUNTER"),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptDelivery(context, ref, delivery),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text("ACCEPT", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _counterDelivery(BuildContext context, WidgetRef ref, DeliveryRequest delivery) async {
    final controller = TextEditingController(text: delivery.fare.toStringAsFixed(0));
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Counter-Offer Fare"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixText: "K ",
            labelText: "Your fare",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text("Cancel")),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v == null || v <= 0) return;
              Navigator.pop(dialogCtx, v);
            },
            child: const Text("Send Offer"),
          ),
        ],
      ),
    );
    if (amount == null) return;
    try {
      await ref.read(transportServiceProvider).counterDeliveryFare(delivery.id, amount);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Counter-offer K${amount.toInt()} sent — waiting for the sender")));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _acceptDelivery(BuildContext context, WidgetRef ref, DeliveryRequest delivery) async {
    try {
      await ref.read(transportServiceProvider).acceptDelivery(delivery.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cargo accepted — waiting for the sender to pay")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }
}