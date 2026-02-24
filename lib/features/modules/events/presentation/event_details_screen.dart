import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/features/finance/presentation/lenco_payment_gateway.dart';

class EventDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> event;
  const EventDetailsScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    bool isFree = event['price'] == 0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Image.network(event['cover'], fit: BoxFit.cover),
            ),
            actions: [
              IconButton(icon: const Icon(LucideIcons.share2), onPressed: () {}),
              _buildReminderButton(context),
            ],
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text((event['type'] ?? 'Event').toUpperCase(), style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 15),
                    Text(event['title'], style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
                    const SizedBox(height: 25),
                    _buildInfoTile(LucideIcons.calendar, "Date & Time", "${event['date']} • ${event['time']}"),
                    _buildInfoTile(LucideIcons.mapPin, "Location", event['location']),
                    _buildInfoTile(LucideIcons.banknote, "Admission", isFree ? "Free Entry" : "K${event['price']} per person"),
                    const Divider(height: 50),
                    const Text("About the Event", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    const Text(
                      "Join us for an incredible experience as we gather to worship, learn, and grow together. This event is designed to bring the community closer to God through inspired messages and powerful fellowship.",
                      style: TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
                    ),
                    const SizedBox(height: 25),
                    const Text("Special Guests", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    _buildGuestTile("Min. Moses Bliss", "Worship Leader"),
                    _buildGuestTile("Pastor Jerry Eze", "Guest Speaker"),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Total Price", style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text(isFree ? "FREE" : "K${event['price']}.00", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(width: 30),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  if (isFree) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("RSVP Successful! Added to your events."), backgroundColor: Colors.green));
                  } else {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => LencoPaymentGateway(
                        amount: event['price'] * 1.0, 
                        description: "Ticket: ${event['title']}",
                        category: "event",
                        recipientName: "Church On App (Events)",
                        recipientAccount: "EVENT-TICKET-MERCHANT",
                        paymentReason: "Ticket: ${event['title']}",
                        onComplete: (success, txId) {
                          Navigator.pop(context);
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ticket Purchased Successfully! Check 'My Tickets'"), backgroundColor: Colors.green));
                          }
                        },
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(isFree ? "RSVP NOW" : "SECURE TICKET", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderButton(BuildContext context) {
    return IconButton(
      icon: const Icon(LucideIcons.bell),
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reminder set for 1 hour before event!")));
      },
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: Colors.black87, size: 20),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGuestTile(String name, String role) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          const CircleAvatar(backgroundColor: Colors.blueGrey, child: Icon(LucideIcons.user, color: Colors.white, size: 16)),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(role, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
