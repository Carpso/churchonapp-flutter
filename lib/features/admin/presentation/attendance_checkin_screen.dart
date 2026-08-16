import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class AttendanceCheckinScreen extends ConsumerStatefulWidget {
  const AttendanceCheckinScreen({super.key});

  @override
  ConsumerState<AttendanceCheckinScreen> createState() => _AttendanceCheckinScreenState();
}

class _AttendanceCheckinScreenState extends ConsumerState<AttendanceCheckinScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _selectedEvent;
  List<Map<String, dynamic>> _registrations = [];
  int _attendeeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    final tenantId = ref.read(profileProvider).value?.tenantId;
    if (tenantId == null) { setState(() => _isLoading = false); return; }
    try {
      final res = await Supabase.instance.client
          .from('events')
          .select('id, title, date, location, attendee_count, max_attendees')
          .eq('tenant_id', tenantId)
          .gte('date', DateTime.now().subtract(const Duration(days: 7)).toIso8601String())
          .order('date', ascending: false);
      if (mounted) setState(() { _events = List<Map<String, dynamic>>.from(res); _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectEvent(Map<String, dynamic> event) async {
    setState(() { _selectedEvent = event; _isLoading = true; });
    try {
      final res = await Supabase.instance.client
          .from('event_registrations')
          .select('id, user_id, status, created_at')
          .eq('event_id', event['id'] as String);
      if (mounted) {
        setState(() {
          _registrations = List<Map<String, dynamic>>.from(res);
          _attendeeCount = (event['attendee_count'] as num?)?.toInt() ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _recordCheckin(String registrationId) async {
    try {
      await Supabase.instance.client.rpc('record_event_checkin', params: {
        'p_event_id': _selectedEvent!['id'],
        'p_registration_id': registrationId,
        'p_user_id': ref.read(profileProvider).value?.id ?? '',
        'p_device_info': 'pastor_dashboard',
      });
      await _selectEvent(_selectedEvent!);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_selectedEvent != null ? "Check-in: ${_selectedEvent!['title']}" : "Attendance Check-in", style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black87,
        elevation: 0,
        leading: _selectedEvent != null
            ? IconButton(icon: const Icon(LucideIcons.arrowLeft), onPressed: () => setState(() => _selectedEvent = null))
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _selectedEvent != null
              ? _buildCheckinView(theme)
              : _buildEventList(theme),
    );
  }

  Widget _buildEventList(ThemeData theme) {
    if (_events.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(40), child: Text("No events found", style: TextStyle(color: Colors.grey.shade500))));
    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _events.length,
        itemBuilder: (_, i) {
          final e = _events[i];
          final title = e['title'] ?? 'Untitled';
          final dateStr = e['date']?.toString() ?? '';
          final date = DateFormat('MMM d, yyyy').format(DateTime.tryParse(dateStr) ?? DateTime.now());
          final count = (e['attendee_count'] as num?)?.toInt() ?? 0;
          final max = (e['max_attendees'] as num?)?.toInt();
          return GestureDetector(
            onTap: () => _selectEvent(e),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(LucideIcons.calendarCheck, color: Theme.of(context).primaryColor)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(date, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                ])),
                Text("$count${max != null ? '/$max' : ''}", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                const SizedBox(width: 8),
                const Icon(LucideIcons.chevronRight, size: 16, color: Colors.grey),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCheckinView(ThemeData theme) {
    final total = _registrations.length;
    final checkedIn = _registrations.where((r) => r['status'] == 'checked_in').length;
    return RefreshIndicator(
      onRefresh: () => _selectEvent(_selectedEvent!),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Column(children: [
                Text("$_attendeeCount", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: Theme.of(context).primaryColor)),
                Text("Attendees", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
              ]),
              Column(children: [
                Text("$checkedIn", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: Colors.green.shade700)),
                Text("Checked In", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
              ]),
              Column(children: [
                Text("${total - checkedIn}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: Colors.orange.shade700)),
                Text("Pending", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          const Text("Registrations", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          ..._registrations.map((r) {
            final status = r['status'] as String? ?? 'registered';
            final isCheckedIn = status == 'checked_in';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(isCheckedIn ? LucideIcons.checkCircle : LucideIcons.clock, size: 18, color: isCheckedIn ? Colors.green : Colors.orange),
                const SizedBox(width: 12),
                Expanded(child: Text("Registration #${r['user_id'].toString().substring(0, 8)}", style: const TextStyle(fontSize: 12))),
                if (!isCheckedIn)
                  GestureDetector(
                    onTap: () => _recordCheckin(r['id'] as String),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Text("Check In", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 11)),
                    ),
                  ),
              ]),
            );
          }),
        ],
      ),
    );
  }
}
