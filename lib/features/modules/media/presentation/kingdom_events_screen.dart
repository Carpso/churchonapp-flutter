import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/event_service.dart';
import 'package:church_on_app/features/finance/presentation/qr_payment_screen.dart' as qps;
import 'package:church_on_app/features/finance/presentation/lipila_payment_gateway.dart';

class KingdomEventsScreen extends ConsumerWidget {
  const KingdomEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(kingdomUpcomingEventsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Events", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: eventsAsync.when(
        data: (events) => ListView.builder(
          padding: const EdgeInsets.all(25),
          itemCount: events.length,
          itemBuilder: (context, index) => _buildEventCard(context, ref, events[index]),
        ),
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (e, s) => Center(child: Text("Error: $e")),
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, WidgetRef ref, KingdomEvent event) {
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
          Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              image: DecorationImage(
                image: NetworkImage(
                  event.category == 'Conference' 
                    ? "https://images.unsplash.com/photo-1540575861501-7c0f110f6fdf?w=800&q=80"
                    : "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=800&q=80"
                ),
                fit: BoxFit.cover,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.calendar, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text("${event.eventDate.day}/${event.eventDate.month}/${event.eventDate.year}", style: const TextStyle(color: Colors.grey)),
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
                      event.price == 0 ? "FREE MISSION" : "K ${event.price.toStringAsFixed(2)}",
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

  void _purchaseTicket(BuildContext context, WidgetRef ref, KingdomEvent event) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Ticket?"),
        content: Text("Would you like to reserve your spot for ${event.title}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'back'), child: const Text("BACK")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => qps.QrPaymentScreen(
                amount: event.price,
                description: "Event Ticket: ${event.title}",
                recipient: "Apostolic Network Hub",
              )));
            },
            child: const Text("PAY VIA QR", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => LipilaPaymentGateway(
                amount: event.price,
                description: "Ticket: ${event.title}",
                onComplete: (success, txId) {
                  Navigator.pop(context);
                  if (success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payment successful! Ticket reserved.")));
                  }
                },
              )));
            },
            child: const Text("PAY VIA MOBILE MONEY", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(onPressed: () => Navigator.pop(context, 'reserve'), child: const Text("YES, RESERVE")),
        ],
      ),
    );

    if (action == 'reserve') {
      await ref.read(kingdomEventServiceProvider).purchaseTicket(event.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Apostolic Ticket successfully registered on VPS!")));
      }
    }
  }
}

