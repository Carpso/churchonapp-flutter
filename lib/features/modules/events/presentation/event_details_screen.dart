import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:church_on_app/features/finance/presentation/lipila_payment_gateway.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/widgets/premium_confirmation_sheet.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'event_host_dashboard.dart';

class EventDetailsScreen extends ConsumerWidget {
  final Map<String, dynamic> event;
  const EventDetailsScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool isFree = event['price'] == 0;
    final currentUser = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Image.network(
                (event['cover'] != null && (event['cover'] as String).isNotEmpty)
                    ? event['cover']
                    : "https://images.unsplash.com/photo-1501281668745-f7f57925c3b4?w=800&q=80",
                fit: BoxFit.cover,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.share2), 
                onPressed: () {
                  SharePlus.instance.share(ShareParams(
                    text: "Join us at ${event['title']}! Location: ${event['location']}, Date: ${event['date']}. Details: https://churchonapp.com/events/${event['id']}",
                    subject: event['title'],
                  ));
                }
              ),
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
                    _buildInfoTile(LucideIcons.calendar, "Date & Time", "${event['date']}${event['time'] != null ? ' • ${event['time']}' : ''}${event['end_date'] != null && (event['end_date'] as String).isNotEmpty ? ' to ${event['end_date']}' : ''}"),
                    _buildInfoTile(LucideIcons.mapPin, "Location", event['location']),
                    _buildInfoTile(LucideIcons.banknote, "Admission", isFree ? "Free Entry" : "K${event['price']} per person"),
                    if (event['speakers'] != null && (event['speakers'] as String).isNotEmpty)
                      _buildInfoTile(LucideIcons.mic, "Guest Speakers", event['speakers']),
                    const Divider(height: 50),
                    const Text("About the Event", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    Text(
                      event['description'] ?? "Join us for an incredible experience as we gather to worship, learn, and grow together. This event is designed to bring the community closer to God through inspired messages and powerful fellowship.",
                      style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
                    ),
                    const SizedBox(height: 30),
                    // 1. Linked Participating Churches (For interchurch conferences)
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: Supabase.instance.client
                          .from('event_participating_churches')
                          .select('church_id, churches (name, logo_url)')
                          .eq('event_id', event['id'])
                          .then((data) => List<Map<String, dynamic>>.from(data))
                          .catchError((_) => <Map<String, dynamic>>[]),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
                        final list = snapshot.data ?? [];
                        if (list.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Participating Churches", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: list.map((item) {
                                final ch = item['churches'] as Map<String, dynamic>?;
                                final name = ch?['name'] ?? 'Partner Church';
                                final logo = ch?['logo_url'] ?? '';
                                return Chip(
                                  avatar: logo.isNotEmpty 
                                      ? CircleAvatar(backgroundImage: NetworkImage(logo))
                                      : const CircleAvatar(child: Icon(LucideIcons.home, size: 12)),
                                  label: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                  backgroundColor: Colors.grey.shade100,
                                );
                              }).toList(),
                            ),
                            const Divider(height: 40),
                          ],
                        );
                      },
                    ),

                    // 2. Shared Event Resources (Materials & Booklet Program)
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: Supabase.instance.client
                          .from('event_resources')
                          .select('*')
                          .eq('event_id', event['id'])
                          .then((data) => List<Map<String, dynamic>>.from(data))
                          .catchError((_) => <Map<String, dynamic>>[]),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
                        final list = snapshot.data ?? [];
                        if (list.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Conference Materials", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const Text("Shared documents, files & presentation slides.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(height: 15),
                            ...list.map((res) {
                              final title = res['title'] ?? 'Program Booklet';
                              final type = res['resource_type'] ?? 'document';
                              final url = res['resource_url'] ?? '';
                              return Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: Icon(
                                    type == 'media' ? LucideIcons.video : LucideIcons.fileText,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: const Text("Tap to copy resource URL link", style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  trailing: const Icon(LucideIcons.link2, size: 16),
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: url));
                                    PremiumToast.showSuccess(context, "Resource link copied to clipboard!");
                                  },
                                ),
                              );
                            }),
                            const Divider(height: 40),
                          ],
                        );
                      },
                    ),

                    // 3. Organizer Gate check-in console
                    if (currentUser != null && currentUser.id == event['created_by'])
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 30),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EventHostDashboardScreen(
                                  eventId: event['id'],
                                  eventTitle: event['title'],
                                ),
                              ),
                            );
                          },
                          icon: const Icon(LucideIcons.shieldCheck),
                          label: const Text("OPEN ORGANIZER PORTAL (GATE PASSES)"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),
                      ),

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
                const Text("Total (Inc. MoMo Fee)", style: TextStyle(color: Colors.grey, fontSize: 10)),
                Text(
                  isFree 
                      ? "FREE" 
                      : "K${(event['price'] * 1.0 + (event['price'] * 0.05 > 3.00 ? event['price'] * 0.05 : 3.00)).toStringAsFixed(2)}", 
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: ElevatedButton(
                  onPressed: () {
                    if (isFree) {
                      ref.read(eventServiceProvider).registerForEvent(event['id']).then((_) {
                        if (context.mounted) {
                          PremiumConfirmationSheet.show(
                            context: context,
                            title: "RSVP Successful!",
                            message: "You're registered for ${event['title']}. It has been added to your events.",
                            type: ConfirmationType.success,
                            primaryLabel: "EXCITED!",
                          );
                        }
                      }).catchError((err) {
                        if (context.mounted) {
                          PremiumToast.showError(context, "RSVP Failed: ${err.toString().replaceAll("Exception: ", "")}");
                        }
                      });
                  } else {
                    final double ticketPrice = event['price'] * 1.0;
                    final double fee = ticketPrice * 0.05 > 3.00 ? ticketPrice * 0.05 : 3.00;
                    final tenant = ref.read(currentTenantProvider);
                    final String directMomo = (event['organizer_momo_phone']?.toString() ?? '').trim();
                    final String destinationAccount = directMomo.isNotEmpty 
                        ? directMomo 
                        : (tenant?.treasurerPhone ?? "Merchant ID: 68907");
                    final String destinationName = directMomo.isNotEmpty
                        ? "Event Host Payout"
                        : (tenant?.name ?? "Church On App (Events)");

                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => LipilaPaymentGateway(
                        amount: ticketPrice + fee, 
                        description: "Ticket: ${event['title']}",
                        category: "event",
                        recipientName: destinationName,
                        recipientAccount: destinationAccount,
                        paymentReason: "Ticket: ${event['title']}",
                        onComplete: (success, txId) async {
                          Navigator.pop(context);
                          if (success) {
                            try {
                              // 1. Log transaction
                              await ref.read(financeServiceProvider).logTransaction(
                                ticketPrice,
                                'event',
                                txId!,
                                tenantId: tenant?.id,
                                recipientPhone: event['organizer_momo_phone'],
                                recipientName: event['organizer_momo_name'] ?? destinationName,
                              );
                              // 2. Register for event
                              await ref.read(eventServiceProvider).registerForEvent(event['id']);

                              if (context.mounted) {
                                PremiumConfirmationSheet.show(
                                  context: context,
                                  title: "Ticket Purchased!",
                                  message: "Your ticket for ${event['title']} has been confirmed. Check 'My Tickets' for details.",
                                  type: ConfirmationType.success,
                                  primaryLabel: "AWESOME",
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                PremiumToast.showWarning(
                                  context,
                                  "Registration Sync Error: ${e.toString().replaceAll("Exception: ", "")}",
                                  title: "Payment Received",
                                );
                              }
                            }
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
    bool isReminderSet = false;
    return StatefulBuilder(
      builder: (context, setState) {
        return IconButton(
          icon: Icon(isReminderSet ? LucideIcons.bellRing : LucideIcons.bell, color: isReminderSet ? Colors.amber : null),
          onPressed: () {
            setState(() {
              isReminderSet = !isReminderSet;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isReminderSet ? "Reminder set for 1 hour before event!" : "Reminder cancelled."),
                backgroundColor: isReminderSet ? Colors.green : Colors.grey,
              ),
            );
          },
        );
      }
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

