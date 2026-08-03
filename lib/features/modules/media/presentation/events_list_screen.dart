import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import 'package:church_on_app/features/give/presentation/lipila_payment_gateway.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';

class EventsListScreen extends ConsumerWidget {
  const EventsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Events", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: eventsAsync.when(
        data: (events) => events.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.calendarOff, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text("No upcoming events", style: TextStyle(color: Colors.grey[500], fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(25),
                itemCount: events.length,
                itemBuilder: (context, index) => _buildEventCard(context, ref, events[index]),
              ),
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(25),
          itemCount: 3,
          itemBuilder: (context, index) => _buildShimmerCard(),
        ),
        error: (e, s) => Center(child: Text("Error: $e")),
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, WidgetRef ref, ChurchEvent event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 180,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppImage(event.imageUrl, fit: BoxFit.cover),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                        ),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(10)),
                            child: Text(event.category.toUpperCase(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                          ),
                          const SizedBox(height: 10),
                          Text(event.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.calendar, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text("${event.date.day}/${event.date.month}/${event.date.year}", style: const TextStyle(color: Colors.grey)),
                    const Spacer(),
                    const Icon(LucideIcons.mapPin, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(event.location, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                const Divider(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      event.ticketPrice == 0 ? "FREE MISSION" : "K ${event.ticketPrice.toStringAsFixed(2)}",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.green),
                    ),
                    ElevatedButton(
                      onPressed: () => _purchaseTicket(context, ref, event),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Text("GET TICKET"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _purchaseTicket(BuildContext context, WidgetRef ref, ChurchEvent event) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Ticket?"),
        content: Text("Would you like to reserve your spot for ${event.title}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'back'), child: const Text("BACK")),
          TextButton(
            onPressed: () => Navigator.pop(context, 'pay'),
            child: const Text("PAY VIA MOBILE MONEY", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(onPressed: () => Navigator.pop(context, 'reserve'), child: const Text("YES, RESERVE")),
        ],
      ),
    );

    if (action == 'pay' && context.mounted) {
      final tenant = ref.read(currentTenantProvider);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => LipilaPaymentGateway(
          amount: event.ticketPrice,
          description: "Ticket: ${event.title}",
          category: "event",
          recipientName: tenant?.name ?? "Church On App",
          recipientAccount: tenant?.treasurerPhone,
          paymentReason: "Ticket: ${event.title}",
          onComplete: (success, txId) async {
            Navigator.pop(context);
            if (success && txId != null && context.mounted) {
              try {
                await ref.read(eventServiceProvider).registerForEvent(event.id);
                await ref.read(financeServiceProvider).logTransaction(
                  event.ticketPrice, 'event', txId, tenantId: tenant?.id,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payment successful! Ticket purchased.")));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Payment received but registration failed: $e")));
                }
              }
            }
          },
        ),
      );
    } else if (action == 'reserve') {
      final service = ref.read(eventServiceProvider);
      await service.registerForEvent(event.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Apostolic Ticket successfully registered!")));
      }
    }
  }

  Widget _buildShimmerCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerLoader.rectangular(height: 180),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    const ShimmerLoader.rectangular(width: 16, height: 16),
                    const SizedBox(width: 8),
                    const ShimmerLoader.rectangular(width: 80, height: 14),
                    const Spacer(),
                    const ShimmerLoader.rectangular(width: 16, height: 16),
                    const SizedBox(width: 8),
                    const ShimmerLoader.rectangular(width: 60, height: 14),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const ShimmerLoader.rectangular(width: 80, height: 20),
                    ShimmerLoader.rectangular(width: 100, height: 40),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
