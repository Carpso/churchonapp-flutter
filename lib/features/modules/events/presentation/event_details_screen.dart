import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:church_on_app/features/finance/presentation/lipila_payment_gateway.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/core/widgets/premium_confirmation_sheet.dart';
import 'package:church_on_app/core/config/fee_config.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'event_host_dashboard.dart';

class EventDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> event;
  const EventDetailsScreen({super.key, required this.event});

  @override
  ConsumerState<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends ConsumerState<EventDetailsScreen> {
  bool _isPurchasing = false;

  @override
  Widget build(BuildContext context) {
    final priceText = widget.event['price']?.toString() ?? '';
    final price = double.tryParse(priceText) ?? 0;
    bool isFree = price <= 0;
    final currentUser = Supabase.instance.client.auth.currentUser;
    final event = widget.event;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: AppImage(
                (event['cover'] != null && (event['cover'] as String?)?.isNotEmpty == true)
                    ? event['cover']
                    : "",
                fit: BoxFit.cover,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.scanLine),
                tooltip: 'Scan Tickets',
                onPressed: () {
                  final eventId = event['id']?.toString() ?? '';
                  if (eventId.isNotEmpty) {
                    context.push('/events/ticket-scanner/$eventId', extra: event['title']?.toString() ?? 'Event');
                  }
                },
              ),
              IconButton(
                icon: const Icon(LucideIcons.share2), 
                onPressed: () {
                  SharePlus.instance.share(ShareParams(
                    text: "Join us at ${event['title'] ?? 'this event'}! Location: ${event['location'] ?? 'TBA'}, Date: ${event['date'] ?? 'TBA'}. Details: https://churchonapp.com/events/${event['id']}",
                    subject: event['title']?.toString() ?? 'Church On App Event',
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
                      child: Text((event['type'] ?? 'Event').toUpperCase(), style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 15),
                    Text(event['title']?.toString() ?? 'Event', style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
                    const SizedBox(height: 25),
                    _buildInfoTile(LucideIcons.calendar, "Date & Time", "${event['date'] ?? ''}${event['time'] != null ? ' • ${event['time']}' : ''}${event['end_date'] != null && (event['end_date'] as String?)?.isNotEmpty == true ? ' to ${event['end_date']}' : ''}"),
                    _buildInfoTile(LucideIcons.mapPin, "Location", (event['location'] as String?) ?? 'TBA'),
                    _buildInfoTile(LucideIcons.banknote, "Admission", isFree ? "Free Entry" : "K$price per person"),
                    if (event['speakers'] != null && (event['speakers'] as String?)?.isNotEmpty == true)
                      _buildInfoTile(LucideIcons.mic, "Guest Speakers", (event['speakers'] as String?) ?? ''),
                    const Divider(height: 50),
                    const Text("About the Event", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    Text(
                      event['description'] ?? "Join us for an incredible experience as we gather to worship, learn, and grow together. This event is designed to bring the community closer to God through inspired messages and powerful fellowship.",
                      style: TextStyle(fontSize: 16, height: 1.6, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85)),
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
                          .select('id, title, resource_type, resource_url')
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
                    ..._buildSpecialGuests(context),
                    if (currentUser != null && currentUser.id == event['created_by'])
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: TextButton.icon(
                          onPressed: () => _addSpecialGuest(context),
                          icon: const Icon(LucideIcons.plus, size: 16),
                          label: const Text("Add Special Guest (Promoter)"),
                        ),
                      ),
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
                const Text("Ticket Price", style: TextStyle(color: Colors.grey, fontSize: 11)),
                Text(
                  isFree
                      ? "FREE"
                      : "K${(double.tryParse(event['price'].toString()) ?? 0).toStringAsFixed(2)}",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
                ),
                if (!isFree) ...[
                  const SizedBox(height: 2),
                  Builder(
                    builder: (ctx) {
                      final fees = ref.read(feeConfigProvider).value ?? FeeConfig.defaults;
                      final price = double.tryParse(event['price'].toString()) ?? 0;
                      final pf = fees.platformFee(price);
                      return Text(
                        "Platform Fee: K${pf.toStringAsFixed(2)}",
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                      );
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: ElevatedButton(
                  onPressed: _isPurchasing ? null : () {
                    if (isFree) {
                      setState(() => _isPurchasing = true);
                      ref.read(eventServiceProvider).registerForEvent(event['id']).then((_) {
                        if (context.mounted) {
                          setState(() => _isPurchasing = false);
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
                          setState(() => _isPurchasing = false);
                          PremiumToast.showError(context, "RSVP Failed: ${err.toString().replaceAll("Exception: ", "")}");
                        }
                      });
                  } else {
                    final double ticketPrice = event['price'] * 1.0;
                    final tenant = ref.read(currentTenantProvider);
                    final String directMomo = (event['organizer_momo_phone']?.toString() ?? '').trim();
                    final String destinationAccount = directMomo.isNotEmpty 
                        ? directMomo 
                        : (tenant?.treasurerPhone ?? "Merchant ID: 68907");
                    final String destinationName = directMomo.isNotEmpty
                        ? "Event Host Payout"
                        : (tenant?.name ?? "Church On App (Events)");

                    setState(() => _isPurchasing = true);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      isDismissible: true,
                      enableDrag: true,
                      builder: (context) => LipilaPaymentGateway(
                        amount: ticketPrice, 
                        description: "Ticket: ${event['title']}",
                        category: "event",
                        recipientName: destinationName,
                        recipientAccount: destinationAccount,
                        paymentReason: "Ticket: ${event['title']}",
                        onComplete: (success, txId) async {
                          Navigator.pop(context);
                          if (success) {
                            try {
                              await ref.read(financeServiceProvider).logTransaction(
                                ticketPrice,
                                'event',
                                txId!,
                                tenantId: tenant?.id,
                                recipientPhone: event['organizer_momo_phone'],
                                recipientName: event['organizer_momo_name'] ?? destinationName,
                              );
                              await ref.read(eventServiceProvider).registerForEvent(event['id']);

                              if (context.mounted) {
                                setState(() => _isPurchasing = false);
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
                                setState(() => _isPurchasing = false);
                                PremiumToast.showWarning(
                                  context,
                                  "Registration Sync Error: ${e.toString().replaceAll("Exception: ", "")}",
                                  title: "Payment Received",
                                );
                              }
                            }
                          } else {
                            if (context.mounted) setState(() => _isPurchasing = false);
                          }
                        },
                      ),
                    ).whenComplete(() {
                      if (mounted && _isPurchasing) {
                        setState(() => _isPurchasing = false);
                      }
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _isPurchasing
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(isFree ? "RSVP NOW" : "SECURE TICKET", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  List<Widget> _buildSpecialGuests(BuildContext context) {
    final raw = widget.event['special_guests'] ?? [];
    final guests = raw is List ? raw.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
    if (guests.isEmpty) {
      return [
        Text("No special guests added yet.", style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        const SizedBox(height: 10),
      ];
    }
    return guests.map((g) => _buildGuestTile(context, g['name'] ?? 'Guest', g['role'] ?? 'Special Guest', g['image_url'])).toList();
  }

  void _addSpecialGuest(BuildContext context) {
    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController();
    final imageCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Add Special Guest"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: roleCtrl, decoration: const InputDecoration(labelText: "Role (e.g. Guest Speaker)", border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: imageCtrl, decoration: const InputDecoration(labelText: "Photo URL (optional)", border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final guests = List<Map<String, dynamic>>.from(widget.event['special_guests'] ?? []);
              guests.add({
                'name': nameCtrl.text.trim(),
                'role': roleCtrl.text.trim().isNotEmpty ? roleCtrl.text.trim() : 'Special Guest',
                'image_url': imageCtrl.text.trim().isNotEmpty ? imageCtrl.text.trim() : null,
              });
              await Supabase.instance.client
                  .from('events')
                  .update({'special_guests': guests})
                  .eq('id', widget.event['id']);
              if (context.mounted) {
                PremiumToast.showSuccess(context, "Special guest added!");
              }
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestTile(BuildContext context, String name, String role, [String? imageUrl]) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                  backgroundColor: Colors.blueGrey,
                  child: imageUrl == null ? const Icon(LucideIcons.user, color: Colors.white, size: 32) : null,
                ),
                const SizedBox(height: 15),
                Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(role, style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CLOSE")),
            ],
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(15)),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blueGrey,
              backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
              child: imageUrl == null ? const Icon(LucideIcons.user, color: Colors.white, size: 16) : null,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(role, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

