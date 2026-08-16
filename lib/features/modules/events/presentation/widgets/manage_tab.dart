import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';

class ManageTab extends ConsumerStatefulWidget {
  final VoidCallback onCreateEvent;
  const ManageTab({super.key, required this.onCreateEvent});

  @override
  ConsumerState<ManageTab> createState() => _ManageTabState();
}

class _EventStats {
  int tickets = 0;
  int checkedIn = 0;
  double revenue = 0;
}

class _ManageTabState extends ConsumerState<ManageTab> {
  bool _loading = true;
  int _eventCount = 0;
  int _upcomingCount = 0;
  int _ticketsSold = 0;
  int _checkedIn = 0;
  double _revenue = 0;
  final Map<String, _EventStats> _byEvent = {};
  List<Map<String, dynamic>> _events = [];

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
          .select('id, title, event_date, price, capacity')
          .eq('tenant_id', tenant.id);
      final events = List<Map<String, dynamic>>.from(eventsRes);
      final now = DateTime.now();

      final regsRes = await client
          .from('event_registrations')
          .select('event_id, ticket_quantity, rsvp_status, check_in_status, events!inner (ticket_price, price)')
          .eq('events.tenant_id', tenant.id);

      var tickets = 0;
      var checkedIn = 0;
      var revenue = 0.0;
      final byEvent = <String, _EventStats>{};
      for (final reg in List<Map<String, dynamic>>.from(regsRes)) {
        final status = (reg['rsvp_status'] ?? '').toString().toLowerCase();
        if (status.contains('cancel') || status.contains('decline')) continue;
        final qty = (reg['ticket_quantity'] as num?)?.toInt() ?? 1;
        final eventId = (reg['event_id'] ?? '').toString();
        final stats = byEvent.putIfAbsent(eventId, _EventStats.new);
        tickets += qty;
        stats.tickets += qty;
        if (reg['check_in_status'] == true) {
          checkedIn += qty;
          stats.checkedIn += qty;
        }
        final ev = reg['events'];
        if (ev is Map) {
          final price = (ev['ticket_price'] as num?)?.toDouble() ??
              (ev['price'] as num?)?.toDouble() ??
              0;
          revenue += price * qty;
          stats.revenue += price * qty;
        }
      }

      if (mounted) {
        setState(() {
          _eventCount = events.length;
          _upcomingCount = events.where((e) {
            final d = DateTime.tryParse((e['event_date'] ?? '').toString());
            return d != null && d.isAfter(now);
          }).length;
          _ticketsSold = tickets;
          _checkedIn = checkedIn;
          _revenue = revenue;
          _byEvent
            ..clear()
            ..addAll(byEvent);
          _events = events;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ManageTab stats failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _attendanceRate =>
      _ticketsSold == 0 ? 0 : (_checkedIn / _ticketsSold) * 100;

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
          if (_loading) ...[
            const Row(
              children: [
                Expanded(child: _MetricCardSkeleton()),
                SizedBox(width: 15),
                Expanded(child: _MetricCardSkeleton()),
              ],
            ),
            const SizedBox(height: 15),
            const Row(
              children: [
                Expanded(child: _MetricCardSkeleton()),
                SizedBox(width: 15),
                Expanded(child: _MetricCardSkeleton()),
              ],
            ),
            const SizedBox(height: 20),
            const ShimmerLoader.rectangular(height: 90),
          ] else ...[
            Row(
              children: [
                Expanded(child: _MetricCard(title: "Tickets Sold", value: "$_ticketsSold", icon: LucideIcons.ticket, color: Theme.of(context).primaryColor)),
                const SizedBox(width: 15),
                Expanded(child: _MetricCard(title: "Revenue (K)", value: _revenue.toStringAsFixed(2), icon: LucideIcons.wallet, color: Colors.green)),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _MetricCard(title: "Events Hosted", value: "$_eventCount", icon: LucideIcons.calendarDays, color: Colors.orange)),
                const SizedBox(width: 15),
                Expanded(child: _MetricCard(title: "Attendance Rate", value: "${_attendanceRate.toStringAsFixed(0)}%", icon: LucideIcons.clipboardCheck, color: Theme.of(context).primaryColor.withValues(alpha: 0.75))),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _MetricCard(title: "Upcoming Events", value: "$_upcomingCount", icon: LucideIcons.calendarClock, color: Theme.of(context).primaryColor.withValues(alpha: 0.55))),
                const SizedBox(width: 15),
                Expanded(child: _MetricCard(title: "Checked In", value: "$_checkedIn", icon: LucideIcons.userCheck, color: Theme.of(context).primaryColor.withValues(alpha: 0.45))),
              ],
            ),
            const SizedBox(height: 20),
            const Text("Event Breakdown", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Text(
                    "No events yet. Create your first event above.",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              )
            else
              ..._events.map((e) => _buildEventRow(e)),
          ],
        ],
      ),
    );
  }

  Widget _buildEventRow(Map<String, dynamic> event) {
    final id = (event['id'] ?? '').toString();
    final stats = _byEvent[id] ?? _EventStats();
    final date = DateTime.tryParse((event['event_date'] ?? '').toString());
    final price = (event['price'] as num?)?.toDouble() ?? 0;
    final capacity = (event['capacity'] as num?)?.toInt();
    final dateLabel = date == null ? '—' : DateFormat('MMM d, yyyy • h:mm a').format(date.toLocal());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  event['title']?.toString() ?? 'Untitled Event',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (date != null && date.isAfter(DateTime.now()))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text("UPCOMING", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(dateLabel, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          Row(
            children: [
              _miniStat("${stats.tickets} tickets", LucideIcons.ticket, Theme.of(context).primaryColor),
              const SizedBox(width: 14),
              _miniStat("${stats.checkedIn} checked in", LucideIcons.userCheck, Theme.of(context).primaryColor.withValues(alpha: 0.6)),
              const SizedBox(width: 14),
              _miniStat("K${stats.revenue.toStringAsFixed(2)}", LucideIcons.wallet, Colors.green),
              const Spacer(),
              if (capacity != null)
                Text("cap: $capacity", style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
          if (price > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text("Ticket price: K${price.toStringAsFixed(2)}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _miniStat(String text, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
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

class _MetricCardSkeleton extends StatelessWidget {
  const _MetricCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerLoader.rectangular(width: 26, height: 26),
          SizedBox(height: 12),
          ShimmerLoader.rectangular(width: 80, height: 20),
          SizedBox(height: 8),
          ShimmerLoader.rectangular(width: 110, height: 12),
        ],
      ),
    );
  }
}