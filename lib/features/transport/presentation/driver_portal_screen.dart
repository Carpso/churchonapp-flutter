import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/transport_service.dart';
import '../data/ride_request_model.dart';
import '../data/delivery_model.dart';
import 'active_ride_tracking_screen.dart';

class DriverPortalScreen extends ConsumerWidget {
  const DriverPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingRidesAsync = ref.watch(pendingRidesStreamProvider);
    final pendingDeliveriesAsync = ref.watch(pendingDeliveriesStreamProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFAEB),
        appBar: AppBar(
          title: const Text("Command", style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(LucideIcons.car), text: "RIDES"),
              Tab(icon: Icon(LucideIcons.package), text: "CARGO"),
            ],
            indicatorColor: Colors.amber,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
          ),
          actions: [
            IconButton(icon: const Icon(LucideIcons.settings), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Driver settings coming soon")))),
          ],
        ),
        body: Column(
          children: [
            _buildStatusBanner(context),
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
              const Text("NEW REQUEST", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.2)),
              Text("K ${ride.fare.toInt()}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              const Column(
                children: [
                  Icon(LucideIcons.mapPin, color: Colors.blue, size: 18),
                  SizedBox(height: 20),
                  Icon(LucideIcons.navigation, color: Colors.green, size: 18),
                ],
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Pickup", style: TextStyle(color: Colors.grey, fontSize: 10)),
                    const Text("Main Street, Church View", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 10),
                    const Text("Destination", style: TextStyle(color: Colors.grey, fontSize: 10)),
                    const Text("Mall, Wing B", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request dismissed"))),
                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  child: const Text("IGNORE"),
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

  void _acceptRide(BuildContext context, WidgetRef ref, RideRequest ride) async {
    try {
      await ref.read(transportServiceProvider).acceptRide(ride.id);
      if (context.mounted) {
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
                child: Text(delivery.itemCategory.toUpperCase(), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 8, letterSpacing: 1)),
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
              const Icon(LucideIcons.mapPin, color: Colors.blue, size: 16),
              const SizedBox(width: 10),
              const Expanded(child: Text("Pickup: Church Offices", style: TextStyle(fontSize: 13))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(LucideIcons.navigation, color: Colors.green, size: 16),
              const SizedBox(width: 10),
              const Expanded(child: Text("Deliver: Member Residence", style: TextStyle(fontSize: 13))),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request dismissed"))),
                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  child: const Text("IGNORE"),
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
                  child: const Text("ACCEPT MISSION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _acceptDelivery(BuildContext context, WidgetRef ref, DeliveryRequest delivery) async {
    try {
      await ref.read(transportServiceProvider).acceptDelivery(delivery.id);
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveRideTrackingScreen(
              startPos: delivery.pickup,
              destPos: delivery.destination,
              deliveryId: delivery.id,
              type: 'delivery',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }
}

