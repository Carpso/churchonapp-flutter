import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class ManageTab extends ConsumerStatefulWidget {
  final VoidCallback onCreateEvent;
  const ManageTab({super.key, required this.onCreateEvent});

  @override
  ConsumerState<ManageTab> createState() => _ManageTabState();
}

class _ManageTabState extends ConsumerState<ManageTab> {
  bool _loading = true;
  int _eventCount = 0;
  int _ticketsSold = 0;
  int _checkedIn = 0;
  double _revenue = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final client = Supabase.instance.client;
      final eventsRes = await client
          .from('events')
          .select('id')
          .eq('tenant_id', tenant.id);
      final eventsCount = List<Map<String, dynamic>>.from(eventsRes).length;

      final regsRes = await client
          .from('event_registrations')
          .select('ticket_quantity, rsvp_status, check_in_status, events!inner (ticket_price, price)')
          .eq('events.tenant_id', tenant.id);

      var tickets = 0;
      var checkedIn = 0;
      var revenue = 0.0;
      for (final reg in List<Map<String, dynamic>>.from(regsRes)) {
        final status = (reg['rsvp_status'] ?? '').toString().toLowerCase();
        if (status.contains('cancel') || status.contains('decline')) continue;
        final qty = (reg['ticket_quantity'] as num?)?.toInt() ?? 1;
        tickets += qty;
        if ((reg['check_in_status'] ?? '').toString() == 'checked_in') {
          checkedIn += qty;
        }
        final ev = reg['events'];
        if (ev is Map) {
          final price = (ev['ticket_price'] as num?)?.toDouble() ??
              (ev['price'] as num?)?.toDouble() ??
              0;
          revenue += price * qty;
        }
      }

      if (mounted) {
        setState(() {
          _eventCount = eventsCount;
          _ticketsSold = tickets;
          _checkedIn = checkedIn;
          _revenue = revenue;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ManageTab stats failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GestureDetector(
            onTap: widget.onCreateEvent,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Theme.of(context).primaryColor, Colors.orangeAccent]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))]
              ),
              child: Row(
                children: [
                  CircleAvatar(backgroundColor: Colors.white.withValues(alpha: 0.2), child: const Icon(LucideIcons.plus, color: Colors.white)),
                  const SizedBox(width: 15),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Create New Event", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text("Host tickets, live streams & more", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text("Dashboard & Analytics", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          if (_loading)
            const SizedBox(
              height: 90,
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Row(
              children: [
                Expanded(child: _MetricCard(title: "Tickets Sold", value: "$_ticketsSold", icon: LucideIcons.ticket, color: Colors.blue)),
                const SizedBox(width: 15),
                Expanded(child: _MetricCard(title: "Revenue (K)", value: _revenue.toStringAsFixed(2), icon: LucideIcons.wallet, color: Colors.green)),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _MetricCard(title: "Events Hosted", value: "$_eventCount", icon: LucideIcons.calendarDays, color: Colors.orange)),
                const SizedBox(width: 15),
                Expanded(child: _MetricCard(title: "Checked In", value: "$_checkedIn", icon: LucideIcons.clipboardCheck, color: Colors.teal)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}
