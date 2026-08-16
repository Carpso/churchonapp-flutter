import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';

class SosAlertsManagementScreen extends ConsumerStatefulWidget {
  const SosAlertsManagementScreen({super.key});

  @override
  ConsumerState<SosAlertsManagementScreen> createState() => _SosAlertsManagementScreenState();
}

class _SosAlertsManagementScreenState extends ConsumerState<SosAlertsManagementScreen> {
  String _selectedFilter = 'active'; // 'all', 'active', 'resolved', 'false_alarm'

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    dynamic query = client.from('sos_alerts').select('*, profiles(full_name)');
    if (_selectedFilter != 'all') {
      query = query.eq('status', _selectedFilter);
    }
    query = query.order('created_at', ascending: false);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Emergency SOS Manager", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildFilterTabs(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: query.then((value) => List<Map<String, dynamic>>.from(value)),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: ListSkeleton());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
                }
                final alerts = snapshot.data ?? [];
                if (alerts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.shieldAlert, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text("No $_selectedFilter emergency alerts found", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: alerts.length,
                    itemBuilder: (context, idx) {
                      final alert = alerts[idx];
                      return _buildAlertCard(alert);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final filters = [
      {'id': 'active', 'label': 'Active'},
      {'id': 'resolved', 'label': 'Resolved'},
      {'id': 'false_alarm', 'label': 'False Alarm'},
      {'id': 'all', 'label': 'All'},
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: filters.map((f) {
          final isSelected = _selectedFilter == f['id'];
          return ChoiceChip(
            label: Text(f['label'] as String),
            selected: isSelected,
            onSelected: (val) {
              if (val) {
                setState(() => _selectedFilter = f['id'] as String);
              }
            },
            selectedColor: Colors.red.shade800,
            labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
            backgroundColor: Colors.grey.shade100,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final id = alert['id'];
    final contactName = alert['contact_name'] ?? 'Unknown Contact';
    final contactPhone = alert['contact_phone'] ?? '';
    final lat = alert['lat'];
    final lng = alert['lng'];
    final status = alert['status'] ?? 'active';
    final createdAt = DateTime.tryParse(alert['created_at'] ?? '') ?? DateTime.now();
    final timeString = "${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')} (${createdAt.day}/${createdAt.month})";
    
    final profiles = alert['profiles'] as Map<String, dynamic>?;
    final senderName = profiles?['full_name'] ?? 'Unknown Member';

    Color statusColor = Colors.red;
    if (status == 'resolved') statusColor = Colors.green;
    if (status == 'false_alarm') statusColor = Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.toString().toUpperCase(),
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                Text(
                  timeString,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              "Sender: $senderName",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              "Emergency Contact: $contactName ($contactPhone)",
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
            if (lat != null && lng != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(LucideIcons.mapPin, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text("Coordinates: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
            const Divider(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (contactPhone.isNotEmpty) ...[
                  IconButton(
                    icon: Icon(LucideIcons.phone, color: Theme.of(context).primaryColor),
                    onPressed: () async {
                      final url = Uri.parse("tel:$contactPhone");
                      if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.inAppWebView);
                    },
                  ),
                  const Spacer(),
                ],
                if (status == 'active') ...[
                  TextButton.icon(
                    icon: const Icon(LucideIcons.check, color: Colors.green),
                    label: const Text("RESOLVE", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    onPressed: () => _updateStatus(id, 'resolved'),
                  ),
                  const SizedBox(width: 10),
                  TextButton.icon(
                    icon: const Icon(LucideIcons.xCircle, color: Colors.grey),
                    label: const Text("FALSE ALARM", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    onPressed: () => _updateStatus(id, 'false_alarm'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(String id, String status) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: ListSkeleton()),
    );
    try {
      await Supabase.instance.client.from('sos_alerts').update({'status': status}).eq('id', id);
      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        setState(() {}); // Reload
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Alert marked as $status"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }
}
